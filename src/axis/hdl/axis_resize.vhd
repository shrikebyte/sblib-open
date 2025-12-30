--##############################################################################
--# File : axis_resize.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--# Downsizes or upsizes a stream width.
--#
--# This module has a few tkeep restrictions:
--#   1. Input tkeep bits must be contiguous from low to high. For example:
--#      0000, 0001, 0011, 0111, and 1111 are allowed, but 1010 or 0100 are not
--#      allowed.
--#   2. On a tlast beat, at least one tkeep bit must be set.
--#
--# Downsize mode:
--#   In this mode, one input beat results in multiple output beats.
--#
--# Upsize mode:
--#   In this mode, several input beats result in one output beat.
--#
--# Packed input streams always result in a packed output stream.
--# Unpacked input streams may result in an unpacked output stream.
--# Output tkeep bits will alwyas be contiguous, so long as the input rules are
--# followed.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_resize is
  port (
    clk    : in    std_ulogic;
    srst   : in    std_ulogic;
    --
    s_axis : view s_axis_v;
    --
    m_axis : view m_axis_v;
  );
end entity;

architecture rtl of axis_resize is

  constant S_DW  : integer := s_axis.tdata'length;
  constant S_KW  : integer := s_axis.tkeep'length;
  constant S_UW  : integer := s_axis.tuser'length;
  constant S_DBW : integer := S_DW / S_KW;
  constant S_UBW : integer := S_UW / S_KW;
  constant M_DW  : integer := m_axis.tdata'length;
  constant M_KW  : integer := m_axis.tkeep'length;
  constant M_UW  : integer := m_axis.tuser'length;
  constant M_DBW : integer := M_DW / M_KW;
  constant M_UBW : integer := M_UW / M_KW;
  constant DBW : integer   := S_DBW;
  constant UBW : integer   := S_UBW;

