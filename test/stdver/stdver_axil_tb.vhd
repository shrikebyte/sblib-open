--##############################################################################
--# File : stdver_axil_tb.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! Standard version module testbench
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.vc_context;
use vunit_lib.axi_lite_master_pkg.all;
use work.util_pkg.all;
use work.stdver_regs_pkg.all;

entity stdver_axil_tb is
  generic (
    RUNNER_CFG : string
  );
end entity;

architecture tb of stdver_axil_tb is

  -- Clock period
  constant CLK_PERIOD : time := 10 ns;
  constant CLK_TO_Q   : time := 1 ns;
  -- Generics
  constant G_DEVICE_ID   : std_logic_vector(31 downto 0) := x"0000_0001";
  constant G_VER_MAJOR   : natural                       := 1;
  constant G_VER_MINOR   : natural                       := 2;
  constant G_VER_PATCH   : natural                       := 3;
  constant G_LOCAL_BUILD : boolean                       := true;
  constant G_DEV_BUILD   : boolean                       := true;
  constant G_GIT_DIRTY   : boolean                       := true;
  constant G_GIT_HASH    : std_logic_vector(31 downto 0) := x"A000_000A";
  constant G_BUILD_DATE  : std_logic_vector(31 downto 0) := x"B000_000B";
  constant G_BUILD_TIME  : std_logic_vector(23 downto 0) := x"C0_000C";

  -- Ports
  signal clk  : std_logic := '1';
  signal srst : std_logic := '1';

  signal axil_req : axil_req_t;
  signal axil_rsp : axil_rsp_t;

  constant AXIM : bus_master_t := new_bus(data_length => AXIL_DATA_WIDTH, address_length => AXIL_ADDR_WIDTH);

  function fn_addr (
    idx : natural
  ) return std_logic_vector is begin
    return std_logic_vector(to_unsigned(idx * 4, 32));
  end function;

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

    -- This code is common to the entire test suite
    -- and is executed *once* prior to all test cases.
    test_runner_setup(runner, RUNNER_CFG);

    while test_suite loop

      -- This code executed before *every* test case.
      prd_rst(16);

      if run("test_alive") then
        info("Hello world test_alive");
      elsif run("test_0") then
        info("Running test_0");

        info("Check scratchpad");
        check_axi_lite(net, AXIM, fn_addr(stdver_scratchpad), AXI_RSP_OKAY, x"12345678");
        write_axi_lite(net, AXIM, fn_addr(stdver_scratchpad), X"1122_3344", AXI_RSP_OKAY, x"F");
        check_axi_lite(net, AXIM, fn_addr(stdver_scratchpad), AXI_RSP_OKAY, X"1122_3344");

        info("Check ID");
        check_axi_lite(net, AXIM, fn_addr(stdver_id), AXI_RSP_OKAY, G_DEVICE_ID);
        write_axi_lite(net, AXIM, fn_addr(stdver_id), X"1122_3344", AXI_RSP_SLVERR, x"F");
        check_axi_lite(net, AXIM, fn_addr(stdver_id), AXI_RSP_OKAY, G_DEVICE_ID);

        info("Check version");
        check_axi_lite(net, AXIM, fn_addr(stdver_version), AXI_RSP_OKAY, X"E001_0203");
        write_axi_lite(net, AXIM, fn_addr(stdver_version), X"1122_3344", AXI_RSP_SLVERR, x"F");
        check_axi_lite(net, AXIM, fn_addr(stdver_version), AXI_RSP_OKAY, X"E001_0203");

        info("Check build date");
        check_axi_lite(net, AXIM, fn_addr(stdver_date), AXI_RSP_OKAY, X"B000_000B");
        write_axi_lite(net, AXIM, fn_addr(stdver_date), X"1122_3344", AXI_RSP_SLVERR, x"F");
        check_axi_lite(net, AXIM, fn_addr(stdver_date), AXI_RSP_OKAY, X"B000_000B");

        info("Check build time");
        check_axi_lite(net, AXIM, fn_addr(stdver_time), AXI_RSP_OKAY, X"00C0_000C");
        write_axi_lite(net, AXIM, fn_addr(stdver_time), X"1122_3344", AXI_RSP_SLVERR, x"F");
        check_axi_lite(net, AXIM, fn_addr(stdver_time), AXI_RSP_OKAY, X"00C0_000C");

        info("Check git hash");
        check_axi_lite(net, AXIM, fn_addr(stdver_githash), AXI_RSP_OKAY, X"A000_000A");
        write_axi_lite(net, AXIM, fn_addr(stdver_githash), X"1122_3344", AXI_RSP_SLVERR, x"F");
        check_axi_lite(net, AXIM, fn_addr(stdver_githash), AXI_RSP_OKAY, X"A000_000A");

      end if;

      -- Put test case cleanup code here. This code executed after *every* test case.
      info("Test done");
      prd_wait_clk(16);

    end loop;

    -- Put test suite cleanup code here. This code is common to the entire test suite
    -- and is executed *once* after all test cases have been run.
    test_runner_cleanup(runner);

  end process;

  -- Watchdog
  test_runner_watchdog(runner, 100 us);

  -- ---------------------------------------------------------------------------
  clk <= not clk after CLK_PERIOD / 2;

  -- ---------------------------------------------------------------------------
  u_stdver_axil : entity work.stdver_axil
  generic map (
    G_DEVICE_ID   => G_DEVICE_ID,
    G_VER_MAJOR   => G_VER_MAJOR,
    G_VER_MINOR   => G_VER_MINOR,
    G_VER_PATCH   => G_VER_PATCH,
    G_LOCAL_BUILD => G_LOCAL_BUILD,
    G_DEV_BUILD   => G_DEV_BUILD,
    G_BUILD_DATE  => G_BUILD_DATE,
    G_BUILD_TIME  => G_BUILD_TIME,
    G_GIT_HASH    => G_GIT_HASH,
    G_GIT_DIRTY   => G_GIT_DIRTY
  )
  port map (
    clk        => clk,
    srst       => srst,
    s_axil_req => axil_req,
    s_axil_rsp => axil_rsp
  );

  -- ---------------------------------------------------------------------------
  u_axil_bfm : entity work.bfm_axil_man
  generic map (
    G_BUS_HANDLE => AXIM
  )
  port map (
    clk        => clk,
    m_axil_req => axil_req,
    m_axil_rsp => axil_rsp
  );

end architecture;
