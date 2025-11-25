--##############################################################################
--# File : axil_to_apb.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! AXI Lite to APB bridge.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;

entity axil_to_apb is
  port (
    clk        : in    std_logic;
    srst       : in    std_logic;
    s_axil_req : in    axil_req_t;
    s_axil_rsp : out   axil_rsp_t;
    m_apb_req  : out   apb_req_t;
    m_apb_rsp  : in    apb_rsp_t
  );
end entity;

architecture rtl of axil_to_apb is

  -- ---------------------------------------------------------------------------
  signal wb_req    : wb_req_t;
  signal wb_rsp    : wb_rsp_t;
  signal wb_stb_re : std_logic;

begin

  -- ---------------------------------------------------------------------------
  u_axil_to_wb : entity work.axil_to_wb
  port map (
    clk        => clk,
    srst       => srst,
    s_axil_req => s_axil_req,
    s_axil_rsp => s_axil_rsp,
    m_wb_req   => wb_req,
    m_wb_rsp   => wb_rsp
  );

  -- ---------------------------------------------------------------------------
  u_edge_detect : entity work.edge_detect
  generic map (
    G_WIDTH   => 1,
    G_OUT_REG => false
  )
  port map (
    clk     => clk,
    srst    => srst,
    din(0)  => wb_req.stb,
    rise(0) => wb_stb_re
  );

  m_apb_req.psel    <= wb_req.stb;
  m_apb_req.penable <= wb_req.stb and not wb_stb_re;
  m_apb_req.pwrite  <= wb_req.wen;
  m_apb_req.paddr   <= wb_req.addr;
  m_apb_req.pwdata  <= wb_req.wdat;
  m_apb_req.pstrb   <= wb_req.wsel;
  wb_rsp.rdat       <= m_apb_rsp.prdata;
  wb_rsp.ack        <= m_apb_rsp.pready;
  wb_rsp.err        <= m_apb_rsp.pslverr;

end architecture;
