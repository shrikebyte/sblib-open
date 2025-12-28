--##############################################################################
--# File : axis_demux.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! AXI-Stream de-multiplexer.
--! The `sel` select input can be changed at any time. The de-mux "locks on" to
--! a packet when the input channel's tvalid is high at the same time as it's
--! `sel` is selected. The demux releases a channel after the tlast beat.
--! This module inserts one bubble cycle per packet, as this is the design that
--! uses the most reasonable tradeoff between the competing variables of
--! latency, utilization, and combinatorial loading on s_axis.tready. For large
--! packets, this will essentially be neglegible and for packets sized one beat,
--! the best possible thruput of this module is 50%.
--! TODO: Consider adding an alternate implementation with no bubble cycles.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_demux is
  port (
    clk    : in    std_ulogic;
    srst   : in    std_ulogic;
    --
    s_axis : view s_axis_v;
    --
    m_axis : view (m_axis_v) of axis_arr_t;
    --! Output select
    sel : in integer range m_axis'range;
  );
end entity;

architecture rtl of axis_demux is

  type state_t is (ST_UNLOCKED, ST_LOCKED);
  signal state : state_t;
  signal sel_reg : integer range m_axis'range;
  signal oe : std_ulogic;

  signal int_axis_tvalid : std_ulogic_vector(m_axis'range);
  signal int_axis_tdata  : std_ulogic_vector(s_axis.tdata'range);
  signal int_axis_tuser  : std_ulogic_vector(s_axis.tuser'range);
  signal int_axis_tkeep  : std_ulogic_vector(s_axis.tkeep'range);
  signal int_axis_tlast  : std_ulogic;

begin

  -- ---------------------------------------------------------------------------
  oe <= m_axis(sel_reg).tready or not m_axis(sel_reg).tvalid;
  s_axis.tready <= oe and to_sl(state = ST_LOCKED);

  -- ---------------------------------------------------------------------------
  prc_select : process(clk) begin
    if rising_edge(clk) then

      if m_axis(sel_reg).tready then
        int_axis_tvalid(sel_reg) <= '0';
      end if;

      case state is
        when ST_UNLOCKED =>
          if s_axis.tvalid and oe then
            sel_reg <= sel;
            state <= ST_LOCKED;
          end if;

        when ST_LOCKED =>
          if s_axis.tvalid and oe then
            int_axis_tvalid(sel_reg) <= '1';
            int_axis_tlast <= s_axis.tlast;
            int_axis_tdata <= s_axis.tdata;
            int_axis_tkeep <= s_axis.tkeep;
            int_axis_tuser <= s_axis.tuser;

            if s_axis.tlast then
              state <= ST_UNLOCKED;
            end if;
          end if;
      end case;

      if srst then
        int_axis_tvalid <= (others=>'0');
        sel_reg <= m_axis'low;
        state  <= ST_UNLOCKED;
      end if;
    end if;
  end process;

  gen_assign_m_axis : for i in m_axis'range generate
    m_axis(i).tvalid <= int_axis_tvalid(i);
    m_axis(i).tlast  <= int_axis_tlast;
    m_axis(i).tdata  <= int_axis_tdata;
    m_axis(i).tkeep  <= int_axis_tkeep;
    m_axis(i).tuser  <= int_axis_tuser;
  end generate;

end architecture;
