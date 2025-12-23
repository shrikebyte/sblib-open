--##############################################################################
--# File : axis_pack.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--!
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_pack is
  port (
    clk    : in    std_ulogic;
    srst   : in    std_ulogic;
    --
    s_axis : view s_axis_v;
    --
    m_axis : view m_axis_v
  );
end entity;

architecture rtl of axis_pack is

  constant DW : integer := m_axis.tdata'length;
  constant KW : integer := m_axis.tkeep'length;
  constant UW : integer := m_axis.tuser'length;
  constant DBW : integer := DW / KW;
  constant UBW : integer := UW / KW;

  constant KW_ZEROS : std_ulogic_vector(KW-1 downto 0) := (others=>'0');

  -- Not synthesized. Only for assertion check.
  function is_contiguous(vec : std_ulogic_vector) return boolean is
    variable saw_zero : boolean := false;
  begin
    for i in vec'low to vec'high loop
      if vec(i) = '0' then
        saw_zero := true;
      elsif saw_zero then
        -- Found a '1' after seeing a '0' - not contiguous!
        return false;
      end if;
    end loop;
    return true;
  end function;

  type state_t is (ST_PACK, ST_LAST);
  signal state_nxt : state_t;
  signal state_reg : state_t;

  signal pipe0_axis : axis_t (
    tkeep(KW - 1 downto 0),
    tdata(DW - 1 downto 0),
    tuser(UW - 1 downto 0)
  );

  signal pipe1_axis_nxt : axis_t (
    tkeep(KW * 2 - 1 downto 0),
    tdata(DW * 2 - 1 downto 0),
    tuser(UW * 2 - 1 downto 0)
  );

  signal pipe1_axis_reg : axis_t (
    tkeep(KW * 2 - 1 downto 0),
    tdata(DW * 2 - 1 downto 0),
    tuser(UW * 2 - 1 downto 0)
  );

  signal pipe0_axis_cnt : integer range 0 to KW;
  signal offset_nxt : integer range 0 to KW - 1;
  signal offset_reg : integer range 0 to KW - 1;

