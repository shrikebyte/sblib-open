--##############################################################################
--# File : axis_mux.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! AXI-Stream multiplexer.
--! The `sel` select input can be changed at any time. The mux "locks on" to
--! a packet when the input channel's tvalid is high at the same time as it's
--! `sel` is selected. The mux releases a channel after the tlast beat.
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
  signal state_nxt : state_t;
  signal state_reg : state_t;
  signal sel_nxt : integer range s_axis'range;
  signal sel_reg : integer range s_axis'range;

begin

  -- ---------------------------------------------------------------------------
  prc_select_comb : process(all) begin
    sel_nxt <= sel_reg;
    state_nxt <= state_reg;

    case state_reg is
      when ST_UNLOCKED =>
        if s_axis(sel).tvalid then
          sel_nxt <= sel;
          state_nxt <= ST_LOCKED;
        end if;
      when ST_LOCKED =>
        if m_axis.tvalid and m_axis.tready and m_axis.tlast then
          if s_axis(sel).tvalid then
            sel_nxt <= sel;
          else
            state_nxt <= ST_UNLOCKED;
          end if;
        end if;
    end case;
  end process;

  prc_select_ff : process(clk) begin
    if rising_edge(clk) then
      sel_reg <= sel_nxt;
      state_reg <= state_nxt;

      if srst then
        sel_reg    <= s_axis'low;
        state_reg  <= ST_UNLOCKED;
      end if;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  gen_assign_s_axis_tready : for i in s_axis'range generate
    s_axis(i).tready <= (m_axis.tready or not m_axis.tvalid) and
                         to_sl((sel_nxt = i));
  end generate;

  prc_output_ff : process(clk) begin
    if rising_edge(clk) then
      if s_axis(sel_nxt).tvalid and s_axis(sel_nxt).tready then
        m_axis.tvalid <= '1';
        m_axis.tlast  <= s_axis(sel_nxt).tlast;
        m_axis.tdata  <= s_axis(sel_nxt).tdata;
        m_axis.tkeep  <= s_axis(sel_nxt).tkeep;
        m_axis.tuser  <= s_axis(sel_nxt).tuser;
      elsif m_axis.tready then
        m_axis.tvalid <= '0';
      end if;

      if srst then
        m_axis.tvalid <= '0';
      end if;
    end if;
  end process;

end architecture;
