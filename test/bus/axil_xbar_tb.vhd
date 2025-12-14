--##############################################################################
--# File : axil_xbar_tb.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! AXI Lite crossbar testbench
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;

library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.vc_context;
use vunit_lib.axi_lite_master_pkg.all;

entity axil_xbar_tb is
  generic (
    RUNNER_CFG : string
  );
end entity;

architecture tb of axil_xbar_tb is

  -- Testbench constants
  constant CLK_PERIOD  : time     := 10 ns;
  constant CLK_TO_Q    : time     := 1 ns;
  constant NUM_MASTERS : positive := 4;
  constant NUM_SLAVES  : positive := 4;

  constant BASEADDRS : slv_arr_t(0 to NUM_SLAVES - 1)(AXIL_ADDR_WIDTH - 1 downto 0) := (
    0 => x"0000_0000",
    1 => x"0001_0000",
    2 => x"000F_0000",
    3 => x"0110_0000"
  );

  -- DUT ports
  signal clk          : std_logic := '1';
  signal srst         : std_logic := '1';
  signal axil_req_cpu : axil_req_arr_t(0 to NUM_MASTERS - 1);
  signal axil_rsp_cpu : axil_rsp_arr_t(0 to NUM_MASTERS - 1);
  signal axil_req_ram : axil_req_arr_t(0 to NUM_SLAVES - 1);
  signal axil_rsp_ram : axil_rsp_arr_t(0 to NUM_SLAVES - 1);

  type bus_master_arr_t is array (natural range<>) of bus_master_t;

  -- Testbench BFMs
  constant AXIM : bus_master_arr_t(0 to NUM_MASTERS - 1) := (
    0 => new_bus(AXIL_DATA_WIDTH, AXIL_ADDR_WIDTH),
    1 => new_bus(AXIL_DATA_WIDTH, AXIL_ADDR_WIDTH),
    2 => new_bus(AXIL_DATA_WIDTH, AXIL_ADDR_WIDTH),
    3 => new_bus(AXIL_DATA_WIDTH, AXIL_ADDR_WIDTH)
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

        -- Generate transactions
        for master in 0 to NUM_MASTERS - 1 loop
          for slave in 0 to NUM_SLAVES - 1 loop
            for transaction in 1 to 10 loop
              addr  := BASEADDRS(slave) or (std_logic_vector(to_unsigned(transaction + (master * 16), AXIL_ADDR_WIDTH - 2)) & b"00");
              data  := addr;
              wstrb := x"F";
              write_axi_lite(net, AXIM(master), addr, data, AXI_RSP_OKAY, wstrb);
            end loop;
          end loop;
        end loop;

        -- Check transactions
        for master in 0 to NUM_MASTERS - 1 loop
          for slave in 0 to NUM_SLAVES - 1 loop
            for transaction in 1 to 10 loop
              addr := BASEADDRS(slave) or (std_logic_vector(to_unsigned(transaction + (master * 16), AXIL_ADDR_WIDTH - 2)) & b"00");
              data := addr;
              check_axi_lite(net, AXIM(master), addr, AXI_RSP_OKAY, data, "Check during read loop failed.");
            end loop;
          end loop;
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
  u_axil_xbar : entity work.axil_xbar
  generic map (
    G_NUM_MASTERS => NUM_MASTERS,
    G_NUM_SLAVES  => NUM_SLAVES,
    G_BASEADDRS   => BASEADDRS
  )
  port map (
    clk        => clk,
    srst       => srst,
    s_axil_req => axil_req_cpu,
    s_axil_rsp => axil_rsp_cpu,
    m_axil_req => axil_req_ram,
    m_axil_rsp => axil_rsp_ram
  );

  -- ---------------------------------------------------------------------------
  gen_masters : for i in 0 to NUM_MASTERS - 1 generate

    u_axil_bfm : entity work.bfm_axil_man
    generic map (
      G_BUS_HANDLE => AXIM(i)
    )
    port map (
      clk        => clk,
      m_axil_req => axil_req_cpu(i),
      m_axil_rsp => axil_rsp_cpu(i)
    );

  end generate;

  -- ---------------------------------------------------------------------------
  gen_slaves : for i in 0 to NUM_SLAVES - 1 generate

    u_axil_ram : entity work.axil_ram
    generic map (
      G_ADDR_WIDTH => 10,
      G_RD_LATENCY => 2
    )
    port map (
      clk        => clk,
      srst       => srst,
      s_axil_req => axil_req_ram(i),
      s_axil_rsp => axil_rsp_ram(i)
    );

  end generate;

end architecture;
