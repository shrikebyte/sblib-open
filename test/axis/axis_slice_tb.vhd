--##############################################################################
--# File : axis_slice_tb.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! AXIS slice testbench
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

entity axis_slice_tb is
  generic (
    RUNNER_CFG      : string;
    G_ENABLE_JITTER : boolean := true
  );
end entity;

architecture tb of axis_slice_tb is

  -- TB Constants
  constant RESET_TIME  : time     := 50 ns;
  constant CLK_PERIOD  : time     := 5 ns;
  constant NUM_OUTPUTS : integer  := 2;
  constant KW          : integer  := 4;
  constant DW          : integer  := 32;
  constant UW          : integer  := 32;
  constant DBW         : integer  := DW / KW;
  constant UBW         : integer  := UW / KW;
  constant MAX_M0_BYTES : integer := 2048;

  -- TB Signals
  signal clk   : std_ulogic := '1';
  signal arst  : std_ulogic := '1';
  signal srst  : std_ulogic := '1';
  signal srstn : std_ulogic := '0';

  -- DUT Signal
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

  signal  num_bytes    :  natural range 0 to MAX_M0_BYTES;
  signal  sts_err_runt :  std_ulogic;

  -- Testbench BFMs
  constant STALL_CFG : stall_configuration_t := (
    stall_probability => 0.2 * to_real(G_ENABLE_JITTER),
    min_stall_cycles  => 1,
    max_stall_cycles  => 3
  );

  constant NUM_BYTES_QUEUE : queue_t := new_queue;
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

    variable rnd : randomptype;
    variable num_tests : nat_arr_t(m_axis'range) := (others => 0);

    procedure send_random is

      constant PACKET_LENGTH_BYTES : natural := rnd.Uniform(1, 4 * KW);
      constant SPLIT_LENGTH_BYTES : natural := rnd.Uniform(0, 5 * KW);

      function get_m0_len return natural is
      begin
        if (PACKET_LENGTH_BYTES > SPLIT_LENGTH_BYTES) then
          -- Normal case. Packet gets split.
          return SPLIT_LENGTH_BYTES;
        else
          -- Runt packet.
          return PACKET_LENGTH_BYTES;
        end if;
      end function;

      function get_m1_len return natural is
      begin
        if (PACKET_LENGTH_BYTES > SPLIT_LENGTH_BYTES) then
          -- Normal case. Remaining bytes get sent down m1.
          return PACKET_LENGTH_BYTES - SPLIT_LENGTH_BYTES;
        else
          -- Runt packet. Nothing gets sent down m1.
          return 0;
        end if;
      end function;

      constant M0_LEN : integer := get_m0_len;
      constant M1_LEN : integer := get_m1_len;

      variable s_data : integer_array_t :=
        new_1d (
          length => PACKET_LENGTH_BYTES,
          bit_width => DBW,
          is_signed => false
      );

      variable m0_data : integer_array_t :=
        new_1d (
          length => M0_LEN,
          bit_width => DBW,
          is_signed => false
      );

      variable m1_data : integer_array_t :=
        new_1d (
          length => M1_LEN,
          bit_width => DBW,
          is_signed => false
      );

      variable s_user : integer_array_t :=
        new_1d (
          length => PACKET_LENGTH_BYTES,
          bit_width => UBW,
          is_signed => false
      );

      variable m0_user : integer_array_t :=
        new_1d (
          length => M0_LEN,
          bit_width => UBW,
          is_signed => false
      );

      variable m1_user : integer_array_t :=
        new_1d (
          length => M1_LEN,
          bit_width => UBW,
          is_signed => false
      );

      variable j : integer := 0;

    begin

      assert SPLIT_LENGTH_BYTES >= 0 and SPLIT_LENGTH_BYTES < 2**UBW
        report
          "ERROR: SPLIT_LENGTH_BYTES > 0 and SPLIT_LENGTH_BYTES < " &
          to_string(2**UBW)
        severity error;

      -- Random test data packet
      random_integer_array (
        rnd           => rnd,
        integer_array => s_data,
        width         => PACKET_LENGTH_BYTES,
        bits_per_word => DBW,
        is_signed     => false
      );

      -- Use user packet for the split length input
      for i in 0 to PACKET_LENGTH_BYTES - 1 loop
        set(s_user, i, SPLIT_LENGTH_BYTES);
      end loop;

      -- Generated expected packet for output0
      j := 0;
      if M0_LEN /= 0 then
        for i in 0 to M0_LEN - 1 loop
          set(m0_data, i, get(s_data, j));
          set(m0_user, i, get(s_user, j));
          j := j + 1;
        end loop;
      end if;

      -- Generated expected packet for output1
      if M1_LEN /= 0 then
        for i in 0 to M1_LEN - 1 loop
          set(m1_data, i, get(s_data, j));
          set(m1_user, i, get(s_user, j));
          j := j + 1;
        end loop;
      end if;

      push(NUM_BYTES_QUEUE, SPLIT_LENGTH_BYTES);
      push_ref(DATA_QUEUE, s_data);
      push_ref(USER_QUEUE, s_user);
      if M0_LEN /= 0 then
        push_ref(REF_DATA_QUEUES(0), m0_data);
        push_ref(REF_USER_QUEUES(0), m0_user);
        num_tests(0) := num_tests(0) + 1;
      end if;
      if M1_LEN /= 0 then
        push_ref(REF_DATA_QUEUES(1), m1_data);
        push_ref(REF_USER_QUEUES(1), m1_user);
        num_tests(1) := num_tests(1) + 1;
      end if;

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
  u_axis_slice : entity work.axis_slice
  generic map (
    G_MAX_M0_BYTES => MAX_M0_BYTES,
    G_PACK_OUTPUT => true
  )
  port map (
    clk          => clk,
    srst         => srst,
    s_axis       => s_axis,
    m0_axis      => m_axis(0),
    m1_axis      => m_axis(1),
    num_bytes    => num_bytes,
    sts_err_runt => sts_err_runt
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

  gen_subs : for i in m_axis'range generate
    u_bfm_axis_sub : entity work.bfm_axis_sub
    generic map(
      G_REF_DATA_QUEUE => REF_DATA_QUEUES(i),
      G_REF_USER_QUEUE => REF_USER_QUEUES(i),
      G_LOGGER_NAME_SUFFIX => to_string(i),
      G_STALL_CONFIG   => STALL_CFG
    )
    port map(
      clk    => clk,
      s_axis => m_axis(i),
      num_packets_checked => num_packets_checked(i)
    );
  end generate;

  -- ---------------------------------------------------------------------------
  prc_num_bytes : process is
  begin
    while is_empty(NUM_BYTES_QUEUE) loop
      wait until rising_edge(clk);
    end loop;
    num_bytes <= pop(NUM_BYTES_QUEUE);
    wait until (s_axis.tvalid and s_axis.tready and s_axis.tlast) = '1'
      and rising_edge(clk);
  end process;

end architecture;
