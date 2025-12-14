--##############################################################################
--# File : axis_mux_tb.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! AXIS mux testbench
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

entity axis_mux_tb is
  generic (
    RUNNER_CFG        : string;
    G_ENABLE_JITTER   : boolean := true;
    G_LOW_AREA        : boolean := false;
  );
end entity;

architecture tb of axis_mux_tb is

  -- TB Constants
  constant RESET_TIME            : time    := 25 ns;
  constant CLK_PERIOD            : time    := 5 ns;

  constant AXIS_DATA_WIDTH       : integer := 16;
  constant AXIS_BYTE_WIDTH       : integer := 8;
  constant AXIS_KEEP_WIDTH       : integer := AXIS_DATA_WIDTH / AXIS_BYTE_WIDTH;
  constant AXIS_USER_WIDTH       : integer := 8;
  constant NUM_S                 : integer := 4;

  -- TB Signals
  signal clk          : std_ulogic := '1';
  signal arst         : std_ulogic := '1';
  signal srst         : std_ulogic := '1';
  signal srstn        : std_ulogic := '0';

  -- DUT Signals
  signal s_axis : axis_arr_t(0 to NUM_S-1) (
    tdata(AXIS_DATA_WIDTH-1 downto 0),
    tkeep(AXIS_DATA_WIDTH/8-1 downto 0),
    tuser(AXIS_USER_WIDTH-1 downto 0)
  );

  signal m_axis : axis_t (
    tdata(AXIS_DATA_WIDTH-1 downto 0),
    tkeep(AXIS_DATA_WIDTH/8-1 downto 0),
    tuser(AXIS_USER_WIDTH-1 downto 0)
  );

  signal sel : integer range s_axis'range := s_axis'low;

  function to_real(b : boolean) return real is
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

  constant INPUT_DATA_QUEUES, REF_DATA_QUEUES, INPUT_USER_QUEUES, REF_USER_QUEUES : queue_vec_t(s_axis'range) := get_new_queues(s_axis'length);  

  signal num_packets_checked : nat_arr_t(s_axis'range) := (others => 0);

  signal bfm_m_tvalid, bfm_m_tready : std_ulogic_vector(s_axis'range) := (others => '0');

begin

  -- ---------------------------------------------------------------------------
  test_runner_watchdog(runner, 100 us);
  prc_main : process
    variable rnd : RandomPType;

    variable num_tests : nat_arr_t(s_axis'range) := (others => 0);

    procedure send_random is

      constant INPUT_IDX : natural := rnd.Uniform(s_axis'low, s_axis'high);
      constant PACKET_LENGTH_BYTES : natural := rnd.Uniform(1, 5 * AXIS_KEEP_WIDTH);

      -- Calculate the integer ceiling division of 
      -- PACKET_LENGTH_BYTES / AXIS_KEEP_WIDTH to determine the number of beats
      -- in a packet.
      constant PACKET_LENGTH_BEATS : natural := (PACKET_LENGTH_BYTES + AXIS_KEEP_WIDTH - 1) / AXIS_KEEP_WIDTH;

      variable data, data_copy : integer_array_t := null_integer_array;
      variable user, user_copy :  integer_array_t := new_1d (
        length => PACKET_LENGTH_BEATS,
        bit_width => AXIS_BYTE_WIDTH,
        is_signed => false
      );

    begin

      assert INPUT_IDX >= 0 and INPUT_IDX < 2**AXIS_USER_WIDTH
        report "ERROR: INPUT_IDX > 0 and INPUT_IDX <" & to_string(2**AXIS_USER_WIDTH)
        severity error;      

      -- Random test data packet
      random_integer_array (
        rnd => rnd,
        integer_array => data,
        width => PACKET_LENGTH_BYTES,
        bits_per_word => AXIS_BYTE_WIDTH,
        is_signed => false
      );
      data_copy := copy(data);
      push_ref(INPUT_DATA_QUEUES(INPUT_IDX), data);
      push_ref(REF_DATA_QUEUES(INPUT_IDX), data_copy);

      -- Assign the input channel number to tuser. This will be used to route
      -- result packets to the appropriate checker.
      for i in 0 to PACKET_LENGTH_BEATS - 1 loop
        set(user, i, INPUT_IDX);
      end loop;
      user_copy := copy(user);
      push_ref(INPUT_USER_QUEUES(INPUT_IDX), user);
      push_ref(REF_USER_QUEUES(INPUT_IDX), user_copy);

      num_tests(INPUT_IDX) := num_tests(INPUT_IDX) + 1;

    end procedure;

  begin

    test_runner_setup(runner, runner_cfg);
    rnd.InitSeed(get_string_seed(runner_cfg));

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
  -- TODO: s_axis(0), a_axis(1), etc - Add explicit NUM_S generic if required
  u_axis_mux : entity work.axis_mux
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

  -- ---------------------------------------------------------------------------
  gen_bfms : for i in s_axis'range generate

    -- -------------------------------------------------------------------------
    -- TODO: Rename to axis_manager_bfm
    -- TODO: Change generic naming
    -- TODO: Change to use axis interface
    axi_stream_master_inst : entity work.axi_stream_master
    generic map (
      data_width         => s_axis(i).tdata'length,
      data_queue         => INPUT_DATA_QUEUES(i),
      user_width         => s_axis(i).tuser'length,
      user_queue         => INPUT_USER_QUEUES(i),
      stall_config       => STALL_CFG,
      logger_name_suffix => " - input #" & to_string(i)
    )
    port map (
      clk     => clk,
      --
      ready   => s_axis(i).tready,
      valid   => s_axis(i).tvalid,
      last    => s_axis(i).tlast,
      data    => s_axis(i).tdata,
      strobe  => s_axis(i).tkeep,
      user   =>  s_axis(i).tuser
    );

    ----------------------------------------------------------------------------
    -- TODO: Rename to axis_subordinate_bfm
    -- TODO: Change generic naming
    -- TODO: Change to use axis interface
    axi_stream_slave_inst : entity work.axi_stream_slave
    generic map (
      data_width => m_axis.tdata'length,
      reference_data_queue => REF_DATA_QUEUES(i),
      user_width => m_axis.tuser'length,
      reference_user_queue => REF_USER_QUEUES(i),
      stall_config => STALL_CFG,
      logger_name_suffix => " - result"
    )
    port map (
      clk    => clk,
      --
      ready  => bfm_m_tready(i),
      valid  => bfm_m_tvalid(i),
      last   => m_axis.tlast,
      data   => m_axis.tdata,
      strobe => m_axis.tkeep,
      user   => m_axis.tuser,
      --
      num_packets_checked => num_packets_checked(i)
    );

  end generate;

  ------------------------------------------------------------------------------
  -- Assign handshaking signals to/from the BFM that corresponds to the result ID.
  -- Due to the arbitration we do not know in what order the input packets will be passed on.
  -- Hence there must be one reference queue for each input.
  prc_assign_handshake : process(all) begin

    bfm_m_tvalid <= (others => '0');
    m_axis.tready <= '0';

    if m_axis.tvalid then
      bfm_m_tvalid(to_integer(unsigned(m_axis.tuser))) <= m_axis.tvalid;
      m_axis.tready <= bfm_m_tready(to_integer(unsigned(m_axis.tuser)));
    end if;

  end process;

  -- Use randomly changing values for sel
  prc_sel : process
    variable rnd : RandomPType;
  begin
    rnd.InitSeed(get_string_seed(runner_cfg));

    while true loop
      wait until rising_edge(clk);
      sel <= rnd.Uniform(s_axis'low, s_axis'high);
    end loop;

  end process;

end architecture;
