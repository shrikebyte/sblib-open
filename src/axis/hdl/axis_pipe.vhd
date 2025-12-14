--##############################################################################
--# File : axis_pipe.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! AXI-Stream pipeline register. Has options to pipeline both the
--! "forward" data / valid and the "backward" ready signals.
--! Maintains full throughput without inserting bubbles.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.axis_pkg.all;

entity axis_pipe is
  generic (
    G_READY_PIPE : boolean  := true;
    G_DATA_PIPE  : boolean  := true
  );
  port (
    clk    : in    std_ulogic;
    srst   : in    std_ulogic;
    --
    s_axis : view s_axis_v;
    --
    m_axis : view m_axis_v;
  );
end entity;

architecture rtl of axis_pipe is

  signal int_axis : axis_t (
    tdata(s_axis.tdata'range),
    tkeep(s_axis.tkeep'range),
    tuser(s_axis.tuser'range)
  );

begin

  -- ---------------------------------------------------------------------------
  gen_ready_pipe : if G_READY_PIPE generate

    signal skid_axis_tlast  : std_ulogic;
    signal skid_axis_tdata  : std_ulogic_vector(s_axis.tdata'range);
    signal skid_axis_tkeep  : std_ulogic_vector(s_axis.tkeep'range);
    signal skid_axis_tuser  : std_ulogic_vector(s_axis.tuser'range);

  begin

    prc_ready_pipe : process (clk) begin
      if rising_edge(clk) then

        -- Register tready
        if int_axis.tvalid then
          s_axis.tready <= int_axis.tready;
        end if;

        -- New transaction at the input but output is not ready. This condition
        -- is possible because input ready is delayed by one cycle since it is
        -- registered.
        -- Store input data to the temporary skid buffer when output ready
        -- suddenly drops.
        if s_axis.tvalid and s_axis.tready and not int_axis.tready then
          skid_axis_tlast  <= s_axis.tlast;
          skid_axis_tdata  <= s_axis.tdata;
          skid_axis_tkeep  <= s_axis.tkeep;
          skid_axis_tuser  <= s_axis.tuser;
        end if;

        if srst then
          s_axis.tready <= '1';
        end if;
      end if;
    end process;

    prc_out_select : process (all) begin
      if s_axis.tready then
        -- Input is ready. Route input directly to output with zero latency.
        int_axis.tvalid <= s_axis.tvalid; 
        int_axis.tlast  <= s_axis.tlast; 
        int_axis.tdata  <= s_axis.tdata; 
        int_axis.tkeep  <= s_axis.tkeep; 
        int_axis.tuser  <= s_axis.tuser; 
      else
        -- Input is not ready. Route skid buffer to output. Valid can be held
        -- at '1' here because after a skid-buffer output valid-ready combo,
        -- we know that the output will switch to the direct input on the next
        -- cycle.
        int_axis.tvalid <= '1';
        int_axis.tlast  <= skid_axis_tlast;
        int_axis.tdata  <= skid_axis_tdata;
        int_axis.tkeep  <= skid_axis_tkeep;
        int_axis.tuser  <= skid_axis_tuser;
      end if;
    end process;

  else generate

    s_axis.tready   <= int_axis.tready;
    int_axis.tvalid <= s_axis.tvalid; 
    int_axis.tlast  <= s_axis.tlast; 
    int_axis.tdata  <= s_axis.tdata; 
    int_axis.tkeep  <= s_axis.tkeep; 
    int_axis.tuser  <= s_axis.tuser; 

  end generate;


  -- ---------------------------------------------------------------------------
  gen_data_pipe : if G_DATA_PIPE generate begin

    -- Output ready acts as a clock enable for the output data register.
    -- To avoid a lockup scenario, we must also be allowed to output new data
    -- on the next cycle when the output interface is not currently valid.
    -- This satisfies the axi stream handshaking rule that states that setting
    -- output valid cannot be solely dependent on waiting for output ready to
    -- go high. Ready is allowed to wait for valid, so if valid were
    -- also allowed to wait for ready, then you have a chicken and egg problem
    -- where both are stuck waiting on each other forever.
    int_axis.tready <= m_axis.tready or not m_axis.tvalid;

    prc_data_pipe : process (clk) begin
      if rising_edge(clk) then
        if int_axis.tvalid and int_axis.tready then
          -- If there's a new transaction accepted at the input, we also
          -- implicitly know that the output buffer is empty and ready.
          m_axis.tvalid   <= '1'; 
          m_axis.tlast    <= int_axis.tlast; 
          m_axis.tdata    <= int_axis.tdata; 
          m_axis.tkeep    <= int_axis.tkeep; 
          m_axis.tuser    <= int_axis.tuser;
        elsif m_axis.tready then
          -- If no new transaction at the input and output is ready,
          -- de-assert tvalid.
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
    m_axis.tlast    <= int_axis.tlast; 
    m_axis.tdata    <= int_axis.tdata; 
    m_axis.tkeep    <= int_axis.tkeep; 
    m_axis.tuser    <= int_axis.tuser; 
    
  end generate;

end architecture;
