--##############################################################################
--# File : axis_arb.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--# Arbitrates packets with simple, fixed-priority. Higher subordinate
--# channel numbers have higher priority.
--#
--# NOTICE: Since this uses fixed-priority, if a higher channel holds valid high
--# on every clock cycle, then it will hog all of the bandwidth,
--# preventing the lower channels from ever sending data.
--#
--# TODO: Add round-robin arbitration.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_arb is
  port (
    clk    : in    std_ulogic;
    srst   : in    std_ulogic;
    --
    s_axis : view (s_axis_v) of axis_arr_t;
    --
    m_axis : view m_axis_v
  );
end entity;

architecture rtl of axis_arb is

  signal sel : integer range s_axis'range;

begin

  -- ---------------------------------------------------------------------------
  prc_arb_sel : process(all) begin
    for i in s_axis'range loop
      if s_axis(i).tvalid then
        sel <= i;
      end if;
    end loop;
  end process;

  -- ---------------------------------------------------------------------------
  u_axis_mux : entity work.axis_mux
  port map(
    clk => clk,
    srst => srst,
    s_axis => s_axis,
    m_axis => m_axis,
    sel => sel
  );

end architecture;
