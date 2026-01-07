--##############################################################################
--# File : axis_pack.vhd
--# Auth : David Gussler
--# ============================================================================
--# Shrikebyte VHDL Library - https://github.com/shrikebyte/sblib
--# Copyright (C) Shrikebyte, LLC
--# Licensed under the Apache 2.0 license, see LICENSE for details.
--# ============================================================================
--# Removes null bytes from a stream.
--# This module has a few tkeep restrictions:
--#   1. Input tkeep bits must be contiguous from low to high. For example:
--#      0000, 0001, 0011, 0111, and 1111 are allowed, but 1010 or 0100 are not
--#      allowed. The logic resources required to implement a general purpose
--#      null byte remover are just way too high for practical use, and most
--#      of the time, if the surrounding system is well-designed, then there
--#      should never be a need to remove non-contiguous null-bytes.
--#   2. On a tlast beat, at least one tkeep bit must be set. Supporting null
--#      tlast would make this module more general purpose, but it would cost
--#      an additional cycle of latency, and as with the first first
--#      restriction, there are very few systems in practice that would need
--#      support for this feature.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_pack is
  generic (
    -- This reduces the crit path by 2 logic levels on Artix 7
    -- when tkeep width is set to 8. This will add more of noticeable
    -- improvement for larger tkeep.
    -- This comes at the cost of extra registers and an additional cycle of
    -- latency, so only include if its really necessary. Usually, its not.
    G_EXTRA_PIPE : boolean := false
  );
  port (
    clk  : in    std_ulogic;
    srst : in    std_ulogic;
    --
    s_axis : view s_axis_v;
    --
    m_axis : view m_axis_v
  );
end entity;

