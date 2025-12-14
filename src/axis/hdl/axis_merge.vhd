--##############################################################################
--# File : axis_merge.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! Merge 2 packets into one.
--! Does not support tuser (for now).
--! Supports packed unaligned packets, where tkeep is all ones, except for
--! on the tlast beat.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_merge is
  port (
    clk    : in    std_ulogic;
    srst   : in    std_ulogic;
    --
    s0_axis : view s_axis_v;
    s1_axis : view s_axis_v;
    --
    m_axis : view m_axis_v;
    --! Enable merge operation. If de-asserted, this module directly
    --! passes thru s0 to m.
    --! If asserted, s1 is concatenated to the end of s0 and both are passed
    --! thru to m.
    merge_enable : in std_ulogic
  );
end entity;

architecture rtl of axis_merge is

  -- Data width, keep width, and byte width
  constant DW : integer := m_axis.tdata'length;
  constant KW : integer := m_axis.tkeep'length;
  constant BW : integer := DW / KW;

  type state_t is (ST_IDLE, ST_FORWARD_S0, ST_PACK, ST_LAST, 
      ST_FORWARD_S1, ST_PASSTHRU);
  signal state : state_t;

  signal oe : std_ulogic;
  signal resid_tdata : std_ulogic_vector(m_axis.tdata'range);
  signal resid_tkeep : std_ulogic_vector(m_axis.tkeep'range);

  -- Represents packed data type, comprising of 2 back-to-back beats with
  -- some tkeep bits unset in one or both beats. 
  type pack_t is record
    -- Residual bytes
    resid_keep  : std_ulogic_vector(KW-1 downto 0);
    resid_data  : std_ulogic_vector(DW-1 downto 0);

    -- Packed bytes
    packed_keep : std_ulogic_vector(KW-1 downto 0);
    packed_data : std_ulogic_vector(DW-1 downto 0);
  end record;

  constant PACK_DEFAULT : pack_t := (
    resid_keep => (others => '0'), 
    resid_data => (others => '0'),
    packed_keep => (others => '0'), 
    packed_data => (others => '0')
  );

  -- Pack 2 sparse beats into one packed beat and one residual beat
  impure function calc_pack (
    lo_keep : std_ulogic_vector(KW-1 downto 0);
    lo_data : std_ulogic_vector(DW-1 downto 0);
    hi_keep : std_ulogic_vector(KW-1 downto 0);
    hi_data : std_ulogic_vector(DW-1 downto 0);
  ) return pack_t 
  is
    variable j : integer range 0 to KW := 0;
    variable k : integer range 0 to KW := 0;
    variable result : pack_t := PACK_DEFAULT;
  begin
    for i in 0 to KW - 1 loop
      if lo_keep(i) = '1' then
        -- Pack byte from lower input to packed output
        result.packed_keep(j) := '1';
        result.packed_data(j * BW + BW - 1 downto j * BW) := 
            lo_data(i * BW + BW - 1 downto i * BW);
        j := j + 1;
      end if;
    end loop;

    for i in 0 to KW - 1 loop
      if hi_keep(i) = '1' then
        if j < KW then
          -- Pack byte from upper input to packed output
          result.packed_keep(j) := '1';
          result.packed_data(j * BW + BW - 1 downto j * BW) := 
              hi_data(i * BW + BW - 1 downto i * BW);
          j := j + 1;
        else 
          -- Pack byte from upper input to residual output
          result.resid_keep(k) := '1';
          result.resid_data(k * BW + BW - 1 downto k * BW) := 
              hi_data(i * BW + BW - 1 downto i * BW);
          k := k + 1;
        end if;
      end if;
    end loop;

    return result;
  end function;

  signal pack : pack_t;

begin

  -- ---------------------------------------------------------------------------
  m_axis.tuser <= (others => '0');
  oe <= m_axis.tready or not m_axis.tvalid;
  s0_axis.tready <= oe and ((state = ST_FORWARD_S0) or (state = ST_PASSTHRU));
  s1_axis.tready <= oe and ((state = ST_FORWARD_S1) or (state = ST_PACK));
  pack <= calc_pack(resid_tkeep, resid_tdata, s1_axis.tkeep, s1_axis.tdata);

  prc_fsm : process (clk) begin
    if rising_edge(clk) then

      -- By default, clear mvalid if mready. The FSM might override this if it
      -- has new data to send.
      if m_axis.tready then
        m_axis.tvalid <= '0';
      end if;

      case state is
        -- ---------------------------------------------------------------------
        when ST_IDLE =>
          if s0_axis.tvalid then
            if merge_enable then
              state <= ST_FORWARD_S0;
            else
              state <= ST_PASSTHRU;
            end if;
          end if;

        -- ---------------------------------------------------------------------
        when ST_FORWARD_S0 =>
          if s0_axis.tvalid and s0_axis.tready then

            m_axis.tdata  <= s0_axis.tdata;
            m_axis.tkeep  <= s0_axis.tkeep;

            if s0_axis.tlast then
              if (and s0_axis.tkeep) then
                -- If the last beat of s0 is full, skip repacking and simply
                -- forward s1 to the output. This saves one bubble cycle.
                m_axis.tvalid <= '1';
                m_axis.tlast  <= '0';
                state         <= ST_FORWARD_S1;
              else
                -- If the last beat of s0 is sparse, store the partial beat
                -- as residual and insert a bubble cycle. Bubble is needed
                -- because we can't output a new beat until we rx the first
                -- beat of the second packet to make a full output beat.
                resid_tdata   <= s0_axis.tdata;
                resid_tkeep   <= s0_axis.tkeep;
                m_axis.tvalid <= '0';
                m_axis.tlast  <= '0';
                state         <= ST_PACK;
              end if;
            else 
              m_axis.tvalid <= '1';
              m_axis.tlast  <= '0';
            end if;
          end if;

        -- ---------------------------------------------------------------------
        when ST_PACK =>
          if s1_axis.tvalid and s1_axis.tready then

            m_axis.tvalid <= '1';
            m_axis.tdata  <= pack.packed_data;
            m_axis.tkeep  <= pack.packed_keep;
            resid_tdata   <= pack.resid_data;
            resid_tkeep   <= pack.resid_keep;

            if s1_axis.tlast then
              if (or pack.resid_keep) then
                -- If there are any residual bytes, we need to transmit
                -- one extra beat to finish the packet.
                m_axis.tlast  <= '0';
                state <= ST_LAST;
              else
                -- Otherwise, if there are no residual bytes left at this point,
                -- we're done.
                m_axis.tlast  <= '1';
                resid_tkeep   <= (others => '0');
                state         <= ST_IDLE;
              end if;
            else 
              m_axis.tlast  <= '0';
            end if;

          end if;

        -- ---------------------------------------------------------------------
        when ST_LAST =>
          if oe then
            m_axis.tvalid <= '1';
            m_axis.tdata  <= resid_tdata;
            m_axis.tkeep  <= resid_tkeep;
            m_axis.tlast  <= '1';
            resid_tkeep   <= (others => '0');
            state         <= ST_IDLE;
          end if;

        -- ---------------------------------------------------------------------
        when ST_FORWARD_S1 =>
          if s1_axis.tvalid and s1_axis.tready then

            m_axis.tvalid <= '1';
            m_axis.tdata  <= s1_axis.tdata;
            m_axis.tkeep  <= s1_axis.tkeep;

            if s1_axis.tlast then
              m_axis.tlast  <= '1';
              state         <= ST_IDLE;
            else 
              m_axis.tlast  <= '0';
            end if;
          end if;

        -- ---------------------------------------------------------------------
        when ST_PASSTHRU =>
          if s0_axis.tvalid and s0_axis.tready then

            m_axis.tvalid <= '1';
            m_axis.tdata  <= s0_axis.tdata;
            m_axis.tkeep  <= s0_axis.tkeep;

            if s0_axis.tlast then
              m_axis.tlast  <= '1';
              state         <= ST_IDLE;
            else 
              m_axis.tlast  <= '0';
            end if;
          end if;

        when others =>
          null;
      end case;

      if srst then
        m_axis.tvalid  <= '0';
        resid_tkeep    <= (others => '0');
        state          <= ST_IDLE;
      end if;
    end if;
  end process;

end architecture;
