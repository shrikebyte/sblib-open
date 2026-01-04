--##############################################################################
--# File : axis_fifo.vhd
--# Auth : David Gussler
--# Lang : VHDL '19
--# ============================================================================
--# Synchronous AXI Stream FIFO.
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
    -- stored at the input. This guarantees that output valid will never
    -- be lowered during a packet.
    G_PACKET_MODE : boolean := false;
    -- Drop oversized packets that do not fit in the FIFO.
    -- Only applicable in packet mode.
    G_DROP_OVERSIZE : boolean := false;
    --
    G_USE_TLAST : boolean := true;
    G_USE_TKEEP : boolean := true;
    G_USE_TUSER : boolean := true
  );
  port (
    clk  : in    std_logic;
    srst : in    std_logic;
    --
    s_axis : view s_axis_v;
    --
    m_axis : view m_axis_v;
    --
    -- Drop the current packet that is being written or next packet that will be
    -- written to the FIFO. This input
    -- can be pulsed at any time. It is not confined
    -- to the axis handshaking mechanism. For example:
    --   Cycle 1: valid=1, ready=1, last=0 ctl_drop=0
    --   Cycle 2: valid=0, ready=1, last=0 ctl_drop=1
    --   Cycle 3: valid=1, ready=1, last=1 ctl_drop=0
    --   Packet is dropped.
    -- Only applicable in packet mode.
    ctl_drop : in    std_ulogic;
    -- Pulse indicating that the last packet was dropped.
    -- Only applicable in packet mode.
    sts_dropped : out   std_ulogic;
    -- Current speculative fill depth of the FIFO, in beats.
    sts_depth_spec : out   u_unsigned(clog2(G_DEPTH) downto 0);
    -- Current committed fill depth of the FIFO, in beats.
    -- Only applicable in packet mode.
    sts_depth_comm : out   u_unsigned(clog2(G_DEPTH) downto 0)
  );
end entity;

