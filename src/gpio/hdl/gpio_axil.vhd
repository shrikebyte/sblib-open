--##############################################################################
--# File : gpio_axil.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! AXI Lite GPIO
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;
use work.gpio_regs_pkg.all;
use work.gpio_register_record_pkg.all;
use work.gpio_pkg.all;

entity gpio_axil is
  generic (
    --! Channel mode
    G_CH_MODE : gpio_mode_arr_t(gpio_range) := (others => GPIO_MODE_INOUT);
    --! Insert bit synchronizer before input. Only applicable for "IN" and "INOUT".
    G_CH_SYNC : bool_arr_t(gpio_range) := (others => false);
    -- Default output value. Only applicable for "OUT" and "INOUT".
    G_CH_DFLT_O : slv_arr_t(gpio_range)(AXIL_DATA_RANGE) := (others => (others => '0'));
    -- Default tri-state value. Only applicable for "OUT" and "INOUT".
    G_CH_DFLT_T : slv_arr_t(gpio_range)(AXIL_DATA_RANGE) := (others => (others => '0'))
  );
  port (
    clk  : in    std_logic;
    srst : in    std_logic;
    irq  : out   std_logic;
    --
    s_axil_req : in    axil_req_t;
    s_axil_rsp : out   axil_rsp_t;
    --
    gpio_i : in    slv_arr_t(gpio_range)(AXIL_DATA_RANGE) := (others => (others => '0'));
    gpio_o : out   slv_arr_t(gpio_range)(AXIL_DATA_RANGE);
    gpio_t : out   slv_arr_t(gpio_range)(AXIL_DATA_RANGE)
  );
end entity;

architecture rtl of gpio_axil is

  signal i : gpio_regs_up_t         := gpio_regs_up_init;
  signal o : gpio_regs_down_t       := gpio_regs_down_init;
  signal r : gpio_reg_was_read_t    := gpio_reg_was_read_init;
  signal w : gpio_reg_was_written_t := gpio_reg_was_written_init;

  signal irq_pre     : std_logic_vector(gpio_range);
  signal regi_din    : slv_arr_t(gpio_range)(AXIL_DATA_RANGE);
  signal regi_dout   : slv_arr_t(gpio_range)(AXIL_DATA_RANGE);
  signal rego_dout   : slv_arr_t(gpio_range)(AXIL_DATA_RANGE);
  signal regw_dout   : std_logic_vector(gpio_range);
  signal regi_tri    : slv_arr_t(gpio_range)(AXIL_DATA_RANGE);
  signal rego_tri    : slv_arr_t(gpio_range)(AXIL_DATA_RANGE);
  signal regw_tri    : std_logic_vector(gpio_range);
  signal rego_inten  : slv_arr_t(gpio_range)(AXIL_DATA_RANGE);
  signal regi_intsts : slv_arr_t(gpio_range)(AXIL_DATA_RANGE);
  signal rego_intsts : slv_arr_t(gpio_range)(AXIL_DATA_RANGE);

begin

  -- ---------------------------------------------------------------------------
  u_gpio_reg_file : entity work.gpio_register_file_axi_lite
  port map (
    clk             => clk,
    reset           => srst,
    s_axil_req      => s_axil_req,
    s_axil_rsp      => s_axil_rsp,
    regs_up         => i,
    regs_down       => o,
    reg_was_read    => r,
    reg_was_written => w
  );

  -- ---------------------------------------------------------------------------
  prc_irq_reduce : process (clk) is begin
    if rising_edge(clk) then
      irq <= or irq_pre;

      if srst then
        irq <= '0';
      end if;
    end if;
  end process;

  -- ---------------------------------------------------------------------------
  gen_chans : for j in gpio_range generate

    u_gpio_chan : entity work.gpio_chan
    generic map (
      G_CH_WIDTH  => AXIL_DATA_WIDTH,
      G_CH_MODE   => G_CH_MODE(j),
      G_CH_SYNC   => G_CH_SYNC(j),
      G_CH_DFLT_O => G_CH_DFLT_O(j),
      G_CH_DFLT_T => G_CH_DFLT_T(j)
    )
    port map (
      clk         => clk,
      srst        => srst,
      irq         => irq_pre(j),
      regi_din    => regi_din(j),
      regi_dout   => regi_dout(j),
      rego_dout   => rego_dout(j),
      regw_dout   => regw_dout(j),
      regi_tri    => regi_tri(j),
      rego_tri    => rego_tri(j),
      regw_tri    => regw_tri(j),
      rego_inten  => rego_inten(j),
      regi_intsts => regi_intsts(j),
      rego_intsts => rego_intsts(j),
      gpio_i      => gpio_i(j),
      gpio_o      => gpio_o(j),
      gpio_t      => gpio_t(j)
    );

    i.chan(j).din.din   <= unsigned(regi_din(j));
    i.chan(j).dout.dout <= unsigned(regi_dout(j));
    i.chan(j).tri.tri   <= unsigned(regi_tri(j));
    i.chan(j).isr.isr   <= unsigned(regi_intsts(j));

    rego_intsts(j) <= std_logic_vector(o.chan(j).isr.isr);
    rego_dout(j)   <= std_logic_vector(o.chan(j).dout.dout);
    regw_dout(j)   <= w.chan(j).dout;
    rego_tri(j)    <= std_logic_vector(o.chan(j).tri.tri);
    regw_tri(j)    <= w.chan(j).tri;
    rego_inten(j)  <= std_logic_vector(o.chan(j).ier.ier);

  end generate;

end architecture;
