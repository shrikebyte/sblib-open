--##############################################################################
--# File : axis_arb.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! AXI-Stream arbiter.
--! Simple, fixed priority, packet arbiter. Higher subordinate channel numbers
--! have higher priority.
--! NOTICE: Since this is fixed-priority, if a higher channel is sending data
--! every clock cycle, it is possible for it to hog all of the bandwidth,
--! preventing lower channels from ever sending data.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_arb is
  generic (
    --! Use a lower area implementation. This results in one bubble cycle per
    --! packet. For large packet sizes, or where throughput is a less of a
    --! concern than utilization, this alternate implementation makes sense.
    G_LOW_AREA : boolean := false
  );
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
  generic map(
    G_LOW_AREA => G_LOW_AREA
  )
  port map(
    clk => clk,
    srst => srst,
    s_axis => s_axis,
    m_axis => m_axis,
    sel => sel
  );

end architecture;
