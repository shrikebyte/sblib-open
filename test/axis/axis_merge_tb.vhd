--##############################################################################
--# File : axis_merge_tb.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! AXIS merge testbench
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
use work.stall_bfm_pkg.stall_configuration_t;
use work.queue_bfm_pkg.get_new_queues;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_merge_tb is
  generic (
    RUNNER_CFG      : string;
    G_ENABLE_JITTER : boolean := true;
    G_DW            : integer := 16;
    G_KW            : integer := 2
  );
end entity;

architecture tb of axis_merge_tb is

  -- TB Constants
  constant RESET_TIME : time := 50 ns;
  constant CLK_PERIOD : time := 5 ns;

  constant BW : integer := G_DW / G_KW;
  constant UW : integer := 8;

  -- TB Signals
  signal clk   : std_ulogic := '1';
  signal arst  : std_ulogic := '1';
  signal srst  : std_ulogic := '1';
  signal srstn : std_ulogic := '0';

  -- DUT Signals
  signal merge_enable : std_ulogic := '0';

  signal s0_axis : axis_t (
                           tdata(G_DW - 1 downto 0),
                           tkeep(G_KW - 1 downto 0),
                           tuser(UW - 1 downto 0)
                         );

  signal s1_axis : axis_t (
                           tdata(G_DW - 1 downto 0),
                           tkeep(G_KW - 1 downto 0),
                           tuser(UW - 1 downto 0)
                         );

  signal m_axis : axis_t (
                           tdata(G_DW - 1 downto 0),
                           tkeep(G_KW - 1 downto 0),
                           tuser(UW - 1 downto 0)
                         );

  function to_real (
    b : boolean
  ) return real is
  begin
    if b then
      return 1.0;
    else
      return 0.0;
    end if;
  end function;

  -- ---------------------------------------------------------------------------
  -- Testbench BFMs
  constant STALL_CFG : stall_configuration_t := (
    stall_probability => 0.2 * to_real(G_ENABLE_JITTER),
    min_stall_cycles  => 1,
    max_stall_cycles  => 3
  );

  constant S0_INPUT_DATA_QUEUE  : queue_t := new_queue;
  constant S1_INPUT_DATA_QUEUE  : queue_t := new_queue;
  constant REF_DATA_QUEUE : queue_t := new_queue;

  signal num_packets_checked : natural := 0;

begin

  -- ---------------------------------------------------------------------------
  test_runner_watchdog(runner, 100 us);

  prc_main : process is
    variable rnd : randomptype;

    variable num_tests : natural := 0;

    procedure send_random(constant merge_enable : boolean) is

      constant S0_PACKET_LENGTH_BYTES : natural := rnd.Uniform(1, 3 * G_KW);
      constant S1_PACKET_LENGTH_BYTES : natural := rnd.Uniform(1, 3 * G_KW);

      variable s0_data : integer_array_t := null_integer_array;
      variable s1_data : integer_array_t := null_integer_array;

      variable m_data : integer_array_t := new_1d (
        length => 0,
        bit_width => BW,
        is_signed => false
      );

    begin

      -- Random s0 data packet
      random_integer_array (
                            rnd           => rnd,
                            integer_array => s0_data,
                            width         => S0_PACKET_LENGTH_BYTES,
                            bits_per_word => BW,
                            is_signed     => false
                          );
      

      -- Random s1 data packet
      random_integer_array (
                            rnd           => rnd,
                            integer_array => s1_data,
                            width         => S1_PACKET_LENGTH_BYTES,
                            bits_per_word => BW,
                            is_signed     => false
                          );

      -- Reference data packet
      for i in 0 to S0_PACKET_LENGTH_BYTES - 1 loop
        append(m_data, get(s0_data, i));
      end loop;
      
      if merge_enable then
        for i in 0 to S1_PACKET_LENGTH_BYTES - 1 loop
          append(m_data, get(s1_data, i));
        end loop;
      end if;

      -- Push data to queues
      push_ref(S1_INPUT_DATA_QUEUE, s1_data);
      push_ref(S0_INPUT_DATA_QUEUE, s0_data);
      push_ref(REF_DATA_QUEUE, m_data);

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
      merge_enable <= '1';
      wait until rising_edge(clk);
      for test_idx in 0 to 50 loop
        send_random(true);
      end loop;

    elsif run("test_random_data_passthru") then
      merge_enable <= '0';
      wait until rising_edge(clk);
      for test_idx in 0 to 50 loop
        send_random(false);
      end loop;
    end if;

    wait until num_packets_checked = num_tests and rising_edge(clk);

    test_runner_cleanup(runner);
  end process;

  -- ---------------------------------------------------------------------------
  -- Clocks & Resets
  clk <= not clk after CLK_PERIOD / 2;

  prc_srst : process (clk) is begin
    if rising_edge(clk) then
      srst  <= arst;
      srstn <= not arst;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  -- DUT
  u_axis_merge : entity work.axis_merge
  port map (
    clk     => clk,
    srst    => srst,
    merge_enable => merge_enable,
    s0_axis => s0_axis,
    s1_axis => s1_axis,
    m_axis  => m_axis
  );

  u_axi_stream_master_0 : entity work.axi_stream_master
  generic map (
    DATA_WIDTH         => s0_axis.tdata'length,
    DATA_QUEUE         => S0_INPUT_DATA_QUEUE,
    STALL_CONFIG       => STALL_CFG,
    LOGGER_NAME_SUFFIX => " - input 0"
  )
  port map (
    clk => clk,
    --
    ready  => s0_axis.tready,
    valid  => s0_axis.tvalid,
    last   => s0_axis.tlast,
    data   => s0_axis.tdata,
    strobe => s0_axis.tkeep
    --user   => s0_axis.tuser
  );

  u_axi_stream_master_1 : entity work.axi_stream_master
  generic map (
    DATA_WIDTH         => s1_axis.tdata'length,
    DATA_QUEUE         => S1_INPUT_DATA_QUEUE,
    STALL_CONFIG       => STALL_CFG,
    LOGGER_NAME_SUFFIX => " - input 1"
  )
  port map (
    clk => clk,
    --
    ready  => s1_axis.tready,
    valid  => s1_axis.tvalid,
    last   => s1_axis.tlast,
    data   => s1_axis.tdata,
    strobe => s1_axis.tkeep
    --user   => s1_axis.tuser
  );

  axi_stream_slave : entity work.axi_stream_slave
  generic map (
    DATA_WIDTH           => m_axis.tdata'length,
    REFERENCE_DATA_QUEUE => REF_DATA_QUEUE,
    STALL_CONFIG         => STALL_CFG,
    LOGGER_NAME_SUFFIX   => " - result"
  )
  port map (
    clk => clk,
    --
    ready  => m_axis.tready,
    valid  => m_axis.tvalid,
    last   => m_axis.tlast,
    data   => m_axis.tdata,
    strobe => m_axis.tkeep,
    --user   => m_axis.tuser,
    --
    num_packets_checked => num_packets_checked
  );

end architecture;
