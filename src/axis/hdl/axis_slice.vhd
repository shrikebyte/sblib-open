--##############################################################################
--# File : axis_slice.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--# Slices one input packet into two output packets at a user-specified
--# byte boundary of the input packet.
--#
--# NOTICE: Does not pack tkeep for unaligned slices. If this
--# feature is needed, then instantiate `axis_pack` between the output
--# of this module and the downstream module that requires packed tkeep.
--#
--# Output tkeep bits will alwyas be contiguous, so long as the input rules are
--# followed.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_slice is
  generic (
    -- Max number of bytes that can be sent out in each M0 packet
    G_MAX_M0_BYTES : positive := 2047;
    -- This reduces the crit path by 3 logic levels on Artix 7
    -- when tkeep width is set to 8. This will add more of noticeable
    -- improvement for larger tkeep.
    -- This comes at the cost of extra registers and an additional cycle of
    -- latency, so only include if its really necessary. Usually, its not.
    G_EXTRA_PIPE : boolean := false
  );
  port (
    clk    : in    std_ulogic;
    srst   : in    std_ulogic;
    --
    s_axis : view s_axis_v;
    --
    m0_axis : view m_axis_v;
    m1_axis : view m_axis_v;
    --! Number of bytes from the start of the input to send to the first output
    --! port. The remaining input bytes, until tlast, will be sent to the
    --! second output port. Note tat this does not necessarily have to be
    --! 8-bit bytes. For example, if data width is 32 and keep width is 2, then
    --! byte width would be 16.
    num_bytes  : in natural range 0 to G_MAX_M0_BYTES;
    --! Pulses if the length of the input packet was shorter than split_bytes.
    sts_err_runt : out std_ulogic;
  );
end entity;