begin

  -- ---------------------------------------------------------------------------
  assert DW mod KW = 0
    report "axis_pack: Data width must be evenly divisible by keep width."
    severity error;

  assert UW mod KW = 0
    report "axis_pack: User width must be evenly divisible by keep width."
    severity error;

  assert is_pwr2(KW)
    report "axis_pack: Keep width must be a power of 2."
    severity error;

  prc_assert : process (clk) begin
    if rising_edge(clk) then
      assert not (s_axis.tvalid = '1' and s_axis.tlast = '1' and (nor s_axis.tkeep))
        report "axis_pack: Null tlast beat detected on input. At " &
          "least one tkeep bit must be set on tlast."
        severity error;

      assert not (s_axis.tvalid = '1' and not is_contiguous(s_axis.tkeep))
        report "Non-contiguous tkeep detected on input. tkeep must be " &
        "contiguous (e.g., 0001, 0011, 0111, but not 0101 or 0100)."
        severity error;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  s_axis.tready <= pipe0_axis.tready or not pipe0_axis.tvalid;
  pipe0_axis.tready <= (pipe1_axis_reg.tready or not pipe1_axis_reg.tvalid) and
                       (state_reg = ST_PACK);

  -- ---------------------------------------------------------------------------
  -- Pre-calculate pipe0_axis_cnt for better timing
  prc_pipe0 : process (clk) begin
    if rising_edge(clk) then
      if s_axis.tvalid and s_axis.tready then
        pipe0_axis.tvalid   <= '1';
        pipe0_axis.tlast    <= s_axis.tlast;
        pipe0_axis.tdata    <= s_axis.tdata;
        pipe0_axis.tkeep    <= s_axis.tkeep;
        pipe0_axis.tuser    <= s_axis.tuser;
        --
        pipe0_axis_cnt   <= cnt_ones_contig(s_axis.tkeep);
      elsif pipe0_axis.tready then
        pipe0_axis.tvalid <= '0';
      end if;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  prc_fsm_comb : process (all) begin
    pipe1_axis_nxt.tvalid <= pipe1_axis_reg.tvalid;
    pipe1_axis_nxt.tlast  <= pipe1_axis_reg.tlast ;
    pipe1_axis_nxt.tkeep(pipe1_axis_nxt.tkeep'range)  <= pipe1_axis_reg.tkeep(pipe1_axis_nxt.tkeep'range) ;
    pipe1_axis_nxt.tdata(pipe1_axis_nxt.tdata'range)  <= pipe1_axis_reg.tdata(pipe1_axis_nxt.tdata'range) ;
    pipe1_axis_nxt.tuser(pipe1_axis_nxt.tuser'range)  <= pipe1_axis_reg.tuser(pipe1_axis_nxt.tuser'range) ;
    --
    offset_nxt <= offset_reg;
    state_nxt <= state_reg;

    case state_reg is

      -- -----------------------------------------------------------------------
      when ST_PACK =>
        if pipe0_axis.tvalid and pipe0_axis.tready then

          if pipe0_axis.tlast then
            offset_nxt <= 0;
            if pipe1_axis_nxt.tkeep(KW) then
              pipe1_axis_nxt.tlast <= '0';
              state_nxt <= ST_LAST;
            else
              pipe1_axis_nxt.tlast <= '1';
            end if;
          else
            offset_nxt <= (offset_reg + pipe0_axis_cnt) mod KW;
            pipe1_axis_nxt.tlast <= '0';
          end if;

          if pipe1_axis_nxt.tkeep(KW-1) or pipe0_axis.tlast then
            pipe1_axis_nxt.tvalid <= '1';
          else
            pipe1_axis_nxt.tvalid <= '0';
          end if;

          if pipe1_axis_reg.tkeep(KW-1) or pipe1_axis_reg.tlast then
            -- Shift in AND shift out
            pipe1_axis_nxt.tkeep <= KW_ZEROS & pipe1_axis_reg.tkeep(KW * 2 - 1 downto KW);
            pipe1_axis_nxt.tkeep(offset_reg + KW - 1 downto offset_reg) <= pipe0_axis.tkeep;
            --
            pipe1_axis_nxt.tdata(DW - 1 downto 0) <= pipe1_axis_reg.tdata(DW * 2 - 1 downto DW);
            pipe1_axis_nxt.tdata((offset_reg * DBW) + DW - 1 downto (offset_reg * DBW)) <= pipe0_axis.tdata;
            --
            pipe1_axis_nxt.tuser(UW - 1 downto 0) <= pipe1_axis_reg.tuser(UW * 2 - 1 downto UW);
            pipe1_axis_nxt.tuser((offset_reg * UBW) + UW - 1 downto (offset_reg * UBW)) <= pipe0_axis.tuser;
          else
            -- Accumulate
            pipe1_axis_nxt.tkeep(offset_reg + KW - 1 downto offset_reg) <= pipe0_axis.tkeep;
            --
            pipe1_axis_nxt.tdata((offset_reg * DBW) + DW - 1 downto (offset_reg * DBW)) <= pipe0_axis.tdata;
            --
            pipe1_axis_nxt.tuser((offset_reg * UBW) + UW - 1 downto (offset_reg * UBW)) <= pipe0_axis.tuser;
          end if;
        elsif pipe1_axis_reg.tready then
          pipe1_axis_nxt.tvalid <= '0';
        end if;

      -- -----------------------------------------------------------------------
      when ST_LAST =>
        if pipe1_axis_reg.tready then
          -- We already know that pipe1_axis_reg.tvalid is high here because it
          -- was set by the prev state.
          pipe1_axis_nxt.tvalid <= '1';
          pipe1_axis_nxt.tlast <= '1';
          --
          -- Shift out
          pipe1_axis_nxt.tkeep <= KW_ZEROS & pipe1_axis_reg.tkeep(KW * 2 - 1 downto KW);
          pipe1_axis_nxt.tdata(DW - 1 downto 0) <= pipe1_axis_reg.tdata(DW * 2 - 1 downto DW);
          pipe1_axis_nxt.tuser(UW - 1 downto 0) <= pipe1_axis_reg.tuser(UW * 2 - 1 downto UW);
          --
          state_nxt <= ST_PACK;
        end if;

    end case;

  end process;

  -- ---------------------------------------------------------------------------
  prc_fsm_ff : process (clk) begin
    if rising_edge(clk) then
      pipe1_axis_reg.tvalid <= pipe1_axis_nxt.tvalid;
      pipe1_axis_reg.tlast  <= pipe1_axis_nxt.tlast ;
      pipe1_axis_reg.tkeep  <= pipe1_axis_nxt.tkeep ;
      pipe1_axis_reg.tdata  <= pipe1_axis_nxt.tdata ;
      pipe1_axis_reg.tuser  <= pipe1_axis_nxt.tuser ;
      --
      offset_reg <= offset_nxt;
      state_reg  <= state_nxt;

      if srst then
        pipe1_axis_reg.tvalid <= '0';
        pipe1_axis_reg.tkeep  <= (others=>'0');
        --
        offset_reg <= 0;
        state_reg  <= ST_PACK;
      end if;
    end if;
  end process;


  -- ---------------------------------------------------------------------------
  pipe1_axis_reg.tready <= m_axis.tready;

  m_axis.tvalid <= pipe1_axis_reg.tvalid;
  m_axis.tlast  <= pipe1_axis_reg.tlast;
  m_axis.tkeep  <= pipe1_axis_reg.tkeep(KW - 1 downto 0);
  m_axis.tdata  <= pipe1_axis_reg.tdata(DW - 1 downto 0);
  m_axis.tuser  <= pipe1_axis_reg.tuser(UW - 1 downto 0);

end architecture;
