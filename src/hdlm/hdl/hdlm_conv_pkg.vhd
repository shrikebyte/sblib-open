--##############################################################################
--# File : conv_pkg.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! Convert between util_pkg types and hdl-modules types
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.axi_lite_pkg.all;
use work.util_pkg.all;

package hdlm_conv_pkg is

  function to_hdlm (
    axil_req : axil_req_t
  ) return axi_lite_m2s_t;

  function to_hdlm (
    axi_lite_s2m : axi_lite_s2m_t
  ) return axil_rsp_t;

end package;

package body hdlm_conv_pkg is

  function to_hdlm (
    axil_req : axil_req_t
  ) return axi_lite_m2s_t is
    variable axi_lite_m2s : axi_lite_m2s_t := axi_lite_m2s_init;
  begin

    axi_lite_m2s.read.ar.valid                  := axil_req.arvalid;
    axi_lite_m2s.read.ar.addr(axil_addr_range)  := unsigned(axil_req.araddr);
    axi_lite_m2s.read.r.ready                   := axil_req.rready;
    axi_lite_m2s.write.aw.valid                 := axil_req.awvalid;
    axi_lite_m2s.write.aw.addr(axil_addr_range) := unsigned(axil_req.awaddr);
    axi_lite_m2s.write.w.valid                  := axil_req.wvalid;
    axi_lite_m2s.write.w.data(axil_data_range)  := axil_req.wdata;
    axi_lite_m2s.write.w.strb(axil_strb_range)  := axil_req.wstrb;
    axi_lite_m2s.write.b.ready                  := axil_req.bready;

    return axi_lite_m2s;
  end function;

  function to_hdlm (
    axi_lite_s2m : axi_lite_s2m_t
  ) return axil_rsp_t is
    variable axil_rsp : axil_rsp_t;
  begin

    axil_rsp.arready := axi_lite_s2m.read.ar.ready;
    axil_rsp.rvalid  := axi_lite_s2m.read.r.valid;
    axil_rsp.rdata   := axi_lite_s2m.read.r.data(axil_data_range);
    axil_rsp.rresp   := axi_lite_s2m.read.r.resp;
    axil_rsp.awready := axi_lite_s2m.write.aw.ready;
    axil_rsp.wready  := axi_lite_s2m.write.w.ready;
    axil_rsp.bvalid  := axi_lite_s2m.write.b.valid;
    axil_rsp.bresp   := axi_lite_s2m.write.b.resp;

    return axil_rsp;
  end function;

end package body;