architecture rtl of axis_pack is

  constant DW  : integer := m_axis.tdata'length;
  constant KW  : integer := m_axis.tkeep'length;
  constant UW  : integer := m_axis.tuser'length;
  constant DBW : integer := DW / KW;
  constant UBW : integer := UW / KW;

  type   state_t is (ST_PACK, ST_LAST);
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
  signal offset_nxt     : integer range 0 to KW - 1;
  signal offset_reg     : integer range 0 to KW - 1;

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

  assert is_pwr2(DBW)
    report "axis_pack: Data byte width must be a power of 2."
    severity error;

  assert is_pwr2(UBW)
    report "axis_pack: User byte width must be a power of 2."
    severity error;

  prc_assert : process (clk) is begin
    if rising_edge(clk) then
      assert not (s_axis.tvalid = '1' and s_axis.tlast = '1' and
        (nor s_axis.tkeep) = '1')
        report "axis_pack: Null tlast beat detected on input. At " &
               "least one tkeep bit must be set on tlast."
        severity error;

      assert not (s_axis.tvalid = '1' and not is_contig(s_axis.tkeep))
        report "axis_pack: Non-contiguous tkeep detected on input. tkeep " &
               "must be contiguous (e.g., 0001, 0011, 0111, but not 0101 " &
               "or 0100)."
        severity error;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  pipe0_axis.tready <= (pipe1_axis_reg.tready or not pipe1_axis_reg.tvalid) and
    to_sl((state_reg = ST_PACK));

  -- ---------------------------------------------------------------------------
  -- Optionally pre-calculate pipe0_axis_cnt for better timing
  gen_pipe0 : if G_EXTRA_PIPE generate

    s_axis.tready <= pipe0_axis.tready or not pipe0_axis.tvalid;

    prc_pipe0 : process (clk) is begin
      if rising_edge(clk) then
        if s_axis.tvalid and s_axis.tready then
          pipe0_axis.tvalid <= '1';
          pipe0_axis.tlast  <= s_axis.tlast;
          pipe0_axis.tdata  <= s_axis.tdata;
          pipe0_axis.tkeep  <= s_axis.tkeep;
          pipe0_axis.tuser  <= s_axis.tuser;
          --
          pipe0_axis_cnt <= cnt_ones_contig(s_axis.tkeep);
        elsif pipe0_axis.tready then
          pipe0_axis.tvalid <= '0';
        end if;

        if srst then
          pipe0_axis.tvalid <= '0';
        end if;
      end if;
    end process;

  else generate

    axis_attach(s_axis, pipe0_axis);

    pipe0_axis_cnt <= cnt_ones_contig(s_axis.tkeep);

  end generate;

  -- ---------------------------------------------------------------------------
  prc_fsm_comb : process (all) is begin
    pipe1_axis_nxt.tvalid <= pipe1_axis_reg.tvalid;
    pipe1_axis_nxt.tlast  <= pipe1_axis_reg.tlast;
    pipe1_axis_nxt.tkeep  <= pipe1_axis_reg.tkeep;
    pipe1_axis_nxt.tdata  <= pipe1_axis_reg.tdata;
    pipe1_axis_nxt.tuser  <= pipe1_axis_reg.tuser;
    --
    offset_nxt <= offset_reg;
    state_nxt  <= state_reg;

    case state_reg is

      -- -----------------------------------------------------------------------
      when ST_PACK =>
        if pipe0_axis.tvalid and pipe0_axis.tready then
          if pipe0_axis.tlast then
            offset_nxt <= 0;
            if pipe1_axis_nxt.tkeep(KW) then
              -- If there will be residual bytes leftover in the buffer when
              -- we get an input tlast, then we need to stall the input for one
              -- transaction and send one extra output beat to transmit
              -- the residuals. This situation arises when a partial beat
              -- has already been accumulated and a tlast input beat causes
              -- the buffer to overflow past the number of bytes in one beat.
              pipe1_axis_nxt.tlast <= '0';
              state_nxt            <= ST_LAST;
            else
              -- Otherwise, send the last on the next beat and continue on
              -- with business as usual.
              pipe1_axis_nxt.tlast <= '1';
            end if;
          else
            -- Increment the buffer offset by the number of new input bytes.
            -- The offset uses natural unsigned rollover when keep width
            -- is a power of 2. That's what the modulus operator synthesizes
            -- to here. Its the same thing as using an unsigned type with
            -- automatic rollover, but using an integer is more convenient.
            offset_nxt           <= (offset_reg + pipe0_axis_cnt) mod KW;
            pipe1_axis_nxt.tlast <= '0';
          end if;

          if pipe1_axis_nxt.tkeep(KW - 1) or pipe0_axis.tlast then
            -- If the next output buffer will be full or the current input
            -- is a tlast, then the next output should be valid
            pipe1_axis_nxt.tvalid <= '1';
          else
            pipe1_axis_nxt.tvalid <= '0';
          end if;

          if pipe1_axis_reg.tkeep(KW - 1) or pipe1_axis_reg.tlast then
            -- If the current output beat is full / last, then shift out.
            pipe1_axis_nxt.tkeep                  <= std_ulogic_vector(shift_right(unsigned(pipe1_axis_reg.tkeep), KW));
            pipe1_axis_nxt.tdata(DW - 1 downto 0) <= pipe1_axis_reg.tdata(DW * 2 - 1 downto DW);
            pipe1_axis_nxt.tuser(UW - 1 downto 0) <= pipe1_axis_reg.tuser(UW * 2 - 1 downto UW);
          end if;

          -- Store the new input data at the buffer offset.
          pipe1_axis_nxt.tkeep(offset_reg + KW - 1 downto offset_reg)                 <= pipe0_axis.tkeep;
          pipe1_axis_nxt.tdata((offset_reg * DBW) + DW - 1 downto (offset_reg * DBW)) <= pipe0_axis.tdata;
          pipe1_axis_nxt.tuser((offset_reg * UBW) + UW - 1 downto (offset_reg * UBW)) <= pipe0_axis.tuser;
        elsif pipe1_axis_reg.tready then
          pipe1_axis_nxt.tvalid <= '0';
        end if;

      -- -----------------------------------------------------------------------
      when ST_LAST =>
        if pipe1_axis_reg.tready then
          -- We already know that pipe1_axis_reg.tvalid is high here because it
          -- was set by the prev state, so no need to check for it.
          pipe1_axis_nxt.tvalid <= '1';
          pipe1_axis_nxt.tlast  <= '1';

          -- Shift out
          pipe1_axis_nxt.tkeep                  <= std_ulogic_vector(shift_right(unsigned(pipe1_axis_reg.tkeep), KW));
          pipe1_axis_nxt.tdata(DW - 1 downto 0) <= pipe1_axis_reg.tdata(DW * 2 - 1 downto DW);
          pipe1_axis_nxt.tuser(UW - 1 downto 0) <= pipe1_axis_reg.tuser(UW * 2 - 1 downto UW);

          state_nxt <= ST_PACK;
        end if;

    end case;

  end process;

  -- ---------------------------------------------------------------------------
  prc_fsm_ff : process (clk) is begin
    if rising_edge(clk) then
      pipe1_axis_reg.tvalid <= pipe1_axis_nxt.tvalid;
      pipe1_axis_reg.tlast  <= pipe1_axis_nxt.tlast;
      pipe1_axis_reg.tkeep  <= pipe1_axis_nxt.tkeep;
      pipe1_axis_reg.tdata  <= pipe1_axis_nxt.tdata;
      pipe1_axis_reg.tuser  <= pipe1_axis_nxt.tuser;
      --
      offset_reg <= offset_nxt;
      state_reg  <= state_nxt;

      if srst then
        pipe1_axis_reg.tvalid <= '0';
        pipe1_axis_reg.tkeep  <= (others=> '0');
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
