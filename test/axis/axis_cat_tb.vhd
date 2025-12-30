--##############################################################################
--# File : axis_cat_tb.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! AXIS concatenate testbench
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
context vunit_lib.vunit_context;
context vunit_lib.vc_context;
use vunit_lib.random_pkg.all;

library osvvm;
use osvvm.randompkg.all;

use work.util_pkg.all;
use work.axis_pkg.all;
use work.bfm_pkg.all;

entity axis_cat_tb is
  generic (
    RUNNER_CFG      : string;
    G_ENABLE_JITTER : boolean := true;
  );
end entity;

architecture tb of axis_cat_tb is

  -- TB Constants
  constant RESET_TIME : time := 50 ns;
  constant CLK_PERIOD : time := 5 ns;
  constant KW          : integer  := 4;
  constant DW          : integer  := 32;
  constant UW          : integer  := 16;
  constant DBW         : integer  := DW / KW;
  constant UBW         : integer  := UW / KW;

  -- TB Signals
  signal clk   : std_ulogic := '1';
  signal arst  : std_ulogic := '1';
  signal srst  : std_ulogic := '1';
  signal srstn : std_ulogic := '0';

  -- DUT Signals
  signal enable : std_ulogic := '1';

  signal s_axis : axis_arr_t(0 to 1) (
    tdata(DW - 1 downto 0),
    tkeep(KW - 1 downto 0),
    tuser(UW - 1 downto 0)
  );

  signal m_axis : axis_t (
    tdata(DW - 1 downto 0),
    tkeep(KW - 1 downto 0),
    tuser(UW - 1 downto 0)
  );

  -- Testbench BFMs
  constant STALL_CFG : stall_configuration_t := (
    stall_probability => 0.2 * to_real(G_ENABLE_JITTER),
    min_stall_cycles  => 1,
    max_stall_cycles  => 3
  );

  constant S0_DATA_QUEUE  : queue_t := new_queue;
  constant S1_DATA_QUEUE  : queue_t := new_queue;
  constant REF_DATA_QUEUE : queue_t := new_queue;
  constant S0_USER_QUEUE  : queue_t := new_queue;
  constant S1_USER_QUEUE  : queue_t := new_queue;
  constant REF_USER_QUEUE : queue_t := new_queue;

  signal num_packets_checked : natural := 0;

begin

  -- ---------------------------------------------------------------------------
  test_runner_watchdog(runner, 100 us);
  prc_main : process is

    variable rnd : randomptype;
    variable num_tests : natural := 0;

    procedure send_random(constant enable : boolean) is

      constant S0_PACKET_LENGTH_BYTES : natural := rnd.Uniform(1, 3 * KW);
      constant S1_PACKET_LENGTH_BYTES : natural := rnd.Uniform(1, 3 * KW);

      variable s0_data : integer_array_t := null_integer_array;
      variable s1_data : integer_array_t := null_integer_array;
      variable s0_user : integer_array_t := null_integer_array;
      variable s1_user : integer_array_t := null_integer_array;

      variable m_data : integer_array_t := new_1d (
        length => 0,
        bit_width => DBW,
        is_signed => false
      );

      variable m_user : integer_array_t := new_1d (
        length => 0,
        bit_width => UBW,
        is_signed => false
      );

    begin

      -- Random s0 data packet
      random_integer_array (
        rnd           => rnd,
        integer_array => s0_data,
        width         => S0_PACKET_LENGTH_BYTES,
        bits_per_word => DBW,
        is_signed     => false
      );

      -- Random s1 data packet
      random_integer_array (
        rnd           => rnd,
        integer_array => s1_data,
        width         => S1_PACKET_LENGTH_BYTES,
        bits_per_word => DBW,
        is_signed     => false
      );

      -- Reference data packet
      for i in 0 to S0_PACKET_LENGTH_BYTES - 1 loop
        append(m_data, get(s0_data, i));
      end loop;

      if enable then
        for i in 0 to S1_PACKET_LENGTH_BYTES - 1 loop
          append(m_data, get(s1_data, i));
        end loop;
      end if;

      -- Push data to queues
      push_ref(S0_DATA_QUEUE, s0_data);
      push_ref(S1_DATA_QUEUE, s1_data);
      push_ref(REF_DATA_QUEUE, m_data);


      -- Random s0 user packet
      random_integer_array (
        rnd           => rnd,
        integer_array => s0_user,
        width         => S0_PACKET_LENGTH_BYTES,
        bits_per_word => UBW,
        is_signed     => false
      );

      -- Random s1 user packet
      random_integer_array (
        rnd           => rnd,
        integer_array => s1_user,
        width         => S1_PACKET_LENGTH_BYTES,
        bits_per_word => UBW,
        is_signed     => false
      );

      -- Reference user packet
      for i in 0 to S0_PACKET_LENGTH_BYTES - 1 loop
        append(m_user, get(s0_user, i));
      end loop;

      if enable then
        for i in 0 to S1_PACKET_LENGTH_BYTES - 1 loop
          append(m_user, get(s1_user, i));
        end loop;
      end if;

      -- Push user to queues
      push_ref(S0_USER_QUEUE, s0_user);
      push_ref(S1_USER_QUEUE, s1_user);
      push_ref(REF_USER_QUEUE, m_user);

      num_tests := num_tests + 1;

    end procedure;

  begin

    test_runner_setup(runner, RUNNER_CFG);
    rnd.InitSeed(get_string_seed(RUNNER_CFG));

    arst <= '1';
    wait for RESET_TIME;
    arst <= '0';
    wait until rising_edge(clk);

    if run("test_random_data_merge") then
      enable <= '1';
      wait until rising_edge(clk);
      for test_idx in 0 to 50 loop
        send_random(true);
      end loop;

    -- elsif run("test_random_data_passthru") then
    --   enable <= '0';
    --   wait until rising_edge(clk);
    --   for test_idx in 0 to 50 loop
    --     send_random(false);
    --   end loop;
    end if;

    wait until num_packets_checked = num_tests and rising_edge(clk);

    test_runner_cleanup(runner);
  end process;

  -- ---------------------------------------------------------------------------
  prc_srst : process (clk) is begin
    if rising_edge(clk) then
      srst  <= arst;
      srstn <= not arst;
    end if;
  end process;

  clk <= not clk after CLK_PERIOD / 2;

  -- ---------------------------------------------------------------------------
  u_axis_cat : entity work.axis_cat
  port map (
    clk       => clk,
    srst      => srst,
    s_axis    => s_axis,
    m_axis    => m_axis
  );

  u_bfm_axis_man_0 : entity work.bfm_axis_man
  generic map(
    G_DATA_QUEUE   => S0_DATA_QUEUE,
    G_USER_QUEUE   => S0_USER_QUEUE,
    G_STALL_CONFIG => STALL_CFG
  )
  port map(
    clk    => clk,
    m_axis => s_axis(0)
  );

  u_bfm_axis_man_1 : entity work.bfm_axis_man
  generic map(
    G_DATA_QUEUE   => S1_DATA_QUEUE,
    G_USER_QUEUE   => S1_USER_QUEUE,
    G_STALL_CONFIG => STALL_CFG
  )
  port map(
    clk    => clk,
    m_axis => s_axis(1)
  );

  u_bfm_axis_sub : entity work.bfm_axis_sub
  generic map(
    G_REF_DATA_QUEUE => REF_DATA_QUEUE,
    G_REF_USER_QUEUE => REF_USER_QUEUE,
    G_STALL_CONFIG   => STALL_CFG
  )
  port map(
    clk    => clk,
    s_axis => m_axis,
    num_packets_checked => num_packets_checked
  );

end architecture;
