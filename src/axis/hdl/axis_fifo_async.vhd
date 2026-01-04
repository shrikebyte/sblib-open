--##############################################################################
--# File : axis_fifo_async.vhd
--# Auth : David Gussler
--# Lang : VHDL '19
--# ============================================================================
--# Asynchronous AXI Stream FIFO.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_fifo_async is
  generic (
    G_SYNC_LEN      : positive := 2;
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
    -- Async reset
    arst : in std_logic;
    -- Input interface
    s_clk  : in std_logic;
    s_axis : view s_axis_v;
    s_ctl_drop : in std_ulogic;
    s_sts_dropped : out   std_ulogic;
    s_sts_depth_spec : out   u_unsigned(clog2(G_DEPTH) downto 0);
    s_sts_depth_comm : out   u_unsigned(clog2(G_DEPTH) downto 0);
    -- Output interface
    m_clk  : in std_logic;
    m_axis : view m_axis_v;
    m_sts_depth_spec : out   u_unsigned(clog2(G_DEPTH) downto 0);
    m_sts_depth_comm : out   u_unsigned(clog2(G_DEPTH) downto 0)
  );
end entity;

architecture rtl of axis_fifo_async is

  constant DW : integer := m_axis.tdata'length;
  constant KW : integer := if_then_else(G_USE_TKEEP, m_axis.tkeep'length, 0);
  constant UW : integer := if_then_else(G_USE_TUSER, m_axis.tuser'length, 0);
  constant LW : integer := if_then_else(G_USE_TLAST, 1, 0);
  constant RW : integer := DW + UW + KW + LW; -- Ram width
  constant AW : integer := clog2(G_DEPTH); -- Address width

  signal ram     : slv_arr_t(0 to G_DEPTH - 1)(RW - 1 downto 0);
  signal s_wr_data : std_ulogic_vector(RW - 1 downto 0);
  signal m_rd_data : std_ulogic_vector(RW - 1 downto 0);

  signal s_wr_ptr_spec : u_unsigned(AW downto 0);
  signal s_wr_ptr_comm : u_unsigned(AW downto 0);
  signal m_rd_ptr      : u_unsigned(AW downto 0);
  signal m_empty       : std_ulogic;
  signal s_full        : std_ulogic;
  signal s_full_wr     : std_ulogic;
  signal s_drop_reg    : std_ulogic;
  signal s_send_reg    : std_ulogic;

  signal s_srst_cdc    : std_ulogic;
  signal m_srst_cdc    : std_ulogic;

  signal s_rd_ptr_cdc  : u_unsigned(AW downto 0);
  signal m_wr_ptr_comm_cdc : u_unsigned(AW downto 0);
  signal m_wr_ptr_spec_cdc : u_unsigned(AW downto 0);

begin

  -- ---------------------------------------------------------------------------
  -- Assertions
  -- ---------------------------------------------------------------------------
  assert is_pwr2(G_DEPTH)
    report "axis_fifo_async: Depth must be a power of 2."
    severity error;

  assert not (G_USE_TLAST = false and G_PACKET_MODE = true)
    report "axis_fifo_async: G_PACKET_MODE requires G_USE_TLAST to be enabled."
    severity failure;

  assert not (G_PACKET_MODE = false and G_DROP_OVERSIZE = true)
    report "axis_fifo_async: G_DROP_OVERSIZE requires G_PACKET_MODE to be enabled."
    severity failure;

  -- ---------------------------------------------------------------------------
  -- Control & Status
  -- ---------------------------------------------------------------------------
  s_wr_data(DW - 1 downto 0) <= s_axis.tdata;
  m_axis.tdata             <= m_rd_data(DW - 1 downto 0);

  gen_assign_tkeep : if G_USE_TKEEP generate
    s_wr_data(DW + KW - 1 downto DW) <= s_axis.tkeep;
    m_axis.tkeep                   <= m_rd_data(DW + KW - 1 downto DW);
  else generate
    m_axis.tkeep <= (others=>'1');
  end generate;

  gen_assign_tuser : if G_USE_TUSER generate
    s_wr_data(DW + KW + UW - 1 downto DW + KW) <= s_axis.tuser;
    m_axis.tuser                             <= m_rd_data(DW + KW + UW - 1 downto DW + KW);
  else generate
    m_axis.tuser <= (others=>'0');
  end generate;

  gen_assign_tlast : if G_USE_TLAST generate
    s_wr_data(DW + KW + UW + LW - 1) <= s_axis.tlast;
    m_axis.tlast                   <= m_rd_data(DW + KW + UW + LW - 1);
  else generate
    m_axis.tlast <= '1';
  end generate;

  s_axis.tready <= not s_full or (to_sl(G_DROP_OVERSIZE) and s_full_wr);

  s_full <= to_sl(
      s_wr_ptr_spec(AW) /= s_rd_ptr_cdc(AW) and
      s_wr_ptr_spec(AW - 1 downto 0) = s_rd_ptr_cdc(AW - 1 downto 0)
    );

  m_empty <= to_sl(m_wr_ptr_comm_cdc = m_rd_ptr);

  s_full_wr <= to_sl(
      s_wr_ptr_spec(AW) /= s_wr_ptr_comm(AW) and
      s_wr_ptr_spec(AW - 1 downto 0) = s_wr_ptr_comm(AW - 1 downto 0)
    );

  prc_status_s : process (s_clk) is begin
    if rising_edge(s_clk) then
      s_sts_depth_spec <= s_wr_ptr_spec - s_rd_ptr_cdc;
      s_sts_depth_comm <= s_wr_ptr_comm - s_rd_ptr_cdc;
    end if;
  end process;

  prc_status_m : process (s_clk) is begin
    if rising_edge(s_clk) then
      m_sts_depth_spec <= m_wr_ptr_spec_cdc - m_rd_ptr;
      m_sts_depth_comm <= m_wr_ptr_comm_cdc - m_rd_ptr;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  -- CDC
  -- ---------------------------------------------------------------------------
  u_cdc_reset_s : entity work.cdc_reset
  generic map (
    G_SYNC_LEN => G_SYNC_LEN,
    G_NUM_ARST => 1,
    G_ARST_LVL => "1"
  )
  port map (
    arst(0) => arst,
    clk     => s_clk,
    srst    => s_srst_cdc
  );

  u_cdc_reset_m : entity work.cdc_reset
  generic map (
    G_SYNC_LEN => G_SYNC_LEN,
    G_NUM_ARST => 1,
    G_ARST_LVL => "1"
  )
  port map (
    arst(0) => arst,
    clk     => m_clk,
    srst    => m_srst_cdc
  );

  u_cdc_gray_wr_ptr_spec : entity work.cdc_gray
  generic map (
    G_SYNC_LEN => G_SYNC_LEN,
    G_OUT_REG  => false
  )
  port map (
    src_clk => s_clk,
    src_cnt => s_wr_ptr_spec,
    dst_clk => m_clk,
    dst_cnt => m_wr_ptr_spec_cdc
  );

  u_cdc_gray_wr_ptr_comm : entity work.cdc_gray
  generic map (
    G_SYNC_LEN => G_SYNC_LEN,
    G_OUT_REG  => false
  )
  port map (
    src_clk => s_clk,
    src_cnt => s_wr_ptr_comm,
    dst_clk => m_clk,
    dst_cnt => m_wr_ptr_comm_cdc
  );

  u_cdc_gray_rd_ptr : entity work.cdc_gray
  generic map (
    G_SYNC_LEN => G_SYNC_LEN,
    G_OUT_REG  => false
  )
  port map (
    src_clk => m_clk,
    src_cnt => m_rd_ptr,
    dst_clk => s_clk,
    dst_cnt => s_rd_ptr_cdc
  );

  -- ---------------------------------------------------------------------------
  gen_packet_mode_wr : if G_PACKET_MODE generate

    prc_write : process (s_clk) is begin
      if rising_edge(s_clk) then
        s_sts_dropped <= '0';

        if s_ctl_drop then
          s_drop_reg <= '1';
        end if;

        if s_axis.tvalid and s_axis.tready then

          if (to_sl(G_DROP_OVERSIZE) and s_full_wr) or s_ctl_drop or s_drop_reg then

            if s_axis.tlast then
              s_drop_reg    <= '0';
              s_sts_dropped <= '1';
              s_wr_ptr_spec <= s_wr_ptr_comm;
            else
              s_drop_reg <= '1';
            end if;

          else

            ram(to_integer(s_wr_ptr_spec(AW - 1 downto 0))) <= s_wr_data;
            s_wr_ptr_spec                                   <= s_wr_ptr_spec + 1;

            if s_axis.tlast or (not to_sl(G_DROP_OVERSIZE) and (s_full_wr or s_send_reg)) then
              s_wr_ptr_comm <= s_wr_ptr_spec + 1;
              s_send_reg    <= not s_axis.tlast;
            end if;
          end if;
        elsif s_axis.tvalid and s_full_wr and not to_sl(G_DROP_OVERSIZE) then
          s_wr_ptr_comm <= s_wr_ptr_spec;
          s_send_reg    <= '1';
        end if;

        if s_srst_cdc then
          s_wr_ptr_spec <= (others => '0');
          s_wr_ptr_comm <= (others => '0');
          s_send_reg    <= '0';
          s_drop_reg    <= '0';
        end if;
      end if;
    end process;

  -- ---------------------------------------------------------------------------
  else generate

    prc_write : process (s_clk) is begin
      if rising_edge(s_clk) then
        if s_axis.tvalid and s_axis.tready then
          ram(to_integer(s_wr_ptr_spec(AW - 1 downto 0))) <= s_wr_data;
          s_wr_ptr_spec                                   <= s_wr_ptr_spec + 1;
        end if;

        if s_srst_cdc then
          s_wr_ptr_spec <= (others => '0');
        end if;
      end if;
    end process;

    s_wr_ptr_comm <= s_wr_ptr_spec;
    s_sts_dropped <= '0';

  end generate;

  -- ---------------------------------------------------------------------------
  prc_read : process (m_clk) is begin
    if rising_edge(m_clk) then
      if (m_axis.tready or not m_axis.tvalid) and (not m_empty) then
        m_axis.tvalid <= '1';
        m_rd_ptr        <= m_rd_ptr + 1;
        m_rd_data       <= ram(to_integer(m_rd_ptr(AW - 1 downto 0)));
      elsif m_axis.tready then
        m_axis.tvalid <= '0';
      end if;

      if s_srst_cdc then
        m_axis.tvalid <= '0';
        m_rd_ptr        <= (others => '0');
      end if;
    end if;
  end process;

end architecture;
