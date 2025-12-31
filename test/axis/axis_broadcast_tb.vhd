--##############################################################################
--# File : axis_broadcast_tb.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! AXIS broadcast testbench
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

entity axis_broadcast_tb is
  generic (
    RUNNER_CFG      : string;
    G_ENABLE_JITTER : boolean := true
  );
end entity;

architecture tb of axis_broadcast_tb is

  -- TB Constants
  constant RESET_TIME  : time    := 50 ns;
  constant CLK_PERIOD  : time    := 5 ns;
  constant NUM_OUTPUTS : integer := 3;
  constant KW          : integer := 2;
  constant DW          : integer := 16;
  constant UW          : integer := 8;
  constant DBW         : integer := DW / KW;
  constant UBW         : integer := UW / KW;

  -- TB Signals
  signal clk   : std_ulogic := '1';
  signal arst  : std_ulogic := '1';
  signal srst  : std_ulogic := '1';
  signal srstn : std_ulogic := '0';

  -- DUT Signals
  signal s_axis : axis_t (
    tdata(DW - 1 downto 0),
    tkeep(KW - 1 downto 0),
    tuser(UW - 1 downto 0)
  );

  signal m_axis : axis_arr_t(0 to NUM_OUTPUTS - 1)(
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

  constant DATA_QUEUE : queue_t := new_queue;
  constant USER_QUEUE : queue_t := new_queue;

  constant REF_DATA_QUEUES : queue_vec_t(m_axis'range) :=
    get_new_queues(m_axis'length);
  constant REF_USER_QUEUES : queue_vec_t(m_axis'range) :=
    get_new_queues(m_axis'length);

  signal num_packets_checked : nat_arr_t(m_axis'range) := (others => 0);

begin

  -- ---------------------------------------------------------------------------
  test_runner_watchdog(runner, 100 us);

  prc_main : process is

    variable rnd       : randomptype;
    variable num_tests : nat_arr_t(m_axis'range) := (others => 0);

    procedure send_random is

      constant PACKET_LENGTH_BYTES : natural := rnd.Uniform(1, 5 * KW);

      variable data        : integer_array_t := null_integer_array;
      variable data_copy_0 : integer_array_t := null_integer_array;
      variable data_copy_1 : integer_array_t := null_integer_array;
      variable data_copy_2 : integer_array_t := null_integer_array;

      variable user : integer_array_t := new_1d (
        length    => PACKET_LENGTH_BYTES,
        bit_width => UBW,
        is_signed => false
      );

      variable user_copy_0 : integer_array_t := new_1d (
        length    => PACKET_LENGTH_BYTES,
        bit_width => UBW,
        is_signed => false
      );

      variable user_copy_1 : integer_array_t := new_1d (
        length    => PACKET_LENGTH_BYTES,
        bit_width => UBW,
        is_signed => false
      );

      variable user_copy_2 : integer_array_t := new_1d (
        length    => PACKET_LENGTH_BYTES,
        bit_width => UBW,
        is_signed => false
      );

    begin

      -- Random test data packet
      random_integer_array (
        rnd           => rnd,
        integer_array => data,
        width         => PACKET_LENGTH_BYTES,
        bits_per_word => DBW,
        is_signed     => false
      );
      data_copy_0 := copy(data);
      data_copy_1 := copy(data);
      data_copy_2 := copy(data);
      push_ref(DATA_QUEUE, data);
      push_ref(REF_DATA_QUEUES(0), data_copy_0);
      push_ref(REF_DATA_QUEUES(1), data_copy_1);
      push_ref(REF_DATA_QUEUES(2), data_copy_2);

      -- Random user data packet
      random_integer_array (
        rnd           => rnd,
        integer_array => user,
        width         => PACKET_LENGTH_BYTES,
        bits_per_word => UBW,
        is_signed     => false
      );
      user_copy_0 := copy(user);
      user_copy_1 := copy(user);
      user_copy_2 := copy(user);
      push_ref(USER_QUEUE, user);
      push_ref(REF_USER_QUEUES(0), user_copy_0);
      push_ref(REF_USER_QUEUES(1), user_copy_1);
      push_ref(REF_USER_QUEUES(2), user_copy_2);

      num_tests(0) := num_tests(0) + 1;
      num_tests(1) := num_tests(1) + 1;
      num_tests(2) := num_tests(2) + 1;

    end procedure;

  begin

    test_runner_setup(runner, RUNNER_CFG);
    rnd.InitSeed(get_string_seed(RUNNER_CFG));

    arst <= '1';
    wait for RESET_TIME;
    arst <= '0';
    wait until rising_edge(clk);

    if run("test_random_data") then
      for test_idx in 0 to 50 loop
        send_random;
      end loop;
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
  u_axis_broadcast : entity work.axis_broadcast
  port map (
    clk    => clk,
    srst   => srst,
    s_axis => s_axis,
    m_axis => m_axis
  );

  u_bfm_axis_man : entity work.bfm_axis_man
  generic map (
    G_DATA_QUEUE   => DATA_QUEUE,
    G_USER_QUEUE   => USER_QUEUE,
    G_STALL_CONFIG => STALL_CFG
  )
  port map (
    clk    => clk,
    m_axis => s_axis
  );

  gen_subs : for i in m_axis'range generate

    u_bfm_axis_sub : entity work.bfm_axis_sub
    generic map (
      G_REF_DATA_QUEUE => REF_DATA_QUEUES(i),
      G_REF_USER_QUEUE => REF_USER_QUEUES(i),
      G_STALL_CONFIG   => STALL_CFG
    )
    port map (
      clk                 => clk,
      s_axis              => m_axis(i),
      num_packets_checked => num_packets_checked(i)
    );

  end generate;

end architecture;
