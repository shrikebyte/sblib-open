--##############################################################################
--# File : axis_resize_tb.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! AXIS resize testbench
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

entity axis_resize_tb is
  generic (
    RUNNER_CFG      : string;
    G_ENABLE_JITTER : boolean := true;
    G_S_DW          : positive := 8;
    G_M_DW          : positive := 8;
    G_S_UW          : positive := 8    
  );
end entity;

architecture tb of axis_resize_tb is

  -- TB Constants
  constant RESET_TIME : time := 50 ns;
  constant CLK_PERIOD : time := 5 ns;

  type resize_mode_t is (MODE_PASSTHRU, MODE_UPSIZE, MODE_DOWNSIZE);

  function calc_mode (s_dw : positive; m_dw : positive) return resize_mode_t is
  begin
    if s_dw = m_dw then
      return MODE_PASSTHRU;
    elsif s_dw > m_dw then
      return MODE_DOWNSIZE;
    else
      return MODE_UPSIZE;
    end if;
  end function;

  constant MODE : resize_mode_t := calc_mode(G_S_DW, G_M_DW);

  function calc_m_uw (s_dw : positive; m_dw : positive; s_uw : positive) return positive is
  begin
    if s_dw = m_dw or s_dw > m_dw then
      return s_uw;
    else
      return s_uw * (m_dw / s_dw);
    end if;
  end function;

  constant M_UW : positive := calc_m_uw(G_S_DW, G_M_DW, G_S_UW);

  constant BW   : positive := 8;
  constant S_KW : positive := G_S_DW / BW;
  constant M_KW : positive := G_M_DW / BW;

  -- TB Signals
  signal clk   : std_ulogic := '1';
  signal arst  : std_ulogic := '1';
  signal srst  : std_ulogic := '1';
  signal srstn : std_ulogic := '0';

  -- DUT Signals
  signal s_axis : axis_t (
                           tdata(G_S_DW - 1 downto 0),
                           tkeep(G_S_DW / 8 - 1 downto 0),
                           tuser(G_S_UW - 1 downto 0)
                         );

  signal m_axis : axis_t (
                           tdata(G_M_DW - 1 downto 0),
                           tkeep(G_M_DW / 8 - 1 downto 0),
                           tuser(M_UW - 1 downto 0)
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

      constant PACKET_LENGTH_BYTES : natural := rnd.Uniform(1, 5 * S_KW);

      -- Calculate the integer ceiling division of
      -- PACKET_LENGTH_BYTES / AXIS_KEEP_WIDTH to determine the number of beats
      -- in a packet.
      constant S_PACKET_LENGTH_BEATS : natural := (PACKET_LENGTH_BYTES + S_KW - 1) / S_KW;
      constant M_PACKET_LENGTH_BEATS : natural := (PACKET_LENGTH_BYTES + M_KW - 1) / S_KW;

      variable data, data_copy : integer_array_t := null_integer_array;
      variable s_user : integer_array_t := new_1d (
        length => S_PACKET_LENGTH_BEATS * (G_S_UW / BW),
        bit_width => BW,
        is_signed => false
      );
      variable m_user : integer_array_t := new_1d (
        length => M_PACKET_LENGTH_BEATS * (M_UW / BW),
        bit_width => BW,
        is_signed => false
      );

      variable j : integer := 0;

    begin

      -- Random test data packet
      random_integer_array (
        rnd           => rnd,
        integer_array => data,
        width         => PACKET_LENGTH_BYTES,
        bits_per_word => BW,
        is_signed     => false
      );
      data_copy := copy(data);
      push_ref(INPUT_DATA_QUEUE, data);
      push_ref(REF_DATA_QUEUE, data_copy);

      -- Random user data packet
      random_integer_array (
        rnd           => rnd,
        integer_array => s_user,
        width         => S_PACKET_LENGTH_BEATS,
        bits_per_word => BW,
        is_signed     => false
      );

      -- Set up expected user data based on the mode. Downsize mode is a bit
      -- different because input user data is replicated on multiple output
      -- beats.
      case MODE is
        when MODE_PASSTHRU | MODE_UPSIZE =>
          m_user := copy(s_user);

        when MODE_DOWNSIZE =>
          for i in 0 to width(m_user) - 1 loop
            set(m_user, i, get(s_user, j));
            if (i mod (S_KW / M_KW)) - 1 = 0 then
              j := j + 1;
            end if;
          end loop;
      end case;

      push_ref(INPUT_USER_QUEUE, s_user);
      push_ref(REF_USER_QUEUE, m_user);

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
      for test_idx in 0 to 99 loop
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
  u_axis_resize : entity work.axis_resize
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
    --USER_WIDTH         => s_axis.tuser'length,
    USER_WIDTH         => 0,
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
    strobe => s_axis.tkeep
    --user   => s_axis.tuser
  );

  axi_stream_slave_inst : entity work.axi_stream_slave
  generic map (
    DATA_WIDTH           => m_axis.tdata'length,
    REFERENCE_DATA_QUEUE => REF_DATA_QUEUE,
    --USER_WIDTH           => m_axis.tuser'length,
    USER_WIDTH           => 0,
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
    --user   => m_axis.tuser,
    --
    num_packets_checked => num_packets_checked
  );

end architecture;
