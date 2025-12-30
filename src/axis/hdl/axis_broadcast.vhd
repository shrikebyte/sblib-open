--##############################################################################
--# File : axis_broadcast.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--# Broadcasts one input stream to several output streams.
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

  signal int_axis_tready : std_ulogic_vector(m_axis'range);
  signal int_axis_tvalid : std_ulogic_vector(m_axis'range);
  signal int_axis_tdata  : std_ulogic_vector(s_axis.tdata'range);
  signal int_axis_tuser  : std_ulogic_vector(s_axis.tuser'range);
  signal int_axis_tkeep  : std_ulogic_vector(s_axis.tkeep'range);
  signal int_axis_tlast  : std_ulogic;

begin

  -- ---------------------------------------------------------------------------
  s_axis.tready <= (and int_axis_tready) or not (or int_axis_tvalid);

  -- ---------------------------------------------------------------------------
  prc_broadcast : process(clk) begin
    if rising_edge(clk) then

      for i in m_axis'range loop
        if int_axis_tready(i) then
          int_axis_tvalid(i) <= '0';
        end if;
      end loop;

      if s_axis.tvalid and s_axis.tready then
        int_axis_tvalid <= (others=>'1');
        int_axis_tlast  <= s_axis.tlast;
        int_axis_tdata  <= s_axis.tdata;
        int_axis_tkeep  <= s_axis.tkeep;
        int_axis_tuser  <= s_axis.tuser;
      end if;

      if srst then
        int_axis_tvalid <= (others=>'0');
      end if;
    end if;
  end process;

  gen_assign_outputs : for i in m_axis'range generate
    int_axis_tready(i) <= m_axis(i).tready;
    m_axis(i).tvalid   <= int_axis_tvalid(i);
    m_axis(i).tlast    <= int_axis_tlast;
    m_axis(i).tdata    <= int_axis_tdata;
    m_axis(i).tkeep    <= int_axis_tkeep;
    m_axis(i).tuser    <= int_axis_tuser;
  end generate;

end architecture;
