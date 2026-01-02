--##############################################################################
--# File : axis_fifo.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! Synchronous AXI Stream FIFO.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_fifo is
  generic (
    -- Depth of the FIFO in axis beats. Must be a power of 2.
    G_DEPTH : positive := 1024;
    -- If true, then output will not go valid until one full packet has been
    -- stored at the input. This guarentees that output valid will never
    -- be lowered during a packet.
    G_PACKET_MODE : boolean := false;
    -- Drop oversized packets that do not fit in the FIFO. Only applicable
    -- when `G_PACKET_MODE` is true.
    G_DROP_OVERSIZE : boolean := false;
    --
    G_USE_TLAST : boolean := true;
    G_USE_TKEEP : boolean := true;
    G_USE_TUSER : boolean := true;
  );
  port (
    clk  : in    std_logic;
    srst : in    std_logic;
    --
    s_axis : view s_axis_v;
    --
    m_axis : view m_axis_v;
    --
    -- Drop the current packet that is being written to the FIFO
    ctl_drop : in std_ulogic;
    -- Current fill depth of the FIFO, in beats
    sts_depth  : out  unsigned(clog2(G_DEPTH) downto 0)
  );
end entity;

architecture rtl of axis_fifo is

  constant DW : integer := m_axis.tdata'length;
  constant KW : integer := if_then_else(G_USE_TKEEP, m_axis.tkeep'length, 0);
  constant UW : integer := if_then_else(G_USE_TUSER, m_axis.tuser'length, 0);
  constant LW : integer := if_then_else(G_USE_TLAST, 1, 0);
  constant RW : integer := DW + UW + KW + LW; -- Ram width
  constant AW : integer := clog2(G_DEPTH); -- Address width

  signal ram : slv_arr_t(0 to G_DEPTH - 1)(RW - 1 downto 0);

  signal wr_ptr : u_unsigned(AW downto 0);
  signal rd_ptr : u_unsigned(AW downto 0);

  signal wr_data : std_ulogic_vector(RW - 1 downto 0);
  signal rd_data : std_ulogic_vector(RW - 1 downto 0);

  signal full : std_ulogic;
  signal empty : std_ulogic;

begin

  -- ---------------------------------------------------------------------------
  assert is_pwr2(G_DEPTH)
    report "axis_fifo: Depth must be a power of 2."
    severity error;

  assert not (G_USE_TLAST = false and G_PACKET_MODE = true)
    report "G_PACKET_MODE requires G_USE_TLAST to be enabled."
    severity failure;

  assert not (G_PACKET_MODE = false and G_DROP_OVERSIZE = true)
    report "G_DROP_OVERSIZE requires G_PACKET_MODE to be enabled."
    severity failure;

  -- ---------------------------------------------------------------------------
  wr_data(DW - 1 downto 0) <= s_axis.tdata;
  m_axis.tdata <= rd_data(DW - 1 downto 0);

  gen_assign_tkeep : if G_USE_TKEEP generate
    wr_data(DW + KW - 1 downto DW) <= s_axis.tkeep;
    m_axis.tkeep <= rd_data(DW + KW - 1 downto DW);
  end generate;

  gen_assign_tuser : if G_USE_TUSER generate
    wr_data(DW + KW + UW - 1 downto DW + KW) <= s_axis.tuser;
    m_axis.tuser <= rd_data(DW + KW + UW - 1 downto DW + KW);
  end generate;

  gen_assign_tlast : if G_USE_TLAST generate
    wr_data(DW + KW + UW + LW - 1) <= s_axis.tlast;
    m_axis.tlast <= rd_data(DW + KW + UW + LW - 1);
  end generate;

  -- ---------------------------------------------------------------------------
  full <= to_sl(
    wr_ptr(AW) /= rd_ptr(AW) and
    wr_ptr(AW - 1 downto 0) = rd_ptr(AW - 1 downto 0)
  );

  empty <= to_sl(wr_ptr = rd_ptr);

  s_axis.tready <= not full;

  -- ---------------------------------------------------------------------------
  prc_write : process (clk) is begin
    if rising_edge(clk) then

      if s_axis.tvalid and s_axis.tready then
        ram(to_integer(wr_ptr(AW - 1 downto 0))) <= wr_data;
        wr_ptr <= wr_ptr + 1;
      end if;

      if srst then
        wr_ptr <= (others => '0');
      end if;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  prc_read : process (clk) is begin
    if rising_edge(clk) then

      if m_axis.tready then
        m_axis.tvalid <= '0';
      end if;

      if m_axis.tready or not m_axis.tvalid then
        if not empty then
          m_axis.tvalid <= '1';
          rd_data <= ram(to_integer(rd_ptr(AW - 1 downto 0)));
          rd_ptr <= rd_ptr + 1;
        end if;
      end if;

      if srst then
        m_axis.tvalid <= '0';
        rd_ptr <= (others => '0');
      end if;
    end if;
  end process;

end architecture;
