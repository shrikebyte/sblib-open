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

  type state_t is (ST_IDLE, ST_PACK, ST_LAST);
  signal state : state_t;

  -- Output enable
  signal oe : std_ulogic;

  -- Residual tdata and tkeep. Stores leftover bytes that need to be
  -- sent after the current packed beat has been sent.
  signal resid_tkeep_reg : std_ulogic_vector(m_axis.tkeep'range);
  signal resid_tdata_reg : std_ulogic_vector(m_axis.tdata'range);
  signal resid_tuser_reg : std_ulogic_vector(m_axis.tuser'range);


  -- Represents packed data type, comprising of 2 back-to-back beats with
  -- some tkeep bits unset in one or both beats.
  type pack_t is record
    packed_tkeep : std_ulogic_vector(KW-1 downto 0);
    packed_tdata : std_ulogic_vector(DW-1 downto 0);
    packed_tuser : std_ulogic_vector(UW-1 downto 0);
    resid_tkeep  : std_ulogic_vector(KW-1 downto 0);
    resid_tdata  : std_ulogic_vector(DW-1 downto 0);
    resid_tuser  : std_ulogic_vector(UW-1 downto 0);
  end record;

  signal pack : pack_t;

  -- ---------------------------------------------------------------------------
  impure function calc_pack (
    lo_count : integer range 0 to KW;
    lo_tdata : std_ulogic_vector(DW-1 downto 0);
    lo_tuser : std_ulogic_vector(UW-1 downto 0);
    hi_count : integer range 0 to KW;
    hi_tdata : std_ulogic_vector(DW-1 downto 0);
    hi_tuser : std_ulogic_vector(UW-1 downto 0);
  ) return pack_t
  is
    variable tkeep : std_ulogic_vector(KW * 2 - 1 downto 0) := (others => '0');
    variable tdata : std_ulogic_vector(DW * 2 - 1 downto 0) := (others => '-');
    variable tuser : std_ulogic_vector(UW * 2 - 1 downto 0) := (others => '-');
    variable combined_count : integer range 0 to KW * 2 := lo_count + hi_count;
    variable result : pack_t;
  begin

    tdata(lo_count * DBW - 1 downto 0) := lo_tdata(lo_count * DBW - 1 downto 0);
    tuser(lo_count * UBW - 1 downto 0) := lo_tuser(lo_count * UBW - 1 downto 0);

    tdata(combined_count * DBW - 1 downto lo_count * DBW) := hi_tdata(hi_count * DBW - 1 downto 0);
    tuser(combined_count * UBW - 1 downto lo_count * UBW) := hi_tuser(hi_count * UBW - 1 downto 0);

    tkeep(combined_count - 1 downto 0) := (others=>'1');

    result.packed_tkeep := tkeep(KW - 1 downto 0);
    result.packed_tdata := tdata(DW - 1 downto 0);
    result.packed_tuser := tuser(UW - 1 downto 0);
    result.resid_tkeep  := tkeep(KW * 2 - 1 downto KW);
    result.resid_tdata  := tdata(DW * 2 - 1 downto DW);
    result.resid_tuser  := tuser(UW * 2 - 1 downto UW);

    return result;
  end function;

  signal packed_all_are_valid : std_ulogic;
  signal packed_at_least_one_is_valid : std_ulogic;
  signal resid_at_least_one_is_valid : std_ulogic;


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

  signal resid_count : integer range 0 to KW;
  signal input_count : integer range 0 to KW;

begin

  -- ---------------------------------------------------------------------------
  assert DW mod KW = 0
    report "axis_pack: Data width must be evenly divisible by keep width."
    severity error;

  assert UW mod KW = 0
    report "axis_pack: User width must be evenly divisible by keep width."
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
  resid_count <= cnt_ones(resid_tkeep_reg);
  input_count <= cnt_ones(s_axis.tkeep);
  oe <= m_axis.tready or not m_axis.tvalid;
  s_axis.tready <= oe and (state = ST_PACK);
  packed_all_are_valid <= and pack.packed_tkeep;
  packed_at_least_one_is_valid <= or pack.packed_tkeep;
  resid_at_least_one_is_valid <= or pack.resid_tkeep;

  pack <= calc_pack (
    lo_count => resid_count,
    lo_tdata => resid_tdata_reg,
    lo_tuser => resid_tuser_reg,
    hi_count => input_count,
    hi_tdata => s_axis.tdata,
    hi_tuser => s_axis.tuser
  );


  -- ---------------------------------------------------------------------------
  prc_fsm : process (clk) begin
    if rising_edge(clk) then

      -- By default, clear m_valid if m_ready. The FSM might override this
      --  if it has new data to send.
      if m_axis.tready then
        m_axis.tvalid <= '0';
      end if;

      case state is

        -- ---------------------------------------------------------------------
        when ST_PACK =>
          if s_axis.tvalid and s_axis.tready then
            -- If new input beat

            m_axis.tkeep <= pack.packed_tkeep;
            m_axis.tdata <= pack.packed_tdata;
            m_axis.tuser <= pack.packed_tuser;

            if packed_all_are_valid then
              -- If a new packed beat is ready, then shift out the packed data
              -- to be transmitted on the next cycle and shift in the residual
              -- data to be transmitted the next time we have a new full output
              -- beat.
              resid_tkeep_reg  <= pack.resid_tkeep;
              resid_tdata_reg  <= pack.resid_tdata;
              resid_tuser_reg  <= pack.resid_tuser;
            else
              -- Otherwise, store the partially-packed output data in the
              -- residual buffer.
              resid_tkeep_reg  <= pack.packed_tkeep;
              resid_tdata_reg  <= pack.packed_tdata;
              resid_tuser_reg  <= pack.packed_tuser;
            end if;

            if s_axis.tlast then

              m_axis.tvalid <= '1';

              if resid_at_least_one_is_valid then
                -- If there are ANY residual bytes, we need to transmit
                -- one additional beat to finish the packet.
                m_axis.tlast <= '0';
                state        <= ST_LAST;
              else
                -- Otherwise, if there are no residual bytes left at this point,
                -- we're done.
                m_axis.tlast <= '1';
                resid_tkeep_reg  <= (others => '0');
              end if;

            else

              -- If normal input beat and ALL of the packed output beats are
              -- valid, then output is valid.
              m_axis.tvalid <= packed_all_are_valid;
              m_axis.tlast  <= '0';
            end if;

          end if;

        -- ---------------------------------------------------------------------
        when ST_LAST =>
          if oe then
            -- If output is ready
            m_axis.tvalid <= '1';
            m_axis.tdata  <= resid_tdata_reg;
            m_axis.tuser  <= resid_tuser_reg;
            m_axis.tkeep  <= resid_tkeep_reg;
            m_axis.tlast  <= '1';
            resid_tkeep_reg     <= (others => '0');
            state           <= ST_PACK;
          end if;

        when others =>
          null;
      end case;

      if srst then
        m_axis.tvalid  <= '0';
        resid_tkeep_reg      <= (others => '0');
        state            <= ST_PACK;
      end if;
    end if;
  end process;

end architecture;
