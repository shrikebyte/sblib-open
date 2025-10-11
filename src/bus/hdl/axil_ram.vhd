--##############################################################################
--# File     : axil_ram.vhd
--# Author   : David Gussler
--# Language : VHDL '08
--# ============================================================================
--! AXI lite ram.
--! Supports full thruput one read and one write per clock cycle.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use work.util_pkg.all;

entity axil_ram is
  generic (
    -- Address width of the RAM. RAM uses word addressing and AXIL uses byte
    -- addressing. So the AXIL address is left-shifted by 2 by this module
    -- before being connected to the ram. This also means that the number of
    -- AXIL address bits used is equal to G_ADDR_WIDTH + 2.
    G_ADDR_WIDTH : positive                                                              := 10;
    G_RAM_STYLE  : string                                                                := "auto";
    G_RAM_INIT   : slv_arr_t(0 to (2 ** G_ADDR_WIDTH) - 1)(AXIL_DATA_WIDTH - 1 downto 0) := (others=> (others=> '0'));
    G_RD_LATENCY : positive                                                              := 1
  );
  port (
    clk        : in    std_logic;
    srst       : in    std_logic;
    s_axil_req : in    axil_req_t;
    s_axil_rsp : out   axil_rsp_t
  );
end entity;

architecture rtl of axil_ram is

  signal ram_req : reg_req_t;
  signal ram_rsp : reg_rsp_t;

begin

  -- ---------------------------------------------------------------------------
  u_axil_to_reg : entity work.axil_to_reg
  generic map (
    G_RD_LATENCY => G_RD_LATENCY
  )
  port map (
    clk        => clk,
    srst       => srst,
    s_axil_req => s_axil_req,
    s_axil_rsp => s_axil_rsp,
    m_reg_req  => ram_req,
    m_reg_rsp  => ram_rsp
  );

  -- ---------------------------------------------------------------------------
  u_ram : entity work.ram
  generic map (
    G_BYTES_PER_ROW => 4,
    G_BYTE_WIDTH    => 8,
    G_ADDR_WIDTH    => G_ADDR_WIDTH,
    G_RAM_STYLE     => G_RAM_STYLE,
    G_RAM_INIT      => G_RAM_INIT,
    G_RD_LATENCY    => G_RD_LATENCY
  )
  port map (
    a_clk  => clk,
    a_en   => ram_req.wen,
    a_wen  => ram_req.wstrb,
    a_addr => ram_req.waddr(G_ADDR_WIDTH - 1 + 2 downto 2),
    a_wdat => ram_req.wdata,
    a_rdat => open,
    b_clk  => clk,
    b_en   => '1',
    b_wen  => b"0000",
    b_addr => ram_req.raddr(G_ADDR_WIDTH - 1 + 2 downto 2),
    b_wdat => (others=>'0'),
    b_rdat => ram_rsp.rdata
  );

  ram_rsp.werr <= '0';
  ram_rsp.rerr <= '0';

end architecture;