architecture rtl of axis_fifo is

  constant DW : integer := m_axis.tdata'length;
  constant KW : integer := if_then_else(G_USE_TKEEP, m_axis.tkeep'length, 0);
  constant UW : integer := if_then_else(G_USE_TUSER, m_axis.tuser'length, 0);
  constant LW : integer := if_then_else(G_USE_TLAST, 1, 0);
  constant RW : integer := DW + UW + KW + LW; -- Ram width
  constant AW : integer := clog2(G_DEPTH); -- Address width

  signal ram     : slv_arr_t(0 to G_DEPTH - 1)(RW - 1 downto 0);
  signal wr_data : std_ulogic_vector(RW - 1 downto 0);
  signal rd_data : std_ulogic_vector(RW - 1 downto 0);

  signal rd_ptr      : u_unsigned(AW downto 0);
  signal wr_ptr_spec : u_unsigned(AW downto 0);
  signal wr_ptr_comm : u_unsigned(AW downto 0);
  signal empty       : std_ulogic;
  signal full        : std_ulogic;
  signal full_wr     : std_ulogic;

  signal drop_reg : std_ulogic;
  signal send_reg : std_ulogic;

begin

  -- ---------------------------------------------------------------------------
  assert is_pwr2(G_DEPTH)
    report "axis_fifo: Depth must be a power of 2."
    severity error;

  assert not (G_USE_TLAST = false and G_PACKET_MODE = true)
    report "axis_fifo: G_PACKET_MODE requires G_USE_TLAST to be enabled."
    severity failure;

  assert not (G_PACKET_MODE = false and G_DROP_OVERSIZE = true)
    report "axis_fifo: G_DROP_OVERSIZE requires G_PACKET_MODE to be enabled."
    severity failure;

  -- ---------------------------------------------------------------------------
  wr_data(DW - 1 downto 0) <= s_axis.tdata;
  m_axis.tdata             <= rd_data(DW - 1 downto 0);

  gen_assign_tkeep : if G_USE_TKEEP generate
    wr_data(DW + KW - 1 downto DW) <= s_axis.tkeep;
    m_axis.tkeep                   <= rd_data(DW + KW - 1 downto DW);
  else generate
    m_axis.tkeep <= (others=>'1');
  end generate;

  gen_assign_tuser : if G_USE_TUSER generate
    wr_data(DW + KW + UW - 1 downto DW + KW) <= s_axis.tuser;
    m_axis.tuser                             <= rd_data(DW + KW + UW - 1 downto DW + KW);
  else generate
    m_axis.tuser <= (others=>'0');
  end generate;

  gen_assign_tlast : if G_USE_TLAST generate
    wr_data(DW + KW + UW + LW - 1) <= s_axis.tlast;
    m_axis.tlast                   <= rd_data(DW + KW + UW + LW - 1);
  else generate
    m_axis.tlast <= '1';
  end generate;

  -- FIFO is ready when not full, unless G_DROP_OVERSIZE is set, in which case
  -- it is also also "ready" whenever an oversized packet has been detected.
  -- In the G_DROP_OVERSIZE case, ready stays high but the fifo discards all new
  -- beats it receives until it gets tlast, at which point it rolls back the
  -- write pointer to the address it was at before the start of the oversized
  -- packet, fully discarding the previous beats it received before it knew that
  -- the packet would be oversized. The FIFO must speculatively store beats
  -- and later roll them back because there is no way to know a packet's size
  -- in advance. The packet size isn't known until tlast.
  s_axis.tready <= not full or (to_sl(G_DROP_OVERSIZE) and full_wr);

  -- FIFO is full. Updates with the speculative write pointer.
  full <= to_sl(
      wr_ptr_spec(AW) /= rd_ptr(AW) and
      wr_ptr_spec(AW - 1 downto 0) = rd_ptr(AW - 1 downto 0)
    );

  -- FIFO is empty. Updates with the committed write pointer.
  empty <= to_sl(wr_ptr_comm = rd_ptr);

  -- Input packet is oversized.
  full_wr <= to_sl(
      wr_ptr_spec(AW) /= wr_ptr_comm(AW) and
      wr_ptr_spec(AW - 1 downto 0) = wr_ptr_comm(AW - 1 downto 0)
    );

  prc_status : process (clk) is begin
    if rising_edge(clk) then
      sts_depth_spec <= wr_ptr_spec - rd_ptr;
      sts_depth_comm <= wr_ptr_comm - rd_ptr;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  gen_packet_mode_wr : if G_PACKET_MODE generate

    prc_write : process (clk) is begin
      if rising_edge(clk) then
        sts_dropped <= '0';

        if ctl_drop then
          -- Manual packet drop control.
          drop_reg <= '1';
        end if;

        if s_axis.tvalid and s_axis.tready then
          -- New input beat.

          if (to_sl(G_DROP_OVERSIZE) and full_wr) or ctl_drop or drop_reg then
            -- Discard the rest of the packet.

            if s_axis.tlast then
              -- Roll back the write pointer to the address just before the
              -- start of the discarded packet.
              drop_reg    <= '0';
              sts_dropped <= '1';
              wr_ptr_spec <= wr_ptr_comm;
            else
              drop_reg <= '1';
            end if;

          else
            -- Normal case.

            ram(to_integer(wr_ptr_spec(AW - 1 downto 0))) <= wr_data;
            wr_ptr_spec                                   <= wr_ptr_spec + 1;

            if s_axis.tlast or (not to_sl(G_DROP_OVERSIZE) and (full_wr or send_reg)) then
              -- Commit the write pointer so that the read side sees the new fill
              -- level. Do this upon getting tlast OR detecting an oversized
              -- packet when using the mode where they are not dropped.
              wr_ptr_comm <= wr_ptr_spec + 1;
              send_reg    <= not s_axis.tlast;
            end if;
          end if;
        elsif s_axis.tvalid and full_wr and not to_sl(G_DROP_OVERSIZE) then
          -- Oversized packet detected, but don't drop it.
          -- This happens when a new beat is detected at the input while the
          -- fifo is already full with beats from that same packet. Input ready
          -- is low at this point and the FIFO cannot accept new beats yet.
          -- Commit the write
          -- pointer early to let rest of the packet through, despite not fitting
          -- the whole packet in the FIFO. When this happens, the
          -- output is not guaranteed to always be valid for the duration of the
          -- packet if the input contains holes during the later part of the
          -- packet. BUT, this mode does guarantee that data is never lost.
          wr_ptr_comm <= wr_ptr_spec;
          send_reg    <= '1';
        end if;

        if srst then
          wr_ptr_spec <= (others => '0');
          wr_ptr_comm <= (others => '0');
          send_reg    <= '0';
          drop_reg    <= '0';
        end if;
      end if;
    end process;

  -- ---------------------------------------------------------------------------
  else generate

    prc_write : process (clk) is begin
      if rising_edge(clk) then
        if s_axis.tvalid and s_axis.tready then
          ram(to_integer(wr_ptr_spec(AW - 1 downto 0))) <= wr_data;
          wr_ptr_spec                                   <= wr_ptr_spec + 1;
        end if;

        if srst then
          wr_ptr_spec <= (others => '0');
        end if;
      end if;
    end process;

    wr_ptr_comm <= wr_ptr_spec;
    sts_dropped <= '0';

  end generate;

  -- ---------------------------------------------------------------------------
  prc_read : process (clk) is begin
    if rising_edge(clk) then
      if (m_axis.tready or not m_axis.tvalid) and (not empty) then
        m_axis.tvalid <= '1';
        rd_ptr        <= rd_ptr + 1;
        rd_data       <= ram(to_integer(rd_ptr(AW - 1 downto 0)));
      elsif m_axis.tready then
        m_axis.tvalid <= '0';
      end if;

      if srst then
        m_axis.tvalid <= '0';
        rd_ptr        <= (others => '0');
      end if;
    end if;
  end process;

end architecture;
