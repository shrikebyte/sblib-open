--##############################################################################
--# File : axil_init_mgr.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! AXI-Lite initialization manager state machine.
--! This runs a hard-coded sequence of read and write transactions after reset.
--! Intended to configure an FPGA at startup / reset without the need for
--! software init scripts or a soft-processor. This can also be used to run a
--! BIST at startup by checking register values to ensure they match expected.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;

entity axil_init_mgr is
  generic (
    G_RESET_DELAY_CLKS : positive := 10;
    G_XACTIONS         : bus_xact_arr_t
  );
  port (
    --! System
    clk  : in    std_logic;
    srst : in    std_logic;
    --! AXI Lite interface
    m_axil_req : out   axil_req_t;
    m_axil_rsp : in    axil_rsp_t;
    --
    --! Valid data qualifier for the remaining m_sts_* signals
    m_sts_valid : out   std_logic;
    --! Indicates that the transaction had a bus error
    m_sts_bus_err : out   std_logic;
    --! Indicates that the transaction's read data did not match the expected data
    m_sts_chk_err : out   std_logic;
    --! Read data for the transaction (if it was a read)
    m_sts_chk_rdata : out   std_logic_vector(31 downto 0);
    --! Transaction index. Starts at 0 and counts up
    m_sts_xact_idx : out   unsigned(15 downto 0)
  );
end entity;

architecture rtl of axil_init_mgr is

  constant NUM_XACTIONS : integer := G_XACTIONS'length;

  type state_t is (
    ST_RESET, ST_START, ST_DONE, ST_WRITE_WAIT, ST_WRITE_RSP_WAIT,
    ST_READ_WAIT, ST_READ_RSP_WAIT
  );

  signal state : state_t;

  signal reset_cnt : integer range 0 to G_RESET_DELAY_CLKS - 1;
  signal idx       : integer range 0 to NUM_XACTIONS;

begin

  -- ---------------------------------------------------------------------------
  m_axil_req.awprot <= b"000";
  m_axil_req.arprot <= b"000";

  -- ---------------------------------------------------------------------------
  prc_axil_init_mgr : process (clk) is begin
    if rising_edge(clk) then
      -- Pulse
      m_sts_valid <= '0';

      case state is
        -- ---------------------------------------------------------------------
        when ST_RESET =>
          if reset_cnt = G_RESET_DELAY_CLKS - 1 then
            state <= ST_START;
          else
            reset_cnt <= reset_cnt + 1;
          end if;

        -- ---------------------------------------------------------------------
        when ST_START =>
          if idx = NUM_XACTIONS then
            state <= ST_DONE;
          elsif G_XACTIONS(idx).cmd = BUS_WRITE then
            m_axil_req.awvalid <= '1';
            m_axil_req.awaddr  <= G_XACTIONS(idx).addr;
            m_axil_req.wvalid  <= '1';
            m_axil_req.wdata   <= G_XACTIONS(idx).data;
            m_axil_req.wstrb   <= G_XACTIONS(idx).wstrb;
            m_axil_req.bready  <= '0';
            --
            state <= ST_WRITE_WAIT;
          elsif G_XACTIONS(idx).cmd = BUS_CHECK then
            m_axil_req.arvalid <= '1';
            m_axil_req.araddr  <= G_XACTIONS(idx).addr;
            m_axil_req.rready  <= '0';
            --
            state <= ST_READ_WAIT;
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
            m_sts_valid    <= '1';
            m_sts_xact_idx <= to_unsigned(idx, m_sts_xact_idx'length);
            m_sts_chk_err  <= '0';
            if m_axil_rsp.bresp = AXI_RSP_SLVERR or
               m_axil_rsp.bresp = AXI_RSP_DECERR then
              m_sts_bus_err <= '1';
            else
              m_sts_bus_err <= '0';
            end if;
            --
            idx   <= idx + 1;
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
            m_sts_valid     <= '1';
            m_sts_xact_idx  <= to_unsigned(idx, m_sts_xact_idx'length);
            m_sts_chk_rdata <= m_axil_rsp.rdata;
            if m_axil_rsp.rresp = AXI_RSP_SLVERR or
               m_axil_rsp.rresp = AXI_RSP_DECERR then
              m_sts_bus_err <= '1';
              m_sts_chk_err <= '0';
            elsif (m_axil_rsp.rdata and G_XACTIONS(idx).mask) /=
                  (G_XACTIONS(idx).data and G_XACTIONS(idx).mask) then
              m_sts_bus_err <= '0';
              m_sts_chk_err <= '1';
            else
              m_sts_bus_err <= '0';
              m_sts_chk_err <= '0';
            end if;
            --
            idx   <= idx + 1;
            state <= ST_START;
          end if;

        when others =>
          null;
      end case;

      if srst then
        m_sts_valid <= '0';
        --
        m_axil_req.awvalid <= '0';
        m_axil_req.wvalid  <= '0';
        m_axil_req.bready  <= '0';
        m_axil_req.arvalid <= '0';
        m_axil_req.rready  <= '0';
        --
        reset_cnt <= 0;
        idx       <= 0;
        state     <= ST_RESET;
      end if;

    end if;
  end process;

end architecture;
