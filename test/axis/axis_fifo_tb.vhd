--##############################################################################
--# File : axis_fifo_tb.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! AXIS FIFO testbench
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

entity axis_fifo_tb is
  generic (
    RUNNER_CFG      : string;
    G_ENABLE_JITTER : boolean  := true;
    G_DEPTH         : positive := 64;
    G_PACKET_MODE   : boolean  := false;
    G_DROP_OVERSIZE : boolean  := false
  );
end entity;

architecture tb of axis_fifo_tb is

  -- TB Constants
  constant RESET_TIME : time    := 50 ns;
  constant CLK_PERIOD : time    := 5 ns;
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
    tdata(DW - 1 downto 0),
    tkeep(KW - 1 downto 0),
    tuser(UW - 1 downto 0)
  );

  signal m_axis : axis_t (
    tdata(DW - 1 downto 0),
    tkeep(KW - 1 downto 0),
    tuser(UW - 1 downto 0)
  );

  signal ctl_drop       : std_ulogic := '0';
  signal sts_dropped    : std_ulogic;
  signal sts_depth_spec : u_unsigned(clog2(G_DEPTH) downto 0);
  signal sts_depth_comm : u_unsigned(clog2(G_DEPTH) downto 0);

  -- Testbench BFMs
  constant STALL_CFG : stall_configuration_t := (
    stall_probability => 0.2 * to_real(G_ENABLE_JITTER),
    min_stall_cycles  => 1,
    max_stall_cycles  => 3
  );

  constant DATA_QUEUE     : queue_t := new_queue;
  constant REF_DATA_QUEUE : queue_t := new_queue;
  constant USER_QUEUE     : queue_t := new_queue;
  constant REF_USER_QUEUE : queue_t := new_queue;

  signal num_packets_checked : natural    := 0;
  signal num_packets_sent    : natural    := 0;
  signal bfm_sub_enable      : std_ulogic := '0';

