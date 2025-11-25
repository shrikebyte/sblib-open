--##############################################################################
--# File : wb_to_axil.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! Wishbone B4 (Synchronous, non-pipelined) to AXI-Lite bridge.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;

entity wb_to_axil is
  port (
    clk        : in    std_logic;
    srst       : in    std_logic;
    s_wb_req   : in    wb_req_t;
    s_wb_rsp   : out   wb_rsp_t;
    m_axil_req : out   axil_req_t;
    m_axil_rsp : in    axil_rsp_t
  );
end entity;

architecture rtl of wb_to_axil is

  type state_t is (
    ST_START, ST_DONE, ST_WRITE_WAIT, ST_WRITE_RSP_WAIT, ST_READ_WAIT,
    ST_READ_RSP_WAIT
  );

  signal state : state_t;

begin

  -- ---------------------------------------------------------------------------
  m_axil_req.awprot <= b"000";
  m_axil_req.arprot <= b"000";

  -- ---------------------------------------------------------------------------
  prc_wb_to_axil : process (clk) is begin
    if rising_edge(clk) then
      -- Pulse
      s_wb_rsp.ack <= '0';
      s_wb_rsp.err <= '0';

      case state is

        -- ---------------------------------------------------------------------
        when ST_START =>
          if s_wb_req.stb then
            if s_wb_req.wen then
              m_axil_req.awvalid <= '1';
              m_axil_req.awaddr  <= s_wb_req.addr;
              m_axil_req.wvalid  <= '1';
              m_axil_req.wdata   <= s_wb_req.wdat;
              m_axil_req.wstrb   <= s_wb_req.wsel;
              m_axil_req.bready  <= '0';
              --
              state <= ST_WRITE_WAIT;
            else
              m_axil_req.arvalid <= '1';
              m_axil_req.araddr  <= s_wb_req.addr;
              m_axil_req.rready  <= '0';
              --
              state <= ST_READ_WAIT;
            end if;
          end if;

        -- ---------------------------------------------------------------------
        when ST_WRITE_WAIT =>
          if m_axil_rsp.awready and m_axil_rsp.wready then
            m_axil_req.awvalid <= '0';
            m_axil_req.wvalid  <= '0';
            m_axil_req.bready  <= '1';
            --
            state <= ST_WRITE_RSP_WAIT;
          end if;

        -- ---------------------------------------------------------------------
        when ST_WRITE_RSP_WAIT =>
          if m_axil_rsp.bvalid then
            m_axil_req.bready <= '0';
            --
            s_wb_rsp.ack <= '1';
            s_wb_rsp.err <= to_sl(m_axil_rsp.bresp = AXI_RSP_SLVERR or
                m_axil_rsp.bresp = AXI_RSP_DECERR);
            --
            state <= ST_START;
          end if;

        -- ---------------------------------------------------------------------
        when ST_READ_WAIT =>
          if m_axil_rsp.arready then
            m_axil_req.arvalid <= '0';
            m_axil_req.rready  <= '1';
            --
            state <= ST_READ_RSP_WAIT;
          end if;

        -- ---------------------------------------------------------------------
        when ST_READ_RSP_WAIT =>
          if m_axil_rsp.rvalid then
            m_axil_req.rready <= '0';
            --
            s_wb_rsp.ack  <= '1';
            s_wb_rsp.err  <= to_sl(m_axil_rsp.bresp = AXI_RSP_SLVERR or
                m_axil_rsp.bresp = AXI_RSP_DECERR);
            s_wb_rsp.rdat <= m_axil_rsp.rdata;
            --
            state <= ST_START;
          end if;

        when others =>
          null;
      end case;

      if srst then
        s_wb_rsp.ack <= '0';
        s_wb_rsp.err <= '0';
        --
        m_axil_req.awvalid <= '0';
        m_axil_req.wvalid  <= '0';
        m_axil_req.bready  <= '0';
        m_axil_req.arvalid <= '0';
        m_axil_req.rready  <= '0';
        --
        state <= ST_START;
      end if;

    end if;
  end process;

end architecture;
