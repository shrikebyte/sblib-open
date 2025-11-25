--##############################################################################
--# File : axil_init_mgr_tb.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! AXI Lite Master testbench
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;

library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.vc_context;
use vunit_lib.axi_lite_master_pkg.all;
use vunit_lib.wishbone_pkg.all;

entity axil_init_mgr_tb is
  generic (
    RUNNER_CFG : string
  );
end entity;

architecture tb of axil_init_mgr_tb is

  -- Testbench constants
  constant CLK_PERIOD : time := 10 ns;
  constant CLK_TO_Q   : time := 1 ns;

  -- DUT ports
  signal clk      : std_logic := '1';
  signal srst     : std_logic := '1';
  signal axil_req : axil_req_t;
  signal axil_rsp : axil_rsp_t;

  signal sts_valid     : std_logic;
  signal sts_bus_err   : std_logic;
  signal sts_chk_err   : std_logic;
  signal sts_chk_rdata : std_logic_vector(31 downto 0);
  signal sts_xact_idx  : unsigned(15 downto 0);

  constant NUM_XACTIONS : integer := 10;

  constant XACTIONS : bus_xact_arr_t(0 to NUM_XACTIONS - 1) := (
    0       => (
      cmd   => BUS_WRITE,
      wstrb => x"F",
      addr  => x"0000_0000",
      data  => x"1122_3344",
      mask  => x"FFFF_FFFF"
    ),
    1       => (
      cmd   => BUS_WRITE,
      wstrb => x"F",
      addr  => x"0000_0004",
      data  => x"2233_4455",
      mask  => x"FFFF_FFFF"
    ),
    2       => (
      cmd   => BUS_WRITE,
      wstrb => x"F",
      addr  => x"0000_0008",
      data  => x"3344_5566",
      mask  => x"FFFF_FFFF"
    ),
    3       => (
      cmd   => BUS_WRITE,
      wstrb => x"3",
      addr  => x"0000_000C",
      data  => x"4455_6677",
      mask  => x"FFFF_FFFF"
    ),
    4       => (
      cmd   => BUS_CHECK,
      wstrb => x"F",
      addr  => x"0000_0000",
      data  => x"1122_3344",
      mask  => x"FFFF_FFFF"
    ),
    5       => (
      cmd   => BUS_CHECK,
      wstrb => x"F",
      addr  => x"0000_0004",
      data  => x"2233_4455",
      mask  => x"FFFF_FFFF"
    ),
    6       => (
      cmd   => BUS_CHECK,
      wstrb => x"F",
      addr  => x"0000_0008",
      data  => x"3344_5566",
      mask  => x"FFFF_FFFF"
    ),
    7       => (
      cmd   => BUS_CHECK,
      wstrb => x"F",
      addr  => x"0000_000C",
      data  => x"4455_6677",
      mask  => x"0000_FFFF"
    ),
    8       => (
      cmd   => BUS_CHECK,
      wstrb => x"F",
      addr  => x"0000_0004",
      data  => x"2X3X_4X5X",
      mask  => x"F0F0_F0F0"
    ),
    9       => (
      cmd   => BUS_CHECK,
      wstrb => x"F",
      addr  => x"0000_0004",
      data  => x"2X3X_4X5X",
      mask  => x"0F0F_0F0F"
    )
  );

begin

  prc_main : process is

    -- Helper Procedures
    procedure prd_wait_clk (
      cnt : in positive := 1
    ) is
    begin
      for i in 0 to cnt - 1 loop
        wait until rising_edge(clk);
        wait for CLK_TO_Q;
      end loop;
    end procedure;

    procedure prd_rst (
      cnt : in positive := 1
    ) is
    begin
      prd_wait_clk(1);
      srst <= '1';
      prd_wait_clk(cnt);
      srst <= '0';
    end procedure;

  begin

    test_runner_setup(runner, RUNNER_CFG);

    while test_suite loop

      prd_rst(16);

      if run("test_0") then
        info("Running test_0");

        prd_wait_clk;

        for i in 0 to NUM_XACTIONS - 1 loop
          wait until rising_edge(sts_valid);
          wait until falling_edge(clk);

          check(sts_bus_err = '0');
          check(sts_xact_idx = i);

          if i = 9 then
            check(sts_chk_err = '1');
            check(sts_chk_rdata = x"2233_4455");
          else
            check(sts_chk_err = '0');
          end if;

        end loop;

      -- elsif run("test_1") then
      --   info("Running test_1");

      end if;

      info("Test done");
      prd_wait_clk(16);

    end loop;

    test_runner_cleanup(runner);

  end process;

  -- Watchdog
  test_runner_watchdog(runner, 100 us);

  -- ---------------------------------------------------------------------------
  clk <= not clk after CLK_PERIOD / 2;

  -- ---------------------------------------------------------------------------
  u_axil_master : entity work.axil_init_mgr
  generic map (
    G_RESET_DELAY_CLKS => 16,
    G_XACTIONS         => XACTIONS
  )
  port map (
    clk  => clk,
    srst => srst,
    --
    m_axil_req => axil_req,
    m_axil_rsp => axil_rsp,
    --
    m_sts_valid     => sts_valid,
    m_sts_bus_err   => sts_bus_err,
    m_sts_chk_err   => sts_chk_err,
    m_sts_chk_rdata => sts_chk_rdata,
    m_sts_xact_idx  => sts_xact_idx
  );

  -- ---------------------------------------------------------------------------
  u_axil_ram : entity work.axil_ram
  generic map (
    G_ADDR_WIDTH => 4,
    G_RD_LATENCY => 2
  )
  port map (
    clk        => clk,
    srst       => srst,
    s_axil_req => axil_req,
    s_axil_rsp => axil_rsp
  );

end architecture;
