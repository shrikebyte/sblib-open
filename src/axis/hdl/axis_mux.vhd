--##############################################################################
--# File : axis_mux.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--# Multiplexes a stream.
--# The `sel` select input can be changed at any time. The mux "locks on" to
--# a packet when the input channel's tvalid is high at the same time as it's
--# `sel` is selected. The mux releases a channel after the tlast beat.
--# This module inserts one bubble cycle per packet, as this is the design that
--# uses the most reasonable tradeoff between the competing variables of
--# latency, utilization, and combinatorial loading on s_axis.tready. For large
--# packets, the bubble will be negligible compared to the overall packet, but
--# for packets sized one beat, the best possible thruput of this module is 50%.
--#
--# TODO: Consider an alternate implementation with no bubble cycles.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_mux is
  port (
    clk    : in    std_ulogic;
    srst   : in    std_ulogic;
    --
    s_axis : view (s_axis_v) of axis_arr_t;
    --
    m_axis : view m_axis_v;
    --! Input Select
    sel    : in integer range s_axis'range
  );
end entity;

architecture rtl of axis_mux is

  type state_t is (ST_UNLOCKED, ST_LOCKED);
  signal state : state_t;
  signal sel_reg : integer range s_axis'range;
  signal oe : std_ulogic;

begin

  -- ---------------------------------------------------------------------------
  oe <= m_axis.tready or not m_axis.tvalid;
  gen_assign_s_axis_tready : for i in s_axis'range generate
    s_axis(i).tready <= oe and to_sl(state = ST_LOCKED and sel_reg = i);
  end generate;

  -- ---------------------------------------------------------------------------
  prc_select : process(clk) begin
    if rising_edge(clk) then

      if m_axis.tready then
        m_axis.tvalid <= '0';
      end if;

      case state is
        when ST_UNLOCKED =>
          if s_axis(sel).tvalid and oe then
            sel_reg <= sel;
            state <= ST_LOCKED;
          end if;

        when ST_LOCKED =>
          if s_axis(sel_reg).tvalid and oe then
            m_axis.tvalid <= '1';
            m_axis.tlast  <= s_axis(sel_reg).tlast;
            m_axis.tdata  <= s_axis(sel_reg).tdata;
            m_axis.tkeep  <= s_axis(sel_reg).tkeep;
            m_axis.tuser  <= s_axis(sel_reg).tuser;

            if s_axis(sel_reg).tlast then
              state <= ST_UNLOCKED;
            end if;
          end if;
      end case;

      if srst then
        m_axis.tvalid <= '0';
        sel_reg <= s_axis'low;
        state  <= ST_UNLOCKED;
      end if;
    end if;
  end process;

end architecture;
