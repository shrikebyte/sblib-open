--##############################################################################
--# File : axis_slice.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! Slice one input packet into several output packets
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_slice is
  generic (
    G_PACK_OUTPUT : boolean := true;
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
    num_bytes  : in u_unsigned;
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

  signal num_bytes_remaining_in_pkt0 : u_unsigned(num_bytes'range);
  signal num_bytes_in_this_beat : natural range 0 to s_axis.tkeep'length;

  type sliced_tkeep_t is record
    pkt0_tkeep: std_ulogic_vector(KW-1 downto 0);
    pkt1_tkeep: std_ulogic_vector(KW-1 downto 0);
  end record;

  impure function calc_sliced_tkeep (
    tkeep : std_ulogic_vector(KW-1 downto 0);
    num_bytes_in_current : u_unsigned(num_bytes'range);
  ) return sliced_tkeep_t
  is
    variable result : sliced_tkeep_t;
    variable mask : std_ulogic_vector(KW-1 downto 0) := (others=>'0');
  begin

    mask(to_integer(num_bytes_in_current) - 1 downto 0) := (others=>'1');

    result.pkt0_tkeep := mask;
    result.pkt1_tkeep := not mask;

    return result;
  end function;

  signal sliced_tkeep : sliced_tkeep_t;
  signal pkt1_tkeep : std_ulogic_vector(s_axis.tkeep'range);
  signal pkt1_tlast : std_ulogic;
  signal int0_axis_oe : std_ulogic;
  signal s_axis_xact : std_ulogic;
  signal int0_axis_tid : u_unsigned(0 downto 0);
  signal int1_axis_tid : u_unsigned(0 downto 0);

  signal int0_axis : axis_t (
    tdata(s_axis.tdata'range),
    tkeep(s_axis.tkeep'range),
    tuser(s_axis.tuser'range)
  );

  signal int1_axis : axis_t (
    tdata(s_axis.tdata'range),
    tkeep(s_axis.tkeep'range),
    tuser(s_axis.tuser'range)
  );

begin

  -- ---------------------------------------------------------------------------
  num_bytes_in_this_beat <= cnt_ones(s_axis.tkeep);
  int0_axis_oe <= int0_axis.tready or not int0_axis.tvalid;
  s_axis.tready <= int0_axis_oe and ((state = ST_TX0) or (state = ST_TX1));
  s_axis_xact <= s_axis.tvalid and s_axis.tready;
  sliced_tkeep <= calc_sliced_tkeep(
    s_axis.tkeep,
    num_bytes_remaining_in_pkt0
  );

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
          if s_axis.tvalid then
            if num_bytes /= 0 then
              num_bytes_remaining_in_pkt0 <= num_bytes;
              state    <= ST_TX0;
            else
              state    <= ST_TX1;
            end if;
          end if;

        -- ---------------------------------------------------------------------
        when ST_TX0 =>
          if s_axis_xact then

            int0_axis.tvalid  <= '1';
            int0_axis.tdata   <= s_axis.tdata;
            int0_axis.tuser   <= s_axis.tuser;
            int0_axis_tid     <= "0";

            if num_bytes_remaining_in_pkt0 > num_bytes_in_this_beat then
              -- In the middle of sending packet0
              int0_axis.tkeep   <= s_axis.tkeep;
              --
              if s_axis.tlast then
                sts_err_runt      <= '1';
                int0_axis.tlast   <= '1';
                num_bytes_remaining_in_pkt0 <= (others => '0');
                state <= ST_IDLE;
              else
                int0_axis.tlast   <= '0';
                num_bytes_remaining_in_pkt0 <= num_bytes_remaining_in_pkt0 - num_bytes_in_this_beat;
              end if;
              --
            elsif num_bytes_remaining_in_pkt0 = num_bytes_in_this_beat then
              -- Don't need to slice the last beat because the number of bytes
              -- in the current beat matches up perfectly with the number
              -- of remaining bytes in packet0.
              int0_axis.tlast   <= '1';
              int0_axis.tkeep   <= s_axis.tkeep;
              num_bytes_remaining_in_pkt0 <= (others => '0');
              --
              if s_axis.tlast then
                sts_err_runt <= '1';
                state <= ST_IDLE;
              else
                state <= ST_TX1;
              end if;
              --
            else
              -- Need to slice the last beat
              int0_axis.tlast   <= '1';
              int0_axis.tkeep   <= sliced_tkeep.pkt0_tkeep;
              --
              if s_axis.tlast then
                -- If we are slicing on a tlast beat, then tlast needs to be
                -- asserted for the last beat of packet0 output as well as for
                -- the first beat of packet1 output. We register this
                -- information here and use it in the next state.
                pkt1_tlast <= '1';
              else
                pkt1_tlast <= '0';
              end if;
              num_bytes_remaining_in_pkt0 <= (others => '0');
              pkt1_tkeep <= sliced_tkeep.pkt1_tkeep;
              state <= ST_PARTIAL;
            end if;
          end if;

        -- ---------------------------------------------------------------------
        when ST_PARTIAL =>
          if int0_axis_oe then
            int0_axis.tvalid  <= '1';
            int0_axis.tkeep   <= pkt1_tkeep;
            int0_axis.tdata   <= int0_axis.tdata;
            int0_axis.tuser   <= int0_axis.tuser;
            int0_axis_tid     <= "1";
            --
            if pkt1_tlast then
              int0_axis.tlast <= '1';
              state <= ST_IDLE;
            else
              int0_axis.tlast <= '0';
              state <= ST_TX1;
            end if;
            pkt1_tlast <= '0';
          end if;

        when ST_TX1 =>
          if s_axis_xact then
            int0_axis.tvalid  <= '1';
            int0_axis.tkeep   <= s_axis.tkeep;
            int0_axis.tdata   <= s_axis.tdata;
            int0_axis.tuser   <= s_axis.tuser;
            int0_axis_tid     <= "1";
            --
            if s_axis.tlast then
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
  gen_packer : if G_PACK_OUTPUT generate

    signal int0_tuser_tid : std_ulogic_vector(UW + (int0_axis_tid'length * KW) - 1 downto 0);
    signal int1_tuser_tid : std_ulogic_vector(UW + (int0_axis_tid'length * KW) - 1 downto 0);
    constant ID_UBW : natural := UBW + int0_axis_tid'length;

  begin

    -- Hijack the upper bits of each tuser byte to pass along the tid
    -- information through the packer stage. The packer can have variable
    -- latency, so the stream ID must be transported with the stream.
    gen_tuser_sel : for i in 0 to KW - 1 generate begin

      int0_tuser_tid((i * ID_UBW) + ID_UBW - 1 downto (i * ID_UBW)) <=
        std_ulogic_vector(int0_axis_tid) &
        int0_axis.tuser((i * UBW) + UBW - 1 downto (i * UBW));

      int1_axis.tuser((i * UBW) + UBW - 1 downto (i * UBW)) <=
        int1_tuser_tid((i * ID_UBW) + UBW - 1 downto (i * ID_UBW));

    end generate;

    int1_axis_tid <= u_unsigned(int1_tuser_tid(ID_UBW - 1 downto UBW));

    u_axis_pack : entity work.axis_pack
    port map(
      clk    => clk,
      srst   => srst,
      --
      s_axis.tready => int0_axis.tready,
      s_axis.tvalid => int0_axis.tvalid,
      s_axis.tlast  => int0_axis.tlast,
      s_axis.tkeep  => int0_axis.tkeep,
      s_axis.tdata  => int0_axis.tdata,
      s_axis.tuser  => int0_tuser_tid,
      --
      m_axis.tready => int1_axis.tready,
      m_axis.tvalid => int1_axis.tvalid,
      m_axis.tlast  => int1_axis.tlast,
      m_axis.tkeep  => int1_axis.tkeep,
      m_axis.tdata  => int1_axis.tdata,
      m_axis.tuser  => int1_tuser_tid
    );

  else generate

    u_axis_pipe : entity work.axis_pipe
    generic map(
      G_READY_PIPE => false,
      G_DATA_PIPE  => false
    )
    port map(
      clk => clk,
      srst => srst,
      s_axis => int0_axis,
      m_axis => int1_axis
    );

    int1_axis_tid <= int0_axis_tid;

  end generate;

  -- ---------------------------------------------------------------------------
  prc_out_sel : process (all) begin

    m0_axis.tvalid <= '0';
    m1_axis.tvalid <= '0';
    int1_axis.tready <= '0';

    if int1_axis_tid = "0" then
      m0_axis.tvalid <= int1_axis.tvalid and int1_axis.tready;
      int1_axis.tready <= m0_axis.tready;

    elsif int1_axis_tid = "1" then
      m1_axis.tvalid <= int1_axis.tvalid and int1_axis.tready;
      int1_axis.tready <= m1_axis.tready;
    end if;

  end process;

  m0_axis.tlast  <= int1_axis.tlast;
  m0_axis.tkeep  <= int1_axis.tkeep;
  m0_axis.tdata  <= int1_axis.tdata;
  m0_axis.tuser  <= int1_axis.tuser;

  m1_axis.tlast  <= int1_axis.tlast;
  m1_axis.tkeep  <= int1_axis.tkeep;
  m1_axis.tdata  <= int1_axis.tdata;
  m1_axis.tuser  <= int1_axis.tuser;

end architecture;
