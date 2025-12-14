--##############################################################################
--# File : axil_to_wb_tb.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! AXI Lite to Wishbone bridge testbench
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

entity axil_to_wb_tb is
  generic (
    RUNNER_CFG : string
  );
end entity;

architecture tb of axil_to_wb_tb is

  -- Testbench constants
  constant CLK_PERIOD : time    := 10 ns;
  constant CLK_TO_Q   : time    := 1 ns;
  constant MEM_DEPTH  : integer := 1024;

  -- DUT ports
  signal clk      : std_logic := '1';
  signal srst     : std_logic := '1';
  signal axil_req : axil_req_t;
  signal axil_rsp : axil_rsp_t;
  signal wb_req   : wb_req_t;
  signal wb_rsp   : wb_rsp_t;

  -- Testbench BFMs
  constant AXIM : bus_master_t := new_bus (
      data_length    => AXIL_DATA_WIDTH,
      address_length => AXIL_ADDR_WIDTH
    );

  -- Testbench signals
  signal ram           : slv_arr_t(0 to MEM_DEPTH - 1)(31 downto 0) := (others => (others => '0'));
  signal wb_tb_latency : positive range 1 to 8                      := 1;
  signal wb_tb_error   : std_logic                                  := '0';
  signal wb_ack_sr     : std_logic_vector(7 downto 0)               := (others => '0');
  signal wb_err_sr     : std_logic_vector(7 downto 0)               := (others => '0');
  signal err           : std_logic                                  := '0';
  signal ack           : std_logic                                  := '0';

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

    variable addr  : std_logic_vector(31 downto 0) := (others => '0');
    variable data  : std_logic_vector(31 downto 0) := (others => '0');
    variable wstrb : std_logic_vector(3 downto 0)  := (others => '1');

  begin

    test_runner_setup(runner, RUNNER_CFG);

    while test_suite loop

      prd_rst(16);

      if run("test_0") then
        info("Running test_0");

        info("Wishbone slave responds with an ack (no error) and in one clock cycle");
        wb_tb_error   <= '0';
        wb_tb_latency <= 1;

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

        info("Wishbone slave responds with an error and in three clock cycles");
        prd_wait_clk(8);
        wb_tb_error   <= '1';
        wb_tb_latency <= 3;
        prd_wait_clk(8);

        addr  := x"00000018";
        data  := x"44556677";
        wstrb := x"F";
        write_axi_lite(net, AXIM, addr, data, AXI_RSP_SLVERR, wstrb);
        check_axi_lite(net, AXIM, addr, AXI_RSP_SLVERR, data, "Check 4 failed.");

        info("Wishbone slave responds with an ack (no error) and in 5 clock cycles");
        prd_wait_clk(8);
        wb_tb_error   <= '0';
        wb_tb_latency <= 5;
        prd_wait_clk(8);

        addr  := x"0000001C";
        data  := x"AABBCCDD";
        wstrb := x"F";
        write_axi_lite(net, AXIM, addr, data, AXI_RSP_OKAY, wstrb);
        addr  := x"0000001C";
        data  := x"11223344";
        wstrb := x"8";
        write_axi_lite(net, AXIM, addr, data, AXI_RSP_OKAY, wstrb);
        addr  := x"0000001C";
        data  := x"11BBCCDD";
        check_axi_lite(net, AXIM, addr, AXI_RSP_OKAY, data, "Check 4 failed.");

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
  u_axil_to_wb : entity work.axil_to_wb
  port map (
    clk        => clk,
    srst       => srst,
    s_axil_req => axil_req,
    s_axil_rsp => axil_rsp,
    m_wb_req   => wb_req,
    m_wb_rsp   => wb_rsp
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

  -- ---------------------------------------------------------------------------
  prc_wishbone_mem : process (clk) is begin
    if rising_edge(clk) then
      wb_ack_sr <= wb_ack_sr(wb_ack_sr'left - 1 downto 0) & ack;
      wb_err_sr <= wb_err_sr(wb_err_sr'left - 1 downto 0) & err;

      if wb_req.stb then
        if wb_req.wen then
          for i in 0 to 3 loop
            if wb_req.wsel(i) then
              ram(to_integer(unsigned(wb_req.addr)))(i * 8 + 7 downto i * 8) <= wb_req.wdat(i * 8 + 7 downto i * 8);
            end if;
          end loop;
        else
          wb_rsp.rdat <= ram(to_integer(unsigned(wb_req.addr)));
        end if;
      end if;
    end if;
  end process;

  u_edge_detect : entity work.edge_detect
  generic map (
    G_WIDTH   => 2,
    G_OUT_REG => false
  )
  port map (
    clk     => clk,
    srst    => srst,
    din(0)  => wb_req.stb and not wb_tb_error,
    din(1)  => wb_req.stb and wb_tb_error,
    rise(0) => ack,
    rise(1) => err,
    fall    => open,
    both    => open
  );

  wb_rsp.ack <= wb_ack_sr(wb_tb_latency - 1);
  wb_rsp.err <= wb_err_sr(wb_tb_latency - 1);

end architecture;