architecture rtl of axis_slice is

  constant KW : integer := s_axis.tkeep'length;
  constant DW : integer := s_axis.tdata'length;
  constant UW : integer := s_axis.tuser'length;
  constant DBW : integer := DW / KW;
  constant UBW : integer := UW / KW;

  type state_t is (ST_IDLE, ST_TX0, ST_PARTIAL, ST_TX1);
  signal state : state_t;

  signal remain_cnt : natural range 0 to G_MAX_M0_BYTES;
  signal pipe0_num_bytes : natural range 0 to G_MAX_M0_BYTES;
  signal pipe0_axis_cnt : natural range 0 to KW;

  signal shft_tkeep : std_ulogic_vector(s_axis.tkeep'range);
  signal shft_tdata : std_ulogic_vector(s_axis.tdata'range);
  signal shft_tuser : std_ulogic_vector(s_axis.tuser'range);
  signal partial_tlast : std_ulogic;
  signal int0_axis_tid : u_unsigned(0 downto 0);

  signal pipe0_axis : axis_t (
    tdata(s_axis.tdata'range),
    tkeep(s_axis.tkeep'range),
    tuser(s_axis.tuser'range)
  );

  signal int0_axis : axis_t (
    tdata(s_axis.tdata'range),
    tkeep(s_axis.tkeep'range),
    tuser(s_axis.tuser'range)
  );

  signal shft_tdata_arr : slv_arr_t(1 to KW - 1)(DW - 1 downto 0);
  signal shft_tuser_arr : slv_arr_t(1 to KW - 1)(UW - 1 downto 0);

begin

  -- ---------------------------------------------------------------------------
  prc_assert : process (clk) begin
    if rising_edge(clk) then
      assert not (s_axis.tvalid = '1' and s_axis.tlast = '1' and
        (nor s_axis.tkeep) = '1')
        report "axis_slice: Null tlast beat detected on input. At " &
          "least one tkeep bit must be set on tlast."
        severity error;

      assert not (s_axis.tvalid = '1' and not is_contig(s_axis.tkeep))
        report "axis_slice: Non-contiguous tkeep detected on input. tkeep " &
          "must be contiguous (e.g., 0001, 0011, 0111, but not 0101 or 0100)."
        severity error;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  pipe0_axis.tready <= (int0_axis.tready or not int0_axis.tvalid) and
                       to_sl(((state = ST_TX0) or (state = ST_TX1)));

  -- ---------------------------------------------------------------------------
  -- Pre-calculate pipe0_axis_cnt for better timing
  gen_pipe0 : if G_EXTRA_PIPE generate

    s_axis.tready <= pipe0_axis.tready or not pipe0_axis.tvalid;

    prc_pipe0 : process (clk) begin
      if rising_edge(clk) then
        if s_axis.tvalid and s_axis.tready then
          pipe0_axis.tvalid   <= '1';
          pipe0_axis.tlast    <= s_axis.tlast;
          pipe0_axis.tdata    <= s_axis.tdata;
          pipe0_axis.tkeep    <= s_axis.tkeep;
          pipe0_axis.tuser    <= s_axis.tuser;
          --
          pipe0_axis_cnt <= cnt_ones_contig(s_axis.tkeep);
          pipe0_num_bytes <= num_bytes;
        elsif pipe0_axis.tready then
          pipe0_axis.tvalid <= '0';
        end if;

        if srst then
          pipe0_axis.tvalid <= '0';
        end if;
      end if;
    end process;

  else generate

    s_axis.tready <= pipe0_axis.tready;

    pipe0_axis.tvalid   <= s_axis.tvalid;
    pipe0_axis.tlast    <= s_axis.tlast;
    pipe0_axis.tdata    <= s_axis.tdata;
    pipe0_axis.tkeep    <= s_axis.tkeep;
    pipe0_axis.tuser    <= s_axis.tuser;
    pipe0_axis_cnt      <= cnt_ones_contig(s_axis.tkeep);
    pipe0_num_bytes     <= num_bytes;

  end generate;

  -- ---------------------------------------------------------------------------
  -- Pre-calculate the variable shift amounts with KW static shifts and use a
  -- mux to select the final shifted output rather than using a general barrel
  -- shifter. A mux has a shallower logic depth than a barrel shifter so this
  -- improves timing. A general barrel shifter is not needed here because we
  -- know the DBW and UBW shift amounts at compile-time.
  -- By virtue of how the FSM works, we also know that the shift amount will
  -- never be 0 or KW, so we can skip computing these to save some LUTs.
  gen_shift_mux : for i in 1 to KW - 1 generate
    shft_tdata_arr(i) <= std_logic_vector(shift_right(unsigned(pipe0_axis.tdata), i * DBW));
    shft_tuser_arr(i) <= std_logic_vector(shift_right(unsigned(pipe0_axis.tuser), i * UBW));
  end generate;

  -- ---------------------------------------------------------------------------
  prc_fsm : process (clk) begin
    if rising_edge(clk) then

      sts_err_runt <= '0';

      if int0_axis.tready then
        int0_axis.tvalid <= '0';
      end if;

      case state is
        -- ---------------------------------------------------------------------
        when ST_IDLE =>
          if pipe0_axis.tvalid then
            if pipe0_num_bytes /= 0 then
              remain_cnt <= pipe0_num_bytes;
              state    <= ST_TX0;
            else
              state    <= ST_TX1;
            end if;
          end if;

        -- ---------------------------------------------------------------------
        when ST_TX0 =>
          if pipe0_axis.tvalid and pipe0_axis.tready then

            int0_axis.tvalid  <= '1';
            int0_axis.tdata   <= pipe0_axis.tdata;
            int0_axis.tuser   <= pipe0_axis.tuser;
            int0_axis_tid     <= "0";

            if remain_cnt > pipe0_axis_cnt then
              -- In the middle of sending packet0
              int0_axis.tkeep   <= pipe0_axis.tkeep;
              --
              if pipe0_axis.tlast then
                sts_err_runt      <= '1';
                int0_axis.tlast   <= '1';
                remain_cnt <= 0;
                state <= ST_IDLE;
              else
                int0_axis.tlast   <= '0';
                remain_cnt <= remain_cnt - pipe0_axis_cnt;
              end if;
              --
            elsif remain_cnt = pipe0_axis_cnt then
              -- Don't need to slice the last beat because the number of bytes
              -- in the current beat matches up perfectly with the number
              -- of remaining bytes in packet0.
              int0_axis.tlast   <= '1';
              int0_axis.tkeep   <= pipe0_axis.tkeep;
              remain_cnt <= 0;
              --
              if pipe0_axis.tlast then
                sts_err_runt <= '1';
                state <= ST_IDLE;
              else
                state <= ST_TX1;
              end if;
              --
            else
              -- Need to slice the last beat
              int0_axis.tlast   <= '1';
              int0_axis.tkeep(remain_cnt - 1 downto 0) <= pipe0_axis.tkeep(remain_cnt - 1 downto 0);
              int0_axis.tkeep(KW - 1 downto remain_cnt) <= (others=>'0');
              --
              if pipe0_axis.tlast then
                -- If we are slicing on a tlast beat, then tlast needs to be
                -- asserted for the last beat of packet0 output as well as for
                -- the first beat of packet1 output. We register this
                -- information here and use it in the next state.
                partial_tlast <= '1';
              else
                partial_tlast <= '0';
              end if;
              remain_cnt <= 0;

              -- Shift and store the upper bytes of the partial beat for the
              -- next output beat.
              shft_tkeep <= std_ulogic_vector(shift_right(unsigned(pipe0_axis.tkeep), remain_cnt));
              shft_tdata <= shft_tdata_arr(remain_cnt);
              shft_tuser <= shft_tuser_arr(remain_cnt);

              state <= ST_PARTIAL;
            end if;
          end if;

        -- ---------------------------------------------------------------------
        when ST_PARTIAL =>
          if int0_axis.tready then
            -- We already know that int0_axis.tvalid is high here because
            -- it was set by the prev state, so no need to check for it.
            int0_axis.tvalid  <= '1';
            int0_axis.tkeep   <= shft_tkeep;
            int0_axis.tdata   <= shft_tdata;
            int0_axis.tuser   <= shft_tuser;
            int0_axis_tid     <= "1";
            --
            if partial_tlast then
              int0_axis.tlast <= '1';
              state <= ST_IDLE;
            else
              int0_axis.tlast <= '0';
              state <= ST_TX1;
            end if;
            partial_tlast <= '0';
          end if;

        when ST_TX1 =>
          if pipe0_axis.tvalid and pipe0_axis.tready then
            int0_axis.tvalid  <= '1';
            int0_axis.tkeep   <= pipe0_axis.tkeep;
            int0_axis.tdata   <= pipe0_axis.tdata;
            int0_axis.tuser   <= pipe0_axis.tuser;
            int0_axis_tid     <= "1";
            --
            if pipe0_axis.tlast then
              int0_axis.tlast  <= '1';
              state            <= ST_IDLE;
            else
              int0_axis.tlast  <= '0';
            end if;
          end if;

        when others =>
          null;
      end case;

      if srst then
        int0_axis.tvalid <= '0';
        sts_err_runt     <= '0';
        state            <= ST_IDLE;
      end if;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  prc_out_sel : process (all) begin

    m0_axis.tvalid <= '0';
    m1_axis.tvalid <= '0';
    int0_axis.tready <= '0';

    if int0_axis_tid = "0" then
      m0_axis.tvalid <= int0_axis.tvalid and int0_axis.tready;
      int0_axis.tready <= m0_axis.tready;

    elsif int0_axis_tid = "1" then
      m1_axis.tvalid <= int0_axis.tvalid and int0_axis.tready;
      int0_axis.tready <= m1_axis.tready;
    end if;

  end process;

  m0_axis.tlast  <= int0_axis.tlast;
  m0_axis.tkeep  <= int0_axis.tkeep;
  m0_axis.tdata  <= int0_axis.tdata;
  m0_axis.tuser  <= int0_axis.tuser;
  m1_axis.tlast  <= int0_axis.tlast;
  m1_axis.tkeep  <= int0_axis.tkeep;
  m1_axis.tdata  <= int0_axis.tdata;
  m1_axis.tuser  <= int0_axis.tuser;

end architecture;
