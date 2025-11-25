--##############################################################################
--# File : apb_to_axil.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! APB to AXI Lite bridge.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;

entity apb_to_axil is
  port (
    clk        : in    std_logic;
    srst       : in    std_logic;
    s_apb_req  : in    apb_req_t;
    s_apb_rsp  : out   apb_rsp_t;
    m_axil_req : out   axil_req_t;
    m_axil_rsp : in    axil_rsp_t
  );
end entity;

architecture rtl of apb_to_axil is

  -- ---------------------------------------------------------------------------
  signal wb_req : wb_req_t;
  signal wb_rsp : wb_rsp_t;

begin

  -- ---------------------------------------------------------------------------
  u_wb_to_axil : entity work.wb_to_axil
  port map (
    clk        => clk,
    srst       => srst,
    s_wb_req   => wb_req,
    s_wb_rsp   => wb_rsp,
    m_axil_req => m_axil_req,
    m_axil_rsp => m_axil_rsp
  );

  wb_req.stb        <= s_apb_req.psel and s_apb_req.penable;
  wb_req.wen        <= s_apb_req.pwrite;
  wb_req.addr       <= s_apb_req.paddr;
  wb_req.wdat       <= s_apb_req.pwdata;
  wb_req.wsel       <= s_apb_req.pstrb;
  s_apb_rsp.prdata  <= wb_rsp.rdat;
  s_apb_rsp.pready  <= wb_rsp.ack;
  s_apb_rsp.pslverr <= wb_rsp.err;

end architecture;
