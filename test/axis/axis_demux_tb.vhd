--##############################################################################
--# File : axis_demux_tb.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! AXIS de-mux testbench
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

entity axis_demux_tb is
  generic (
    RUNNER_CFG      : string;
    G_LOW_AREA      : boolean := false;
    G_ENABLE_JITTER : boolean := true
  );
end entity;

architecture tb of axis_demux_tb is

  -- TB Constants
  constant RESET_TIME : time := 50 ns;
  constant CLK_PERIOD : time := 5 ns;

  constant AXIS_DATA_WIDTH : integer := 16;
  constant AXIS_BYTE_WIDTH : integer := 8;
  constant AXIS_KEEP_WIDTH : integer := AXIS_DATA_WIDTH / AXIS_BYTE_WIDTH;
  constant AXIS_USER_WIDTH : integer := 8;
  constant NUM_CH          : integer := 4;

  -- TB Signals
  signal clk   : std_ulogic := '1';
  signal arst  : std_ulogic := '1';
  signal srst  : std_ulogic := '1';
  signal srstn : std_ulogic := '0';

  -- DUT Signals
  signal s_axis : axis_t (
    tdata(AXIS_DATA_WIDTH - 1 downto 0),
    tkeep(AXIS_KEEP_WIDTH - 1 downto 0),
    tuser(AXIS_USER_WIDTH - 1 downto 0)
  );

  signal m_axis : axis_arr_t (0 to NUM_CH-1)(
    tdata(AXIS_DATA_WIDTH - 1 downto 0),
    tkeep(AXIS_KEEP_WIDTH - 1 downto 0),
    tuser(AXIS_USER_WIDTH - 1 downto 0)
  );

  signal sel : integer range m_axis'range := m_axis'low;

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

  signal bfm_axis : axis_t (
    tdata(AXIS_DATA_WIDTH - 1 downto 0),
    tkeep(AXIS_DATA_WIDTH / 8 - 1 downto 0),
    tuser(AXIS_USER_WIDTH - 1 downto 0)
  );

  constant INPUT_DATA_QUEUE, REF_DATA_QUEUE, INPUT_USER_QUEUE, REF_USER_QUEUE : queue_t := new_queue;

  signal num_packets_checked : natural := 0;

  signal m_axis_tvalid : std_ulogic_vector(m_axis'range);

begin

  -- ---------------------------------------------------------------------------
  test_runner_watchdog(runner, 100 us);

  prc_main : process is
    variable rnd : randomptype;

    variable num_tests : natural := 0;

    procedure send_random is

      constant PACKET_LENGTH_BYTES : natural := rnd.Uniform(1, 5 * AXIS_KEEP_WIDTH);

      -- Calculate the integer ceiling division of
      -- PACKET_LENGTH_BYTES / AXIS_KEEP_WIDTH to determine the number of beats
      -- in a packet.
      constant PACKET_LENGTH_BEATS : natural := (PACKET_LENGTH_BYTES + AXIS_KEEP_WIDTH - 1) / AXIS_KEEP_WIDTH;

      variable data, data_copy : integer_array_t := null_integer_array;
      variable user, user_copy : integer_array_t := new_1d (
                                                             length => PACKET_LENGTH_BEATS,
                                                             bit_width => AXIS_BYTE_WIDTH,
                                                             is_signed => false
                                                           );

    begin

      -- Random test data packet
      random_integer_array (
                            rnd           => rnd,
                            integer_array => data,
                            width         => PACKET_LENGTH_BYTES,
                            bits_per_word => AXIS_BYTE_WIDTH,
                            is_signed     => false
                          );
      data_copy := copy(data);
      push_ref(INPUT_DATA_QUEUE, data);
      push_ref(REF_DATA_QUEUE, data_copy);

      -- Random user data packet
      random_integer_array (
                            rnd           => rnd,
                            integer_array => user,
                            width         => PACKET_LENGTH_BEATS,
                            bits_per_word => AXIS_BYTE_WIDTH,
                            is_signed     => false
                          );
      user_copy := copy(user);
      push_ref(INPUT_USER_QUEUE, user);
      push_ref(REF_USER_QUEUE, user_copy);

      num_tests := num_tests + 1;

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
  u_axis_demux : entity work.axis_demux
  generic map (
    G_LOW_AREA => G_LOW_AREA
  )
  port map (
    clk    => clk,
    srst   => srst,
    s_axis => s_axis,
    m_axis => m_axis,
    sel    => sel
  );

  axi_stream_master_inst : entity work.axi_stream_master
  generic map (
    DATA_WIDTH         => s_axis.tdata'length,
    DATA_QUEUE         => INPUT_DATA_QUEUE,
    USER_WIDTH         => s_axis.tuser'length,
    USER_QUEUE         => INPUT_USER_QUEUE,
    STALL_CONFIG       => STALL_CFG,
    LOGGER_NAME_SUFFIX => " - input"
  )
  port map (
    clk => clk,
    --
    ready  => s_axis.tready,
    valid  => s_axis.tvalid,
    last   => s_axis.tlast,
    data   => s_axis.tdata,
    strobe => s_axis.tkeep,
    user   => s_axis.tuser
  );

  axi_stream_slave_inst : entity work.axi_stream_slave
  generic map (
    DATA_WIDTH           => bfm_axis.tdata'length,
    REFERENCE_DATA_QUEUE => REF_DATA_QUEUE,
    USER_WIDTH           => bfm_axis.tuser'length,
    REFERENCE_USER_QUEUE => REF_USER_QUEUE,
    STALL_CONFIG         => STALL_CFG,
    LOGGER_NAME_SUFFIX   => " - result"
  )
  port map (
    clk => clk,
    --
    ready  => bfm_axis.tready,
    valid  => bfm_axis.tvalid,
    last   => bfm_axis.tlast,
    data   => bfm_axis.tdata,
    strobe => bfm_axis.tkeep,
    user   => bfm_axis.tuser,
    --
    num_packets_checked => num_packets_checked
  );

  -- Squish the output streams into one input stream for the checker.
  -- We know that that module will only assert one of the valid channels at a
  -- time, so this will work.
  prc_assign_handshake : process(all) begin

    bfm_axis.tvalid <= or m_axis_tvalid;

    bfm_axis.tlast <= 'X';
    bfm_axis.tdata <= (others => 'X');
    bfm_axis.tkeep <=  (others => 'X');
    bfm_axis.tuser <=  (others => 'X');

    for i in m_axis'range loop
      if m_axis(i).tvalid then
        bfm_axis.tlast <= m_axis(i).tlast;
        bfm_axis.tdata <= m_axis(i).tdata;
        bfm_axis.tkeep <= m_axis(i).tkeep;
        bfm_axis.tuser <= m_axis(i).tuser;
      end if;
    end loop;
  end process;

  gen_m_axis_tb : for i in m_axis'range generate
    m_axis_tvalid(i) <= m_axis(i).tvalid;
    m_axis(i).tready <= bfm_axis.tready;
  end generate;

  -- Use randomly changing values for sel
  prc_sel : process
    variable rnd : RandomPType;
  begin
    rnd.InitSeed(get_string_seed(runner_cfg));

    while true loop
      wait until rising_edge(clk);
      sel <= rnd.Uniform(m_axis'low, m_axis'high);
    end loop;

  end process;

end architecture;
