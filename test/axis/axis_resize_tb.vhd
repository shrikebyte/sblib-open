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

use work.util_pkg.all;
use work.axis_pkg.all;
use work.bfm_pkg.all;

entity axis_resize_tb is
  generic (
    RUNNER_CFG      : string;
    G_ENABLE_JITTER : boolean  := true;
    G_PACKED_STREAM : boolean  := true;
    G_S_KW          : positive := 8;
    G_S_DW          : positive := 64;
    G_S_UW          : positive := 32;
    G_M_KW          : positive := 8;
    G_M_DW          : positive := 8;
    G_M_UW          : positive := 32
  );
end entity;

architecture tb of axis_resize_tb is

  -- TB Constants
  constant RESET_TIME   : time := 50 ns;
  constant CLK_PERIOD   : time := 5 ns;
  constant S_KW         : integer := G_S_KW;
  constant S_DW         : integer := G_S_DW;
  constant S_UW         : integer := G_S_UW;
  constant S_DBW        : integer := S_DW / S_KW;
  constant S_UBW        : integer := S_UW / S_KW;
  constant M_KW         : integer := G_M_KW;
  constant M_DW         : integer := G_M_DW;
  constant M_UW         : integer := G_M_UW;
  constant M_DBW        : integer := M_DW / M_KW;
  constant M_UBW        : integer := M_UW / M_KW;


  -- TB Signals
  signal clk   : std_ulogic := '1';
  signal arst  : std_ulogic := '1';
  signal srst  : std_ulogic := '1';
  signal srstn : std_ulogic := '0';

  -- DUT Signals
  signal s_axis : axis_t (
    tdata(S_DW - 1 downto 0),
    tkeep(S_KW - 1 downto 0),
    tuser(S_UW - 1 downto 0)
  );

  signal m_axis : axis_t (
    tdata(S_DW - 1 downto 0),
    tkeep(S_KW - 1 downto 0),
    tuser(S_UW - 1 downto 0)
  );

  -- ---------------------------------------------------------------------------
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

  signal num_packets_checked : natural := 0;

begin

  -- ---------------------------------------------------------------------------
  test_runner_watchdog(runner, 100 us);

  prc_main : process is

    variable rnd : randomptype;
    variable num_tests : natural := 0;

    procedure send_random is

      constant PACKET_LENGTH_BYTES : natural := rnd.Uniform(1, 3 * S_KW);

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
        bits_per_word => S_DBW,
        is_signed     => false
      );
      data_copy := copy(data);
      push_ref(DATA_QUEUE, data);
      push_ref(REF_DATA_QUEUE, data_copy);

      -- Random user packet
      random_integer_array (
        rnd           => rnd,
        integer_array => user,
        width         => PACKET_LENGTH_BYTES,
        bits_per_word => S_UBW,
        is_signed     => false
      );
      user_copy := copy(user);
      push_ref(USER_QUEUE, user);
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
  prc_srst : process (clk) is begin
    if rising_edge(clk) then
      srst  <= arst;
      srstn <= not arst;
    end if;
  end process;

  clk <= not clk after CLK_PERIOD / 2;

  -- ---------------------------------------------------------------------------
  -- DUT
  u_axis_resize : entity work.axis_resize
  port map (
    clk    => clk,
    srst   => srst,
    s_axis => s_axis,
    m_axis => m_axis
  );

  u_bfm_axis_man : entity work.bfm_axis_man
  generic map(
    G_DATA_QUEUE   => DATA_QUEUE,
    G_USER_QUEUE   => USER_QUEUE,
    G_STALL_CONFIG => STALL_CFG,
    G_PACKED_STREAM => G_PACKED_STREAM
  )
  port map(
    clk    => clk,
    m_axis => s_axis
  );

  u_bfm_axis_sub : entity work.bfm_axis_sub
  generic map(
    G_REF_DATA_QUEUE => REF_DATA_QUEUE,
    G_REF_USER_QUEUE => REF_USER_QUEUE,
    G_STALL_CONFIG   => STALL_CFG
  )
  port map(
    clk    => clk,
    s_axis => m_axis,
    num_packets_checked => num_packets_checked
  );

end architecture;
