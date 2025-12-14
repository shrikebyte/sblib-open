--##############################################################################
--# File : axis_demux.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! AXI-Stream de-multiplexer.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_demux is
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
    s_axis : view s_axis_v;
    --
    m_axis : view (m_axis_v) of axis_arr_t;
    --! Output select
    sel    : in integer range m_axis'range;
  );
end entity;

architecture rtl of axis_demux is

  type state_t is (ST_UNLOCKED, ST_LOCKED);
  signal state_reg : state_t;
  signal sel_reg : integer range m_axis'range;

begin

  -- ---------------------------------------------------------------------------
  gen_low_area : if G_LOW_AREA generate
  begin

    prc_select_ff : process(clk) begin
      if rising_edge(clk) then
        case state_reg is
          when ST_UNLOCKED =>
            if s_axis.tvalid then
              sel_reg <= sel;
              state_reg <= ST_LOCKED;
            end if;
          when ST_LOCKED =>
            if m_axis(sel_reg).tvalid and 
               m_axis(sel_reg).tready and 
               m_axis(sel_reg).tlast then
              state_reg <= ST_UNLOCKED;
            end if;
        end case;

        if srst then
          sel_reg <= 0;
          state_reg <= ST_UNLOCKED;
        end if;
      end if;
    end process;

    gen_assign_m_axis : for i in m_axis'range generate
      prc_out_sel : process (all) begin
        m_axis(i).tvalid <= (s_axis.tvalid) and 
                            (state_reg = ST_LOCKED) and 
                            (sel_reg = i);
        m_axis(i).tlast  <= s_axis.tlast;
        m_axis(i).tdata  <= s_axis.tdata;
        m_axis(i).tkeep  <= s_axis.tkeep;
        m_axis(i).tuser  <= s_axis.tuser;
      end process;
    end generate;

    s_axis.tready <= (m_axis(sel_reg).tready) and (state_reg = ST_LOCKED);

  -- ---------------------------------------------------------------------------
  else generate
    signal state_nxt : state_t;
    signal sel_nxt : integer range m_axis'range;
  begin

    prc_select_comb : process(all) begin
      sel_nxt <= sel_reg;
      state_nxt <= state_reg;

      case state_reg is
        when ST_UNLOCKED =>
          if s_axis.tvalid then
            sel_nxt <= sel;
            state_nxt <= ST_LOCKED;
          end if;
        when ST_LOCKED =>
          if m_axis(sel_reg).tvalid and 
             m_axis(sel_reg).tready and 
             m_axis(sel_reg).tlast then
            if s_axis.tvalid then
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
          sel_reg    <= m_axis'low;
          state_reg  <= ST_UNLOCKED;
        end if;
      end if;
    end process;

    gen_assign_m_axis : for i in m_axis'range generate
      prc_out_sel : process (clk) begin
        if rising_edge(clk) then
          if s_axis.tvalid and s_axis.tready and (sel_nxt = i) then
            m_axis(i).tvalid <= '1';
            m_axis(i).tlast  <= s_axis.tlast;
            m_axis(i).tdata  <= s_axis.tdata;
            m_axis(i).tkeep  <= s_axis.tkeep;
            m_axis(i).tuser  <= s_axis.tuser;
          elsif m_axis(i).tready then
            m_axis(i).tvalid <= '0';
          end if;

          if srst then
            m_axis(i).tvalid <= '0';
          end if;
        end if;
      end process;
    end generate;

    s_axis.tready <= (m_axis(sel_nxt).tready or not m_axis(sel_nxt).tvalid) and 
                     (state_nxt = ST_LOCKED);

  end generate;

end architecture;
