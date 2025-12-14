--##############################################################################
--# File : axis_pack_tb.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! AXIS pack testbench
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

entity axis_pack_tb is
  generic (
    RUNNER_CFG      : string;
    G_ENABLE_JITTER : boolean := true;
    G_DW  : integer := 32;
    G_KW  : integer := 4;
    G_SUPPORT_NULL_TLAST : boolean := true
  );
end entity;

architecture tb of axis_pack_tb is

  -- TB Constants
  constant RESET_TIME : time := 50 ns;
  constant CLK_PERIOD : time := 5 ns;

  constant UW  : integer := G_DW;
  constant DBW : integer := G_DW / G_KW;
  constant UBW : integer := UW / G_KW;

  -- TB Signals
  signal clk   : std_ulogic := '1';
  signal arst  : std_ulogic := '1';
  signal srst  : std_ulogic := '1';
  signal srstn : std_ulogic := '0';

  -- DUT Signals
  signal s_axis : axis_t (
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

  constant INPUT_DATA_QUEUE, REF_DATA_QUEUE, INPUT_USER_QUEUE, REF_USER_QUEUE : queue_t := new_queue;

  signal num_packets_checked : natural := 0;

begin

  -- ---------------------------------------------------------------------------
  test_runner_watchdog(runner, 100 us);

  prc_main : process is
    variable rnd : randomptype;

    variable num_tests : natural := 0;

    procedure send_random is

      constant PACKET_LENGTH_BYTES : natural := rnd.Uniform(1, 3 * G_KW);

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
      push_ref(INPUT_DATA_QUEUE, data);
      push_ref(REF_DATA_QUEUE, data_copy);

      -- Random user packet
      random_integer_array (
        rnd           => rnd,
        integer_array => user,
        width         => PACKET_LENGTH_BYTES,
        bits_per_word => UBW,
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
  u_axis_pack : entity work.axis_pack
  generic map (
    G_SUPPORT_NULL_TLAST => G_SUPPORT_NULL_TLAST
  )
  port map (
    clk    => clk,
    srst   => srst,
    s_axis => s_axis,
    m_axis => m_axis
  );

  u_axi_stream_master : entity work.axi_stream_master
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
    DATA_WIDTH           => m_axis.tdata'length,
    REFERENCE_DATA_QUEUE => REF_DATA_QUEUE,
    USER_WIDTH           => m_axis.tuser'length,
    REFERENCE_USER_QUEUE => REF_USER_QUEUE,
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
    user   => m_axis.tuser,
    --
    num_packets_checked => num_packets_checked
  );

end architecture;
