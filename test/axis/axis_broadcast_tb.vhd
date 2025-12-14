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
use work.stall_bfm_pkg.stall_configuration_t;
use work.queue_bfm_pkg.get_new_queues;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_broadcast_tb is
  generic (
    RUNNER_CFG      : string;
    G_ENABLE_JITTER : boolean := true;
  );
end entity;

architecture tb of axis_broadcast_tb is

  -- TB Constants
  constant RESET_TIME : time := 50 ns;
  constant CLK_PERIOD : time := 5 ns;

  constant AXIS_DATA_WIDTH : integer := 16;
  constant AXIS_BYTE_WIDTH : integer := 8;
  constant AXIS_KEEP_WIDTH : integer := AXIS_DATA_WIDTH / AXIS_BYTE_WIDTH;
  constant AXIS_USER_WIDTH : integer := 8;

  constant NUM_M                 : integer := 3;

  -- TB Signals
  signal clk   : std_ulogic := '1';
  signal arst  : std_ulogic := '1';
  signal srst  : std_ulogic := '1';
  signal srstn : std_ulogic := '0';

  -- DUT Signals
  signal s_axis : axis_t (
                           tdata(AXIS_DATA_WIDTH - 1 downto 0),
                           tkeep(AXIS_DATA_WIDTH / 8 - 1 downto 0),
                           tuser(AXIS_USER_WIDTH - 1 downto 0)
                         );

  signal m_axis : axis_arr_t(0 to NUM_M-1) (
    tdata(AXIS_DATA_WIDTH-1 downto 0),
    tkeep(AXIS_DATA_WIDTH/8-1 downto 0),
    tuser(AXIS_USER_WIDTH-1 downto 0)
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

  constant INPUT_DATA_QUEUE, INPUT_USER_QUEUE : queue_t := new_queue;

  constant REF_DATA_QUEUES, REF_USER_QUEUES : queue_vec_t(m_axis'range) := get_new_queues(m_axis'length);  

  signal num_packets_checked : nat_arr_t(m_axis'range) := (others => 0);

begin

  -- ---------------------------------------------------------------------------
  test_runner_watchdog(runner, 100 us);

  prc_main : process is
    variable rnd : randomptype;

    variable num_tests : nat_arr_t(m_axis'range) := (others => 0);

    procedure send_random is

      constant PACKET_LENGTH_BYTES : natural := rnd.Uniform(1, 5 * AXIS_KEEP_WIDTH);

      -- Calculate the integer ceiling division of
      -- PACKET_LENGTH_BYTES / AXIS_KEEP_WIDTH to determine the number of beats
      -- in a packet.
      constant PACKET_LENGTH_BEATS : natural := (PACKET_LENGTH_BYTES + AXIS_KEEP_WIDTH - 1) / AXIS_KEEP_WIDTH;

      variable data, data_copy_0, data_copy_1, data_copy_2: integer_array_t := null_integer_array;
      variable user, user_copy_0, user_copy_1, user_copy_2 : integer_array_t := new_1d (
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
      data_copy_0 := copy(data);
      data_copy_1 := copy(data);
      data_copy_2 := copy(data);
      push_ref(INPUT_DATA_QUEUE, data);
      push_ref(REF_DATA_QUEUES(0), data_copy_0);
      push_ref(REF_DATA_QUEUES(1), data_copy_1);
      push_ref(REF_DATA_QUEUES(2), data_copy_2);

      -- Random user data packet
      random_integer_array (
                            rnd           => rnd,
                            integer_array => user,
                            width         => PACKET_LENGTH_BEATS,
                            bits_per_word => AXIS_BYTE_WIDTH,
                            is_signed     => false
                          );
      user_copy_0 := copy(user);
      user_copy_1 := copy(user);
      user_copy_2 := copy(user);
      push_ref(INPUT_USER_QUEUE, user);
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
  u_axis_broadcast : entity work.axis_broadcast
  port map (
    clk    => clk,
    srst   => srst,
    s_axis => s_axis,
    m_axis => m_axis
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

  -- ---------------------------------------------------------------------------
  gen_bfms : for i in m_axis'range generate

    axi_stream_slave_inst : entity work.axi_stream_slave
    generic map (
      data_width => s_axis.tdata'length,
      reference_data_queue => REF_DATA_QUEUES(i),
      user_width => s_axis.tuser'length,
      reference_user_queue => REF_USER_QUEUES(i),
      stall_config => STALL_CFG,
      logger_name_suffix => " - result"
    )
    port map (
      clk    => clk,
      --
      ready  => m_axis(i).tready,
      valid  => m_axis(i).tvalid,
      last   => m_axis(i).tlast,
      data   => m_axis(i).tdata,
      strobe => m_axis(i).tkeep,
      user   => m_axis(i).tuser,
      --
      num_packets_checked => num_packets_checked(i)
    );

  end generate;

end architecture;
