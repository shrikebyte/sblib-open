--##############################################################################
--# File : bfm_axil_man.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! AXI lite manager BFM. This is just an axil record wrapper around the vunit
--! bfm
--# ============================================================================
--# Copyright (c) 2024, David Gussler. All rights reserved.
--# You may use, distribute and modify this code under the
--# terms of the MIT license: https://choosealicense.com/licenses/mit/
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;

library vunit_lib;
context vunit_lib.vunit_context;
context vunit_lib.vc_context;

entity bfm_axil_man is
  generic (
    G_BUS_HANDLE : bus_master_t
  );
  port (
    clk        : in    std_logic;
    m_axil_req : out   axil_req_t;
    m_axil_rsp : in    axil_rsp_t
  );
end entity;

architecture sim of bfm_axil_man is

begin

  u_axi_lite_master : entity vunit_lib.axi_lite_master
  generic map (
    BUS_HANDLE => G_BUS_HANDLE
  )
  port map (
    aclk    => clk,
    arready => m_axil_rsp.arready,
    arvalid => m_axil_req.arvalid,
    araddr  => m_axil_req.araddr,
    rready  => m_axil_req.rready,
    rvalid  => m_axil_rsp.rvalid,
    rdata   => m_axil_rsp.rdata,
    rresp   => m_axil_rsp.rresp,
    awready => m_axil_rsp.awready,
    awvalid => m_axil_req.awvalid,
    awaddr  => m_axil_req.awaddr,
    wready  => m_axil_rsp.wready,
    wvalid  => m_axil_req.wvalid,
    wdata   => m_axil_req.wdata,
    wstrb   => m_axil_req.wstrb,
    bvalid  => m_axil_rsp.bvalid,
    bready  => m_axil_req.bready,
    bresp   => m_axil_rsp.bresp
  );

end architecture;
