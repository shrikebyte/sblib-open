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

use work.util_pkg.all;
use work.axis_pkg.all;
use work.bfm_pkg.all;

entity axis_mux_tb is
  generic (
    RUNNER_CFG        : string;
    G_ENABLE_JITTER   : boolean := true;
  );
end entity;

architecture tb of axis_mux_tb is

  -- TB Constants
  constant RESET_TIME  : time     := 50 ns;
  constant CLK_PERIOD  : time     := 5 ns;
  constant NUM_INPUTS  : integer  := 4;
  constant KW          : integer  := 2;
  constant DW          : integer  := 16;
  constant UW          : integer  := 8;
  constant DBW         : integer  := DW / KW;
  constant UBW         : integer  := UW / KW;

  -- TB Signals
  signal clk          : std_ulogic := '1';
  signal arst         : std_ulogic := '1';
  signal srst         : std_ulogic := '1';
  signal srstn        : std_ulogic := '0';

  -- DUT Signals
  signal s_axis : axis_arr_t(0 to NUM_INPUTS - 1)(
    tdata(DW-1 downto 0),
    tkeep(KW-1 downto 0),
    tuser(UW-1 downto 0)
  );

  signal m_axis : axis_t (
    tdata(DW-1 downto 0),
    tkeep(KW-1 downto 0),
    tuser(UW-1 downto 0)
  );

  signal sel : integer range s_axis'range := s_axis'low;

  -- Testbench BFMs
  constant STALL_CFG : stall_configuration_t := (
    stall_probability => 0.2 * to_real(G_ENABLE_JITTER),
    min_stall_cycles  => 1,
    max_stall_cycles  => 3
  );

  constant DATA_QUEUES : queue_vec_t(s_axis'range) :=
    get_new_queues(s_axis'length);
  constant USER_QUEUES  : queue_vec_t(s_axis'range) :=
    get_new_queues(s_axis'length);
  constant REF_DATA_QUEUES  : queue_vec_t(s_axis'range) :=
    get_new_queues(s_axis'length);
  constant REF_USER_QUEUES : queue_vec_t(s_axis'range) :=
    get_new_queues(s_axis'length);

  signal num_packets_checked : nat_arr_t(s_axis'range)  := (others => 0);
  signal bfm_m_tvalid : std_ulogic_vector(s_axis'range) := (others => '0');
  signal bfm_m_tready : std_ulogic_vector(s_axis'range) := (others => '0');

begin

  -- ---------------------------------------------------------------------------
  test_runner_watchdog(runner, 100 us);
  prc_main : process

    variable rnd : RandomPType;
    variable num_tests : nat_arr_t(s_axis'range) := (others => 0);

    procedure send_random is

      constant INPUT_IDX : natural := rnd.Uniform(s_axis'low, s_axis'high);
      constant PACKET_LENGTH_BYTES : natural := rnd.Uniform(1, 5 * KW);

      variable data : integer_array_t := null_integer_array;
      variable data_copy : integer_array_t := null_integer_array;

      variable user :  integer_array_t := new_1d (
        length => PACKET_LENGTH_BYTES,
        bit_width => UBW,
        is_signed => false
      );

      variable user_copy :  integer_array_t := new_1d (
        length => PACKET_LENGTH_BYTES,
        bit_width => UBW,
        is_signed => false
      );

    begin

      assert INPUT_IDX >= 0 and INPUT_IDX < 2**UW
        report "ERROR: INPUT_IDX > 0 and INPUT_IDX <" & to_string(2**UW)
        severity error;

      -- Random test data packet
      random_integer_array (
        rnd => rnd,
        integer_array => data,
        width => PACKET_LENGTH_BYTES,
        bits_per_word => DBW,
        is_signed => false
      );
      data_copy := copy(data);
      push_ref(DATA_QUEUES(INPUT_IDX), data);
      push_ref(REF_DATA_QUEUES(INPUT_IDX), data_copy);

      -- Assign the input channel number to tuser. This will be used to route
      -- result packets to the appropriate checker.
      for i in 0 to PACKET_LENGTH_BYTES - 1 loop
        set(user, i, INPUT_IDX);
      end loop;
      user_copy := copy(user);
      push_ref(USER_QUEUES(INPUT_IDX), user);
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
  prc_srst : process (clk) is begin
    if rising_edge(clk) then
      srst  <= arst;
      srstn <= not arst;
    end if;
  end process;

  clk <= not clk after CLK_PERIOD / 2;

  -- ---------------------------------------------------------------------------
  u_axis_mux : entity work.axis_mux
  port map (
    clk    => clk,
    srst   => srst,
    s_axis => s_axis,
    m_axis => m_axis,
    sel    => sel
  );


  gen_bfms : for i in s_axis'range generate

    u_bfm_axis_man : entity work.bfm_axis_man
    generic map(
      G_DATA_QUEUE => DATA_QUEUES(i),
      G_USER_QUEUE => USER_QUEUES(i),
      G_STALL_CONFIG => STALL_CFG
    )
    port map(
      clk    => clk,
      m_axis => s_axis(i)
    );

    u_bfm_axis_sub : entity work.bfm_axis_sub
    generic map(
      G_REF_DATA_QUEUE => REF_DATA_QUEUES(i),
      G_REF_USER_QUEUE => REF_USER_QUEUES(i),
      G_STALL_CONFIG   => STALL_CFG
    )
    port map(
      clk => clk,
      s_axis.tready  => bfm_m_tready(i),
      s_axis.tvalid  => bfm_m_tvalid(i),
      s_axis.tlast   => m_axis.tlast,
      s_axis.tdata   => m_axis.tdata,
      s_axis.tkeep   => m_axis.tkeep,
      s_axis.tuser   => m_axis.tuser,
      num_packets_checked => num_packets_checked(i)
    );

  end generate;

  ------------------------------------------------------------------------------
  prc_assign_handshake : process(all) begin

    bfm_m_tvalid <= (others => '0');
    m_axis.tready <= '0';

    if m_axis.tvalid then
      bfm_m_tvalid(to_integer(unsigned(m_axis.tuser(UBW - 1 downto 0)))) <= m_axis.tvalid;
      m_axis.tready <= bfm_m_tready(to_integer(unsigned(m_axis.tuser(UBW - 1 downto 0))));
    end if;

  end process;

  -- Use randomly changing values for select
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
