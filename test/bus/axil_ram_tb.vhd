--##############################################################################
--# File : axil_ram_tb.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! AXI Lite RAM testbench
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

entity axil_ram_tb is
  generic (
    RUNNER_CFG        : string;
    G_RD_LATENCY      : positive := 1;
    G_AXIS_STALL_PROB : integer  := 10
  );
end entity;

architecture tb of axil_ram_tb is

  -- Testbench constants
  constant CLK_PERIOD : time := 10 ns;
  constant CLK_TO_Q   : time := 1 ns;

  -- DUT ports
  signal clk      : std_logic := '1';
  signal srst     : std_logic := '1';
  signal axil_req : axil_req_t;
  signal axil_rsp : axil_rsp_t;

  -- Testbench BFMs. TODO: Swap this out for a full thruput master that can
  -- also check weird edge cases.
  constant AXIM : bus_master_t := new_bus (
      data_length    => AXIL_DATA_WIDTH,
      address_length => AXIL_ADDR_WIDTH
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

    variable addr  : std_logic_vector(31 downto 0)                      := (others => '0');
    variable data  : std_logic_vector(AXIL_DATA_WIDTH - 1 downto 0)     := (others => '0');
    variable wstrb : std_logic_vector(AXIL_DATA_WIDTH / 8 - 1 downto 0) := (others => '1');

  begin

    test_runner_setup(runner, RUNNER_CFG);

    while test_suite loop

      prd_rst(16);

      if run("test_0") then
        info("Running test_0");

        prd_wait_clk;

        addr  := x"00000008";
        data  := x"11223344";
        wstrb := x"F";
        write_axi_lite(net, AXIM, addr, data, AXI_RSP_OKAY, wstrb);
        check_axi_lite(net, AXIM, addr, AXI_RSP_OKAY, data, "Check 0 failed.");

        addr  := x"00000008";
        data  := x"22334455";
        wstrb := x"1";
        write_axi_lite(net, AXIM, addr, data, AXI_RSP_OKAY, wstrb);

        addr  := x"00000010";
        data  := x"33445566";
        wstrb := x"5";
        write_axi_lite(net, AXIM, addr, data, AXI_RSP_OKAY, wstrb);

        addr  := x"00000014";
        data  := x"44556677";
        wstrb := x"F";
        write_axi_lite(net, AXIM, addr, data, AXI_RSP_OKAY, wstrb);

        addr := x"00000008";
        data := x"11223355";
        check_axi_lite(net, AXIM, addr, AXI_RSP_OKAY, data, "Check 1 failed.");

        addr := x"00000010";
        data := x"00440066";
        check_axi_lite(net, AXIM, addr, AXI_RSP_OKAY, data, "Check 2 failed.");

        addr := x"00000014";
        data := x"44556677";
        check_axi_lite(net, AXIM, addr, AXI_RSP_OKAY, data, "Check 3 failed.");

        for i in 0 to 9 loop
          addr  := std_logic_vector(to_unsigned(i + 25, AXIL_ADDR_WIDTH - 2)) & b"00";
          data  := addr;
          wstrb := x"F";
          write_axi_lite(net, AXIM, addr, data, AXI_RSP_OKAY, wstrb);
        end loop;

        for i in 0 to 9 loop
          addr := std_logic_vector(to_unsigned(i + 25, AXIL_ADDR_WIDTH - 2)) & b"00";
          data := addr;
          check_axi_lite(net, AXIM, addr, AXI_RSP_OKAY, data, "Check during read loop failed.");
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
  u_axil_ram : entity work.axil_ram
  generic map (
    G_ADDR_WIDTH => 10,
    G_RD_LATENCY => G_RD_LATENCY
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