begin

  -- ---------------------------------------------------------------------------
  test_runner_watchdog(runner, 100 us);

  prc_main : process is

    variable rnd                          : randomptype;
    variable expected_num_packets_checked : natural := 0;
    variable expected_num_packets_sent    : natural := 0;

    procedure send_packet (
      packet_length_beats : positive;
      packet_dropped      : boolean := false
    ) is

      constant PACKET_LENGTH_BYTES : natural := packet_length_beats * KW;

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

      -- Random user packet
      random_integer_array (
        rnd           => rnd,
        integer_array => user,
        width         => PACKET_LENGTH_BYTES,
        bits_per_word => UBW,
        is_signed     => false
      );

      if not packet_dropped then
        data_copy                    := copy(data);
        push_ref(REF_DATA_QUEUE, data_copy);
        user_copy                    := copy(user);
        push_ref(REF_USER_QUEUE, user_copy);
        expected_num_packets_checked := expected_num_packets_checked + 1;
      end if;

      push_ref(DATA_QUEUE, data);
      push_ref(USER_QUEUE, user);
      expected_num_packets_sent := expected_num_packets_sent + 1;

    end procedure;

    procedure wait_until_done is begin
      wait until num_packets_checked = expected_num_packets_checked and
                 num_packets_sent = expected_num_packets_sent and
        rising_edge(clk);
    end procedure;

    procedure wait_clks (
      clks : natural
    ) is begin
      if clks > 0 then
        for i in 0 to clks - 1 loop
          wait until rising_edge(clk);
        end loop;
      end if;
    end procedure;

    variable drop : boolean;
    variable len  : positive;

  begin

    test_runner_setup(runner, RUNNER_CFG);
    rnd.InitSeed(get_string_seed(RUNNER_CFG));

    arst <= '1';
    wait for RESET_TIME;
    arst <= '0';
    wait until rising_edge(clk);

    if run("test_random_data") then
      bfm_sub_enable <= '1';

      for test_idx in 0 to G_DEPTH loop
        send_packet(rnd.Uniform(1, 3));
      end loop;

    elsif run("test_fill") then
      bfm_sub_enable <= '0';

      -- Send data while fifo not full
      while sts_depth_spec < G_DEPTH loop
        send_packet(rnd.Uniform(1, 3));
        wait until rising_edge(clk);
      end loop;

      -- Queue up one additional packet to ensure it overflows
      send_packet(5);

      -- Drain the fifo
      bfm_sub_enable <= '1';
    elsif run("test_oversized") then
      bfm_sub_enable <= '1';

      send_packet(G_DEPTH * 3 / 4);
      send_packet(G_DEPTH + 100, G_DROP_OVERSIZE);
      send_packet(1);
      send_packet(G_DEPTH + 1, G_DROP_OVERSIZE);
      send_packet(G_DEPTH - 1);
      send_packet(G_DEPTH);
      send_packet(G_DEPTH + 2, G_DROP_OVERSIZE);
      send_packet(G_DEPTH * 1 / 4);
    elsif run("test_drop") then
      bfm_sub_enable <= '1';
      ctl_drop       <= '0';

      -- Sometimes hold the drop signal during random packets
      for test_idx in 0 to 20 loop
        drop     := to_bool(rnd.RandInt(0, 1));
        len      := rnd.Uniform(1, 10);
        send_packet(len, G_PACKET_MODE and drop);
        ctl_drop <= to_sl(drop);
        wait until (s_axis.tvalid and s_axis.tready and s_axis.tlast) = '1' and
          rising_edge(clk);
        ctl_drop <= '0';
      end loop;

      -- Non-dropped packet
      send_packet(1);
      wait_until_done;

      -- Pulse the drop signal on tlast
      wait_clks(1);
      send_packet(10, G_PACKET_MODE);
      wait until (s_axis.tvalid and s_axis.tready and s_axis.tlast);
      ctl_drop <= '1';
      wait_clks(1);
      ctl_drop <= '0';
      wait_until_done;

      -- Pulse the drop signal in the middle of a packet
      wait_clks(1);
      send_packet(10, G_PACKET_MODE);
      wait_clks(5);
      ctl_drop <= '1';
      wait_clks(1);
      ctl_drop <= '0';
      wait_until_done;

      -- Non-dropped packet
      send_packet(5);
      wait_until_done;

      -- Pulse the drop signal before the next packet
      wait_clks(1);
      ctl_drop <= '1';
      wait_clks(3);
      ctl_drop <= '0';
      wait_clks(3);
      send_packet(10, G_PACKET_MODE);
      wait_until_done;

      -- Non-dropped packet
      send_packet(2);
      wait_until_done;
    elsif run("test_fill_lasts") then
      bfm_sub_enable <= '0';

      -- Send data while fifo not full
      while sts_depth_spec < G_DEPTH loop
        send_packet(1);
        wait until rising_edge(clk);
      end loop;

      -- Queue up a few additional packets
      send_packet(1);
      send_packet(1);
      send_packet(1);

      -- Drain the fifo
      bfm_sub_enable <= '1';
      wait_clks(10);
      bfm_sub_enable <= '0';
      wait_clks(10);
      bfm_sub_enable <= '1';
      wait_clks(10);
      bfm_sub_enable <= '0';
      wait_clks(10);
      bfm_sub_enable <= '1';

    end if;

    wait_until_done;

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
  u_axis_fifo : entity work.axis_fifo
  generic map (
    G_DEPTH         => G_DEPTH,
    G_PACKET_MODE   => G_PACKET_MODE,
    G_DROP_OVERSIZE => G_DROP_OVERSIZE,
    G_USE_TLAST     => true,
    G_USE_TKEEP     => true,
    G_USE_TUSER     => true
  )
  port map (
    clk    => clk,
    srst   => srst,
    s_axis => s_axis,
    m_axis => m_axis,
    --
    ctl_drop       => ctl_drop,
    sts_dropped    => sts_dropped,
    sts_depth_spec => sts_depth_spec,
    sts_depth_comm => sts_depth_comm
  );

  u_bfm_axis_man : entity work.bfm_axis_man
  generic map (
    G_DATA_QUEUE   => DATA_QUEUE,
    G_USER_QUEUE   => USER_QUEUE,
    G_STALL_CONFIG => STALL_CFG
  )
  port map (
    clk              => clk,
    m_axis           => s_axis,
    num_packets_sent => num_packets_sent
  );

  u_bfm_axis_sub : entity work.bfm_axis_sub
  generic map (
    G_REF_DATA_QUEUE => REF_DATA_QUEUE,
    G_REF_USER_QUEUE => REF_USER_QUEUE,
    G_STALL_CONFIG   => STALL_CFG
  )
  port map (
    clk                 => clk,
    s_axis              => m_axis,
    enable              => bfm_sub_enable,
    num_packets_checked => num_packets_checked
  );

  -- ---------------------------------------------------------------------------
  gen_check_no_bubbles : if G_PACKET_MODE and G_DROP_OVERSIZE generate
    signal end_event, en : std_ulogic := '0';
  begin
    -- These inputs must be signals (not constants), so assign them here
    -- instead of the port map directly.
    end_event <= m_axis.tvalid and m_axis.tready and m_axis.tlast;
    en        <= srstn;

    check_stable(
      clock => clk,
      en    => en,
    -- Start check when valid arrives
      start_event => m_axis.tvalid,
    -- End check when last arrives
      end_event => end_event,
    -- Assert that valid is always asserted until last arrives
      expr => m_axis.tvalid,
      msg  => "There was a bubble in m_axis.tvalid!"
    );
  end generate;

end architecture;
