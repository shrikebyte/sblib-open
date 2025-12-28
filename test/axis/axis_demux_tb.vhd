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

use work.util_pkg.all;
use work.axis_pkg.all;
use work.bfm_pkg.all;

entity axis_demux_tb is
  generic (
    RUNNER_CFG      : string;
    G_ENABLE_JITTER : boolean := true
  );
end entity;

architecture tb of axis_demux_tb is

  -- TB Constants
  constant RESET_TIME  : time := 50 ns;
  constant CLK_PERIOD  : time := 5 ns;
  constant NUM_OUTPUTS : integer := 4;
  constant KW         : integer := 2;
  constant DW         : integer := 16;
  constant UW         : integer := 8;
  constant DBW        : integer := DW / KW;
  constant UBW        : integer := UW / KW;

  -- TB Signals
  signal clk   : std_ulogic := '1';
  signal arst  : std_ulogic := '1';
  signal srst  : std_ulogic := '1';
  signal srstn : std_ulogic := '0';

  -- DUT Signals
  signal s_axis : axis_t (
    tdata(DW-1 downto 0),
    tkeep(KW-1 downto 0),
    tuser(UW-1 downto 0)
  );

  signal m_axis :  axis_arr_t(0 to NUM_OUTPUTS - 1)(
    tdata(DW-1 downto 0),
    tkeep(KW-1 downto 0),
    tuser(UW-1 downto 0)
  );

  signal sel : integer range m_axis'range := m_axis'low;

  -- Testbench BFMs
  constant STALL_CFG : stall_configuration_t := (
    stall_probability => 0.2 * to_real(G_ENABLE_JITTER),
    min_stall_cycles  => 1,
    max_stall_cycles  => 3
  );

  constant SEL_QUEUE : queue_t := new_queue;
  constant DATA_QUEUE : queue_t := new_queue;
  constant USER_QUEUE : queue_t := new_queue;
  constant REF_DATA_QUEUES  : queue_vec_t(m_axis'range) :=
    get_new_queues(m_axis'length);
  constant REF_USER_QUEUES : queue_vec_t(m_axis'range) :=
    get_new_queues(m_axis'length);

  signal num_packets_checked : nat_arr_t(m_axis'range)  := (others => 0);

begin

  -- ---------------------------------------------------------------------------
  test_runner_watchdog(runner, 100 us);
  prc_main : process is

    variable rnd : randomptype;
    variable num_tests : nat_arr_t(m_axis'range)  := (others => 0);

    procedure send_random is

      constant PACKET_LENGTH_BYTES : natural := rnd.Uniform(1, 5 * KW);
      constant OUTPUT_IDX : natural := rnd.Uniform(m_axis'low, m_axis'high);

      variable data      : integer_array_t := null_integer_array;
      variable data_copy : integer_array_t := null_integer_array;
      variable user      : integer_array_t := null_integer_array;
      variable user_copy : integer_array_t := null_integer_array;

    begin


      -- Random data packet
      random_integer_array (
        rnd           => rnd,
        integer_array => data,
        width         => PACKET_LENGTH_BYTES,
        bits_per_word => DBW,
        is_signed     => false
      );
      data_copy := copy(data);
      push_ref(DATA_QUEUE, data);
      push_ref(REF_DATA_QUEUES(OUTPUT_IDX), data_copy);

      -- Random user packet
      random_integer_array (
        rnd           => rnd,
        integer_array => user,
        width         => PACKET_LENGTH_BYTES,
        bits_per_word => UBW,
        is_signed     => false
      );
      user_copy := copy(user);
      push_ref(USER_QUEUE, user);
      push_ref(REF_USER_QUEUES(OUTPUT_IDX), user_copy);

      push(SEL_QUEUE, OUTPUT_IDX);

      num_tests(OUTPUT_IDX) := num_tests(OUTPUT_IDX) + 1;

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
  u_axis_demux : entity work.axis_demux
  port map (
    clk    => clk,
    srst   => srst,
    s_axis => s_axis,
    m_axis => m_axis,
    sel    => sel
  );

  u_bfm_axis_man : entity work.bfm_axis_man
  generic map(
    G_DATA_QUEUE   => DATA_QUEUE,
    G_USER_QUEUE   => USER_QUEUE,
    G_STALL_CONFIG => STALL_CFG
  )
  port map(
    clk    => clk,
    m_axis => s_axis
  );

  gen_sub_bfms : for i in m_axis'range generate
    u_bfm_axis_sub : entity work.bfm_axis_sub
    generic map(
      G_REF_DATA_QUEUE => REF_DATA_QUEUES(i),
      G_REF_USER_QUEUE => REF_USER_QUEUES(i),
      G_STALL_CONFIG   => STALL_CFG
    )
    port map (
      clk    => clk,
      s_axis => m_axis(i),
      num_packets_checked => num_packets_checked(i)
    );
  end generate;


  -- ---------------------------------------------------------------------------
  prc_select : process is begin
    while is_empty(SEL_QUEUE) loop
      wait until rising_edge(clk);
    end loop;
    sel <= pop(SEL_QUEUE);
    wait until (s_axis.tvalid and s_axis.tready and s_axis.tlast) = '1'
      and rising_edge(clk);
  end process;


end architecture;
