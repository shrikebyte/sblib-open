--##############################################################################
--# File : axis_cat.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! Packets are concatenated, in order, from lowest subordinate index up to
--! highest.
--! NOTICE: Does not pack tkeep for unaligned input packets. If this
--! feature is needed, then instantiate `axis_pack` between the output
--! of this module and the downstream module that requires packed tkeep.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_cat is
  port (
    clk    : in    std_ulogic;
    srst   : in    std_ulogic;
    --
    s_axis : view (s_axis_v) of axis_arr_t;
    --
    m_axis : view m_axis_v;
  );
end entity;

architecture rtl of axis_cat is

  signal sel : integer range s_axis'range;
  signal oe : std_ulogic;

begin

  -- ---------------------------------------------------------------------------
  prc_switch_on_tlast : process (clk) begin
    if rising_edge(clk) then
      if s_axis(sel).tvalid and s_axis(sel).tready and s_axis(sel).tlast then
        if sel = s_axis'high then
          sel <= s_axis'low;
        else
          sel <= sel + 1;
        end if;
      end if;

      if srst then
        sel <= s_axis'low;
      end if;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  oe <= m_axis.tready or not m_axis.tvalid;
  gen_assign_s_axis_tready : for i in s_axis'range generate
    s_axis(i).tready <= oe and to_sl((sel = i));
  end generate;

  prc_output : process(clk) is begin
    if rising_edge(clk) then
      if s_axis(sel).tvalid and oe then
        m_axis.tvalid <= '1';
        m_axis.tlast  <= s_axis(sel).tlast and to_sl(sel = s_axis'high);
        m_axis.tdata  <= s_axis(sel).tdata;
        m_axis.tkeep  <= s_axis(sel).tkeep;
        m_axis.tuser  <= s_axis(sel).tuser;
      elsif m_axis.tready then
        m_axis.tvalid <= '0';
      end if;

      if srst then
        m_axis.tvalid <= '0';
      end if;
    end if;
  end process;

end architecture;
