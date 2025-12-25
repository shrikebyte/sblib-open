--##############################################################################
--# File : axis_cat.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! AXI-Stream concatenate.
--! Packets are concatenated, in order, from lowest subordinate index up to
--! highest.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_cat is
  generic (
    --! If false - this module just acts as a simple ordered switch for input
    --! packets. It does not shift partial beats.
    --! If true - this module shifts partial beats to generate fully-packed
    --! output packets.
    --! If the user can guarantee that input tkeep is always all ones or if
    --! downstream modules can accept non-packet packets, then
    --! set this to false to save resources.
    G_PACK_OUTPUT : boolean := true;
    --! Add an extra pipeline register to the internal datapath.
    G_DATA_PIPE  : boolean  := false;
    --! Add an extra pipeline register to the internal backpressure path.
    G_READY_PIPE : boolean  := false
  );
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

  signal int0_axis : axis_t (
    tdata(m_axis.tdata'range),
    tkeep(m_axis.tkeep'range),
    tuser(m_axis.tuser'range)
  );

  signal int1_axis : axis_t (
    tdata(m_axis.tdata'range),
    tkeep(m_axis.tkeep'range),
    tuser(m_axis.tuser'range)
  );

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
  gen_assign_s_axis_tready : for i in s_axis'range generate
    s_axis(i).tready <= int0_axis.tready and to_sl((sel = i));
  end generate;

  int0_axis.tvalid <= s_axis(sel).tvalid and s_axis(sel).tready;
  int0_axis.tlast  <= s_axis(sel).tlast and to_sl((sel = s_axis'high));
  int0_axis.tkeep  <= s_axis(sel).tkeep;
  int0_axis.tdata  <= s_axis(sel).tdata;
  int0_axis.tuser  <= s_axis(sel).tuser;

  -- ---------------------------------------------------------------------------
  u_axis_pipe0 : entity work.axis_pipe
  generic map(
    G_READY_PIPE => G_READY_PIPE,
    G_DATA_PIPE  => G_DATA_PIPE
  )
  port map(
    clk    => clk,
    srst   => srst,
    s_axis => int0_axis,
    m_axis => int1_axis
  );

  -- ---------------------------------------------------------------------------
  gen_packer : if G_PACK_OUTPUT generate

    u_axis_pack : entity work.axis_pack
    port map(
      clk    => clk,
      srst   => srst,
      s_axis => int1_axis,
      m_axis => m_axis
    );

  else generate

    u_axis_pipe : entity work.axis_pipe
    generic map(
      G_READY_PIPE => false,
      G_DATA_PIPE  => false
    )
    port map(
      clk => clk,
      srst => srst,
      s_axis => int1_axis,
      m_axis => m_axis
    );

  end generate;

end architecture;
