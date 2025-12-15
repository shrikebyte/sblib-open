--##############################################################################
--# File : axis_pack.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! Pack a sparse stream into a packed stream. Removes null bytes. Can accept
--! any sparse input stream, including beats where all bytes are null.
--! If tuser is used, it must be byte oriented, meaning tuser width must be
--! an integer multiple of tkeep width. Tuser bits will be dropped along with
--! the corresponding data if tkeep is nulled.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_pack is
  generic (
    --! If true, this module will support a fully nulled-out tlast input
    --! transfer. This adds one additional cycle of latency, along with a larger
    --! area footprint. If the user can guarantee that tlast transfers will
    --! always contain at least one valid byte, then set this to false to
    --! save area and latency.
    G_SUPPORT_NULL_TLAST : boolean := false
  );
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
  signal resid_tkeep : std_ulogic_vector(m_axis.tkeep'range);
  signal resid_tdata : std_ulogic_vector(m_axis.tdata'range);
  signal resid_tuser : std_ulogic_vector(m_axis.tuser'range);

  signal int_axis : axis_t (
    tdata(m_axis.tdata'range),
    tkeep(m_axis.tkeep'range),
    tuser(m_axis.tuser'range)
  );

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

  constant PACK_DEFAULT : pack_t := (
    packed_tkeep => (others => '0'),
    packed_tdata => (others => '-'),
    packed_tuser => (others => '-'),
    resid_tkeep  => (others => '0'),
    resid_tdata  => (others => '-'),
    resid_tuser  => (others => '-')
  );

  signal pack : pack_t;

  -- ---------------------------------------------------------------------------
  -- Pack 2 sparse beats into one packed beat and one residual beat.
  -- This is essentially a fancy barrel-shifter.
  impure function calc_pack (
    lo_tkeep : std_ulogic_vector(KW-1 downto 0);
    lo_tdata : std_ulogic_vector(DW-1 downto 0);
    lo_tuser : std_ulogic_vector(UW-1 downto 0);
    hi_tkeep : std_ulogic_vector(KW-1 downto 0);
    hi_tdata : std_ulogic_vector(DW-1 downto 0);
    hi_tuser : std_ulogic_vector(UW-1 downto 0);
  ) return pack_t
  is
    variable j : integer range 0 to KW := 0;
    variable k : integer range 0 to KW := 0;
    variable result : pack_t := PACK_DEFAULT;
  begin
    for i in 0 to KW - 1 loop
      if lo_tkeep(i) = '1' then
        -- Pack byte from lower input to packed output
        result.packed_tkeep(j) := '1';
        result.packed_tdata(j * DBW + DBW - 1 downto j * DBW) := 
            lo_tdata(i * DBW + DBW - 1 downto i * DBW);
        result.packed_tuser(j * UBW + UBW - 1 downto j * UBW) := 
            lo_tuser(i * UBW + UBW - 1 downto i * UBW);
        j := j + 1;
      end if;
    end loop;

    for i in 0 to KW - 1 loop
      if hi_tkeep(i) = '1' then
        if j < KW then
          -- Pack byte from upper input to packed output
          result.packed_tkeep(j) := '1';
          result.packed_tdata(j * DBW + DBW - 1 downto j * DBW) := 
              hi_tdata(i * DBW + DBW - 1 downto i * DBW);
          result.packed_tuser(j * UBW + UBW - 1 downto j * UBW) := 
              hi_tuser(i * UBW + UBW - 1 downto i * UBW);
          j := j + 1;
        else 
          -- Pack byte from upper input to residual output
          result.resid_tkeep(k) := '1';
          result.resid_tdata(k * DBW + DBW - 1 downto k * DBW) := 
              hi_tdata(i * DBW + DBW - 1 downto i * DBW);
          result.resid_tuser(k * UBW + UBW - 1 downto k * UBW) := 
              hi_tuser(i * UBW + UBW - 1 downto i * UBW);
          k := k + 1;
        end if;
      end if;
    end loop;

    return result;
  end function;

  signal packed_all_are_valid : std_ulogic;
  signal packed_at_least_one_is_valid : std_ulogic;
  signal resid_at_least_one_is_valid : std_ulogic;

begin

  -- ---------------------------------------------------------------------------
  oe <= int_axis.tready or not int_axis.tvalid;
  s_axis.tready <= oe and (state = ST_PACK);
  packed_all_are_valid <= and pack.packed_tkeep;
  packed_at_least_one_is_valid <= or pack.packed_tkeep;
  resid_at_least_one_is_valid <= or pack.resid_tkeep;

  pack <= calc_pack(
    lo_tkeep => resid_tkeep, 
    lo_tdata => resid_tdata, 
    lo_tuser => resid_tuser, 
    hi_tkeep => s_axis.tkeep, 
    hi_tdata => s_axis.tdata, 
    hi_tuser => s_axis.tuser
  );

  -- ---------------------------------------------------------------------------
  prc_fsm : process (clk) begin
    if rising_edge(clk) then

      -- By default, clear m_valid if m_ready. The FSM might override this
      --  if it has new data to send.
      if int_axis.tready then
        int_axis.tvalid <= '0';
      end if;

      case state is

        -- ---------------------------------------------------------------------
        when ST_PACK =>
          if s_axis.tvalid and s_axis.tready then
            -- If new input beat

            int_axis.tkeep <= pack.packed_tkeep;
            int_axis.tdata <= pack.packed_tdata;
            int_axis.tuser <= pack.packed_tuser;

            if packed_all_are_valid then
              -- If a new packed beat is ready, then shift out the packed data
              -- to be transmitted on the next cycle and shift in the residual
              -- data to be transmitted the next time we have a new full output
              -- beat.
              resid_tkeep  <= pack.resid_tkeep;
              resid_tdata  <= pack.resid_tdata;
              resid_tuser  <= pack.resid_tuser;
            else
              -- Otherwise, store the partially-packed output data in the
              -- residual buffer.
              resid_tkeep  <= pack.packed_tkeep;
              resid_tdata  <= pack.packed_tdata;
              resid_tuser  <= pack.packed_tuser;
            end if;

            if s_axis.tlast then

              if G_SUPPORT_NULL_TLAST then
                -- If last input beat and ANY of the packed output beats are
                -- valid, then output is valid.
                int_axis.tvalid <= packed_at_least_one_is_valid;
              else
                -- In this mode, the user guarantees the input stream will never
                -- have a null tlast beat, so we can save a bit of logic here.
                int_axis.tvalid <= '1';
              end if;

              if resid_at_least_one_is_valid then
                -- If there are ANY residual bytes, we need to transmit
                -- one additional beat to finish the packet.
                int_axis.tlast <= '0';
                state          <= ST_LAST;
              else
                -- Otherwise, if there are no residual bytes left at this point,
                -- we're done.
                int_axis.tlast <= '1';
                resid_tkeep    <= (others => '0');
              end if;

            else

              -- If normal input beat and ALL of the packed output beats are
              -- valid, then output is valid.
              int_axis.tvalid <= packed_all_are_valid;
              int_axis.tlast  <= '0';
            end if;

          end if;

        -- ---------------------------------------------------------------------
        when ST_LAST =>
          if oe then
            -- If output is ready
            int_axis.tvalid <= '1';
            int_axis.tdata  <= resid_tdata;
            int_axis.tuser  <= resid_tuser;
            int_axis.tkeep  <= resid_tkeep;
            int_axis.tlast  <= '1';
            resid_tkeep     <= (others => '0');
            state           <= ST_PACK;
          end if;

        when others =>
          null;
      end case;

      if srst then
        int_axis.tvalid  <= '0';
        resid_tkeep      <= (others => '0');
        state            <= ST_PACK;
      end if;
    end if;
  end process;


  -- ---------------------------------------------------------------------------
  gen_output_reg : if G_SUPPORT_NULL_TLAST generate

    int_axis.tready <= m_axis.tready or not m_axis.tvalid;

    prc_output_reg : process (clk) begin
      if rising_edge(clk) then
        if int_axis.tvalid and int_axis.tready then
          m_axis.tvalid   <= '1'; 
          m_axis.tdata    <= int_axis.tdata; 
          m_axis.tkeep    <= int_axis.tkeep; 
          m_axis.tuser    <= int_axis.tuser;

          -- If next output beat is packed / valid but current input beat is
          -- a null tlast beat, then the FSM will invalidate the null
          -- tlast beat's data. It is expected behavior to drop the null data,
          -- but we cannot drop the tlast indicator. To solve this, tlast needs
          -- to be "pulled forward" to the next output beat.
          -- This extra output register is required to support null tlast beats
          -- because we need to be able to look ahead in time by one
          -- transaction.
          if s_axis.tvalid and s_axis.tready and s_axis.tlast and 
             (nor s_axis.tkeep)
          then
            m_axis.tlast <= '1';
          else 
            m_axis.tlast <= int_axis.tlast; 
          end if;
        
        elsif m_axis.tready then
          m_axis.tvalid   <= '0';
        end if;

        if srst then
          m_axis.tvalid <= '0';
        end if;
      end if;
    end process;

  else generate

    int_axis.tready <= m_axis.tready;
    m_axis.tvalid   <= int_axis.tvalid; 
    m_axis.tdata    <= int_axis.tdata; 
    m_axis.tkeep    <= int_axis.tkeep; 
    m_axis.tuser    <= int_axis.tuser;
    m_axis.tlast    <= int_axis.tlast; 

  end generate;

end architecture;
