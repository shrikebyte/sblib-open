--##############################################################################
--# File : axis_broadcast.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! AXI-Stream Broadcast. Duplicate one input stream to several output streams.
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

  signal int0_axis_tready : std_ulogic_vector(m_axis'range);

  signal int0_axis : axis_arr_t(m_axis'range) (
    tdata(s_axis.tdata'range),
    tkeep(s_axis.tkeep'range),
    tuser(s_axis.tuser'range)
  );

  signal int1_axis : axis_arr_t(m_axis'range) (
    tdata(s_axis.tdata'range),
    tkeep(s_axis.tkeep'range),
    tuser(s_axis.tuser'range)
  );
  
begin

  s_axis.tready <= and int0_axis_tready;

  gen_broadcast : for i in m_axis'range generate

    int0_axis_tready(i) <= int0_axis(i).tready;
    int0_axis(i).tvalid <= s_axis.tvalid and s_axis.tready;
    int0_axis(i).tlast  <= s_axis.tlast;
    int0_axis(i).tdata  <= s_axis.tdata;
    int0_axis(i).tkeep  <= s_axis.tkeep;
    int0_axis(i).tuser  <= s_axis.tuser;

    u_axis_pipe : entity work.axis_pipe
    generic map(
      G_DATA_PIPE  => true,
      G_READY_PIPE => true
    )
    port map(
      clk    => clk,
      srst   => srst,
      s_axis => int0_axis(i),
      m_axis => int1_axis(i)
    );

    -- VIVADO BUG - As of Vivado 2025.2, vivado elaborator crashes here
    -- unless each port is assigned seperately.
    int1_axis(i).tready <= m_axis(i).tready;
    m_axis(i).tvalid <= int1_axis(i).tvalid;
    m_axis(i).tlast  <= int1_axis(i).tlast;
    m_axis(i).tkeep  <= int1_axis(i).tkeep;
    m_axis(i).tdata  <= int1_axis(i).tdata;
    m_axis(i).tuser  <= int1_axis(i).tuser;

  end generate;

end architecture;