begin

  -- ---------------------------------------------------------------------------
  assert S_DBW = M_DBW
    report "axis_resize: Input and output data byte widths must be " &
      "equal. They are implicitly defined as the ratio of data width to keep " &
      "width."
    severity error;

  assert S_UBW = M_UBW
  report "axis_resize: Input and output user byte widths must be " &
    "equal. They are implicitly defined as the ratio of user width to keep " &
    "width."
    severity error;

  prc_assert : process (clk) begin
    if rising_edge(clk) then
      assert not (s_axis.tvalid = '1' and s_axis.tlast = '1' and
        (nor s_axis.tkeep) = '1')
        report "axis_resize: Null tlast beat detected on input. At " &
          "least one tkeep bit must be set on tlast."
        severity error;

      assert not (s_axis.tvalid = '1' and not is_contig(s_axis.tkeep))
        report "axis_resize: Non-contiguous tkeep detected on input. tkeep " &
          "must be contiguous (e.g., 0001, 0011, 0111, but not 0101 or 0100)."
        severity error;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  -- Passthrough mode
  gen_resize_mode : if S_DW = M_DW generate
  begin

    s_axis.tready <= m_axis.tready;
    m_axis.tvalid <= s_axis.tvalid;
    m_axis.tlast  <= s_axis.tlast;
    m_axis.tdata  <= s_axis.tdata;
    m_axis.tkeep  <= s_axis.tkeep;
    m_axis.tuser  <= s_axis.tuser;


  -- ---------------------------------------------------------------------------
  -- Downsize mode
  elsif S_DW > M_DW generate
    constant RATIO : integer := S_DW / M_DW;
    signal last_reg  : std_ulogic_vector(RATIO - 1 downto 0);
    signal data_reg : std_ulogic_vector(S_DW-1 downto 0);
    signal user_reg : std_ulogic_vector(S_UW-1 downto 0);
    signal keep_reg : std_ulogic_vector(S_KW-1 downto 0);
    signal last_reg_shft : std_ulogic_vector(RATIO - 1 downto 0);
    signal data_reg_shft : std_ulogic_vector(S_DW-1 downto 0);
    signal user_reg_shft : std_ulogic_vector(S_UW-1 downto 0);
    signal keep_reg_shft : std_ulogic_vector(S_KW-1 downto 0);
    signal keep_reg_shft_is_zero : std_logic;
    signal tkeep_contracted : std_ulogic_vector(RATIO - 1 downto 0);

    function find_last_idx (
      vec : std_ulogic_vector
    ) return natural is
      constant VEC_LEN : natural := vec'length;
      variable vec_norm : std_ulogic_vector(VEC_LEN - 1 downto 0);
      variable result  : natural := 0;
    begin
      vec_norm := vec;
      for i in 0 to VEC_LEN - 1 loop
        if vec_norm(i) then
          result := i;
        end if;
      end loop;
      return result;
    end function;

  begin

    -- Input is ready whenever there is room in the output buffer AND the
    -- shift register is empty.
    s_axis.tready <= (m_axis.tready or not m_axis.tvalid) and keep_reg_shft_is_zero;

    data_reg_shft <= std_ulogic_vector(shift_right(u_unsigned(data_reg), M_DW));
    user_reg_shft <= std_ulogic_vector(shift_right(u_unsigned(user_reg), M_UW));
    keep_reg_shft <= std_ulogic_vector(shift_right(u_unsigned(keep_reg), M_KW));
    last_reg_shft <= std_ulogic_vector(shift_right(u_unsigned(last_reg), 1));
    keep_reg_shft_is_zero <= and (not keep_reg_shft);
    tkeep_contracted <= contract_bits(s_axis.tkeep, M_KW);

    prc_downsize : process (clk) begin
      if rising_edge(clk) then

        if s_axis.tvalid and s_axis.tready then
          -- New wide beat at input... send the first narrow output beat.

          m_axis.tvalid <= '1';
          data_reg <= s_axis.tdata;
          user_reg <= s_axis.tuser;
          keep_reg <= s_axis.tkeep;
          last_reg <= (others=>'0');
          last_reg(find_last_idx(tkeep_contracted)) <= s_axis.tlast;

        elsif m_axis.tvalid and m_axis.tready then
          -- Shift out the narrow output data from the rest of the
          -- wide input data until the shift register is empty.

          data_reg <= data_reg_shft;
          user_reg <= user_reg_shft;
          keep_reg <= keep_reg_shft;
          last_reg <= last_reg_shft;

          if keep_reg_shft_is_zero then
            m_axis.tvalid <= '0';
          end if;

        end if;

        if srst then
          m_axis.tvalid <= '0';
          keep_reg <= (others => '0');
        end if;
      end if;
    end process;

    m_axis.tdata <= data_reg(m_axis.tdata'range);
    m_axis.tuser <= user_reg(m_axis.tuser'range);
    m_axis.tkeep <= keep_reg(m_axis.tkeep'range);
    m_axis.tlast <= last_reg(0);


  -- ---------------------------------------------------------------------------
  -- Upsize mode
  else generate
    constant CNT_MAX : natural := M_KW - S_KW;
    signal offset : natural range 0 to M_KW - 1;
    signal offset_plus_current_cnt : natural range 0 to M_KW;
  begin

    assert is_pwr2(DBW)
      report "axis_resize (upsize): Data byte width must be a power of 2."
      severity error;

    assert is_pwr2(UBW)
      report "axis_resize (upsize): User byte width must be a power of 2."
      severity error;

    s_axis.tready <= m_axis.tready or not m_axis.tvalid;
    offset_plus_current_cnt <= offset + cnt_ones_contig(s_axis.tkeep);

    prc_upsize : process (clk) begin
      if rising_edge(clk) then
        if s_axis.tvalid and s_axis.tready then
          -- New narrow input beat

          if offset = 0 then
            -- First narrow input beat of wide output beat
            m_axis.tkeep <= (others=>'0');
          end if;

          m_axis.tkeep(offset + S_KW - 1 downto offset) <= s_axis.tkeep;
          m_axis.tdata((offset * DBW) + S_DW - 1 downto (offset * DBW)) <= s_axis.tdata;
          m_axis.tuser((offset * UBW) + S_UW - 1 downto (offset * UBW)) <= s_axis.tuser;
          m_axis.tlast <= s_axis.tlast;

          if offset_plus_current_cnt > CNT_MAX or s_axis.tlast = '1' then
            m_axis.tvalid <= '1';
            offset <= 0;
          else
            m_axis.tvalid <= '0';
            offset <= offset_plus_current_cnt;
          end if;

        elsif m_axis.tready then
          m_axis.tvalid <= '0';
        end if;

        if srst then
          m_axis.tvalid <= '0';
          offset <= 0;
        end if;
      end if;
    end process;

  end generate;

end architecture;
