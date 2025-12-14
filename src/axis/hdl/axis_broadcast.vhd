--##############################################################################
--# File : axis_broadcast.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! AXI-Stream Broadcast. Broadcast one input stream to several output streams.
--! This just sends one source stream to several destinations.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_broadcast is
  port (
    clk    : in    std_ulogic;
    srst   : in    std_ulogic;
    --
    s_axis : view s_axis_v;
    --
    m_axis : view (m_axis_v) of axis_arr_t;
  );
end entity;

architecture rtl of axis_broadcast is
  signal m_axis_tready : std_logic_vector(m_axis'range);
begin

  s_axis.tready <= and m_axis_tready;

  gen_broadcast : for i in m_axis'range generate
    m_axis_tready(i) <= m_axis(i).tready;

    m_axis(i).tvalid <= s_axis.tvalid and s_axis.tready;
    m_axis(i).tlast  <= s_axis.tlast;
    m_axis(i).tdata  <= s_axis.tdata;
    m_axis(i).tkeep  <= s_axis.tkeep;
    m_axis(i).tuser  <= s_axis.tuser;
  end generate;

end architecture;
