--##############################################################################
--# File : gpio_axil_tb.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! GPIO module testbench
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library vunit_lib;
  context vunit_lib.vunit_context;
  context vunit_lib.vc_context;
use vunit_lib.axi_lite_master_pkg.all;
use work.util_pkg.all;
use work.gpio_regs_pkg.all;
use work.gpio_pkg.all;

entity gpio_axil_tb is
  generic (
    RUNNER_CFG : string
  );
end entity;

architecture tb of gpio_axil_tb is

  -- Clock period
  constant CLK_PERIOD : time := 10 ns;
  constant CLK_TO_Q   : time := 1 ns;

  -- Generics
  constant G_CH_MODE   : gpio_mode_arr_t(gpio_range)                 := (GPIO_MODE_OUT, GPIO_MODE_IN, GPIO_MODE_INOUT);
  constant G_CH_SYNC   : bool_arr_t                                  := (false, true, true);
  constant G_CH_DFLT_O : slv_arr_t(gpio_chan_range)(axil_data_range) := (x"000000AA", x"0000CCDD", x"00112233");
  constant G_CH_DFLT_T : slv_arr_t(gpio_chan_range)(axil_data_range) := (x"000000BB", x"0000EEFF", x"00445566");

  -- Ports
  signal clk        : std_logic := '1';
  signal srst       : std_logic := '1';
  signal irq        : std_logic;
  signal s_axil_req : axil_req_t;
  signal s_axil_rsp : axil_rsp_t;
  signal gpio_i     : slv_arr_t(gpio_chan_range)(axil_data_range);
  signal gpio_o     : slv_arr_t(gpio_chan_range)(axil_data_range);
  signal gpio_t     : slv_arr_t(gpio_chan_range)(axil_data_range);

  constant AXIM : bus_master_t := new_bus(
      data_length => AXIL_DATA_WIDTH, address_length => AXIL_ADDR_WIDTH
    );

  function fn_addr (
    idx : natural
  ) return std_logic_vector is begin
    return std_logic_vector(to_unsigned(idx * 4, AXIL_ADDR_WIDTH));
  end function;

begin

  prc_main : process is

    procedure prd_cycle (
      cnt : in positive := 1
    ) is
    begin
      for i in 0 to cnt - 1 loop
        wait until rising_edge(clk);
        wait for CLK_TO_Q;
      end loop;
    end procedure;

    variable axil_data : std_logic_vector(axil_data_range) := (others => '0');

  begin

    test_runner_setup(runner, RUNNER_CFG);

    while test_suite loop

      prd_cycle;
      srst <= '1';
      prd_cycle(16);
      srst <= '0';

      if run("test_0") then
        info("test_0");

        gpio_i <= (others => (others => '0'));

        prd_cycle(4);

        -- ---------------------------------------------------------------------
        info("Test channel 0");
        info("Check ch0 defaults");
        axil_data := G_CH_DFLT_O(0);
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_dout(0)), AXI_RSP_OKAY,
                       axil_data, "Check ch0 default out reg.");

        prd_cycle;
        check_equal(gpio_o(0), G_CH_DFLT_O(0),
                    "Check ch0 default out sig.");

        axil_data := x"00000000";
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_tri(0)), AXI_RSP_OKAY,
                       axil_data, "Check ch0 default tri reg.");

        prd_cycle;
        check_equal(gpio_t(0), axil_data,
                    "Check ch0 default tri sig.");

        check_axi_lite(net, AXIM, fn_addr(gpio_chan_din(0)), AXI_RSP_OKAY,
                       axil_data, "Check ch0 default in reg.");

        check_axi_lite(net, AXIM, fn_addr(gpio_chan_ier(0)), AXI_RSP_OKAY,
                       axil_data, "Check ch0 default irq en reg.");

        check_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(0)), AXI_RSP_OKAY,
                       axil_data, "Check ch0 irq sts reg.");

        info("Write to the ch0 interrupt enable register.");
        axil_data := x"11223344";
        write_axi_lite(net, AXIM, fn_addr(gpio_chan_ier(0)), axil_data,
                       AXI_RSP_OKAY, x"F");

        check_axi_lite(net, AXIM, fn_addr(gpio_chan_ier(0)), AXI_RSP_OKAY,
                       axil_data, "Check ch0 irq en reg after writing to it.");

        info("Write to the ch0 data out register.");
        axil_data := x"11223344";
        write_axi_lite(net, AXIM, fn_addr(gpio_chan_dout(0)), axil_data,
                       AXI_RSP_OKAY, x"F");

        axil_data := x"11223344";
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_dout(0)), AXI_RSP_OKAY,
                       axil_data, "Check ch0 out reg after writing to it.");

        prd_cycle;
        check_equal(gpio_o(0), axil_data,
                    "Check ch0 out sig after writing to it.");

        check_equal(irq, '0',
                    "Ch0 verify interrupt is not latched.");

        info("Write to the ch0 tri-state register.");
        axil_data := x"44556677";
        write_axi_lite(net, AXIM, fn_addr(gpio_chan_tri(0)), axil_data,
                       AXI_RSP_OKAY, x"F");

        axil_data := x"00000000";
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_tri(0)), AXI_RSP_OKAY,
                       axil_data, "Check ch0 tri reg after writing to it.");

        prd_cycle;
        check_equal(gpio_t(0), axil_data,
                    "Check ch0 tri sig after writing to it.");

        -- ---------------------------------------------------------------------
        info("Test channel 1");
        info("Check ch1 defaults");
        axil_data := x"00000000";
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_dout(1)), AXI_RSP_OKAY,
                       axil_data, "Check ch1 default out reg.");

        prd_cycle;
        check_equal(gpio_o(1), axil_data,
                    "Check ch1 default out sig.");

        axil_data := x"FFFFFFFF";
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_tri(1)), AXI_RSP_OKAY,
                       axil_data, "Check ch1 default tri reg.");

        prd_cycle;
        check_equal(gpio_t(1), axil_data,
                    "Check ch1 default tri sig.");

        axil_data := x"00000000";
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_din(1)), AXI_RSP_OKAY,
                       axil_data, "Check ch1 in reg.");

        check_axi_lite(net, AXIM, fn_addr(gpio_chan_ier(1)), AXI_RSP_OKAY,
                       axil_data, "Check ch1 default irq en reg.");

        check_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(1)), AXI_RSP_OKAY,
                       axil_data, "Check ch1 irq sts reg.");

        prd_cycle;
        gpio_i(1) <= x"0000FFFF";
        prd_cycle;

        axil_data := x"0000FFFF";
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_din(1)), AXI_RSP_OKAY,
                       axil_data, "Check ch1 input register after updating the input signal.");

        check_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(1)), AXI_RSP_OKAY,
                       axil_data, "Verify that interrupts were caught on ch1.");

        check_equal(irq, '0',
                    "Ch1 verify interrupt sig is not latched (interrupts disabled).");

        info("Clear ch1 interrupt register.");
        axil_data := x"0000FFFF";
        write_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(1)), axil_data,
                       AXI_RSP_OKAY, x"F");

        axil_data := x"00000000";
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(1)), AXI_RSP_OKAY,
                       axil_data, "Verify that ch1 interrupts were cleared.");

        info("Enable interrupts.");
        axil_data := x"0000FFFF";
        write_axi_lite(net, AXIM, fn_addr(gpio_chan_ier(1)), axil_data,
                       AXI_RSP_OKAY, x"F");

        info("Change the state of some of the ch1 GPIO inputs.");
        prd_cycle;
        gpio_i(1) <= x"0000F0FE";
        prd_cycle;

        axil_data := gpio_i(1);
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_din(1)), AXI_RSP_OKAY,
                       axil_data, "Check ch1 input register after updating the value of the input signal.");

        axil_data := x"0000" & not gpio_i(1)(15 downto 0);
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(1)), AXI_RSP_OKAY,
                       axil_data, "Verify that the expected interrupts were caught on ch1.");

        check_equal(irq, '1',
                    "Ch1 verify interrupt signal is latched (interrupts enabled).");

        info("Clear some (but not all) of the bits in the ch1 isr.");
        axil_data := x"0000FF00";
        write_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(1)), axil_data,
                       AXI_RSP_OKAY, x"F");

        axil_data := x"000000" & not gpio_i(1)(7 downto 0);
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(1)), AXI_RSP_OKAY,
                       axil_data, "Verify that the expected interrupts were cleared on ch1 (1).");

        check_equal(irq, '1',
                    "Ch1 verify interrupt signal is still latched (not all interrupts cleared).");

        info("Clear the rest of the bits in the ch1 isr.");
        axil_data := x"000000FF";
        write_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(1)), axil_data,
                       AXI_RSP_OKAY, x"F");

        axil_data := x"00000000";
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(1)), AXI_RSP_OKAY,
                       axil_data, "Verify that the expected interrupts were cleared on ch1 (2).");

        check_equal(irq, '0',
                    "Ch1 verify interrupt signal has been cleared.");

        -- ---------------------------------------------------------------------
        info("Test channel 2");
        info("Check ch2 defaults");
        axil_data := G_CH_DFLT_O(2);
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_dout(2)), AXI_RSP_OKAY,
                       axil_data, "Check ch2 default out reg.");

        prd_cycle;
        check_equal(gpio_o(2), axil_data,
                    "Check ch2 default out signal.");

        axil_data := G_CH_DFLT_T(2);
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_tri(2)), AXI_RSP_OKAY,
                       axil_data, "Check ch2 default tri reg.");

        prd_cycle;
        check_equal(gpio_t(2), axil_data, "Check ch2 default tri signal.");

        axil_data := x"00000000";
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_din(2)), AXI_RSP_OKAY,
                       axil_data, "Check ch2 in reg.");

        check_axi_lite(net, AXIM, fn_addr(gpio_chan_ier(2)), AXI_RSP_OKAY,
                       axil_data, "Check ch2 default irq en reg.");

        check_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(2)), AXI_RSP_OKAY,
                       axil_data, "Check ch2 irq sts reg.");

        info("Change the state of all the ch2 GPIO inputs.");
        prd_cycle;
        gpio_i(2) <= x"00FFFFFF";
        prd_cycle;

        axil_data := x"00FFFFFF";
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_din(2)), AXI_RSP_OKAY,
                       axil_data, "Check ch2 input register after updating the input signal value.");

        axil_data := x"00FFFFFF";
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(2)), AXI_RSP_OKAY,
                       axil_data, "Verify that interrupts were caught on ch2.");

        check_equal(irq, '0', "Ch2 verify interrupt signal not asserted.");

        info("Clear ch2 interrupt register.");
        axil_data := x"00FFFFFF";
        write_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(2)), axil_data,
                       AXI_RSP_OKAY, x"F");

        axil_data := x"00000000";
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(2)), AXI_RSP_OKAY,
                       axil_data, "Verify that ch2 interrupts were cleared.");

        info("Enable ch2 interrupts.");
        axil_data := x"00FFFFFF";
        write_axi_lite(net, AXIM, fn_addr(gpio_chan_ier(2)), axil_data,
                       AXI_RSP_OKAY, x"F");

        info("Change the state of some of the ch2 GPIO inputs.");
        prd_cycle;
        gpio_i(2) <= x"00ABF0FE";
        prd_cycle;

        axil_data := gpio_i(2);
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_din(2)), AXI_RSP_OKAY,
                       axil_data, "Check ch2 input register after updating value on wire.");

        axil_data := x"00" & not gpio_i(2)(23 downto 0);
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(2)), AXI_RSP_OKAY,
                       axil_data, "Verify that the expected interrupts were caught on ch2.");

        check_equal(irq, '1', "Ch2 verify interrupt signal asserted.");

        info("Clear some (but not all) of the bits in the ch2 isr.");
        axil_data := x"00FFF000";
        write_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(2)), axil_data,
                       AXI_RSP_OKAY, x"F");

        axil_data := x"00000" & not gpio_i(2)(11 downto 0);
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(2)), AXI_RSP_OKAY,
                       axil_data, "Verify that the expected interrupts were cleared on ch2 (1).");

        check_equal(irq, '1', "Ch2 verify interrupt signal still asserted.");

        info("Clear the rest of the bits in the ch2 isr.");
        axil_data := x"00000FFF";
        write_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(2)), axil_data,
                       AXI_RSP_OKAY, x"F");

        axil_data := x"00000000";
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_isr(2)), AXI_RSP_OKAY,
                       axil_data, "Verify that the expected interrupts were cleared on ch2 (2).");

        check_equal(irq, '0', "Ch2 verify interrupt signal got de-asserted.");

        info("Write the output data on GPIO ch2.");
        axil_data := x"55667788";
        write_axi_lite(net, AXIM, fn_addr(gpio_chan_dout(2)), axil_data,
                       AXI_RSP_OKAY, x"F");

        axil_data := x"55667788";
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_dout(2)), AXI_RSP_OKAY,
                       axil_data, "Check ch2 out reg after writing to it.");

        prd_cycle;
        check_equal(gpio_o(2), axil_data,
                    "Check ch2 out signal after writing to it.");

        axil_data := x"44556677";
        write_axi_lite(net, AXIM, fn_addr(gpio_chan_tri(2)), axil_data,
                       AXI_RSP_OKAY, x"0");

        axil_data := x"44556677";
        check_axi_lite(net, AXIM, fn_addr(gpio_chan_tri(2)), AXI_RSP_OKAY,
                       axil_data, "Check ch2 tri reg after writing to it.");

        prd_cycle;
        check_equal(gpio_t(2), axil_data,
                    "Check ch2 tri signal after writing to it.");

      end if;

      test_runner_cleanup(runner);

    end loop;
  end process;

  -- ---------------------------------------------------------------------------
  clk <= not clk after CLK_PERIOD / 2;

  -- ---------------------------------------------------------------------------
  u_gpio_axil : entity work.gpio_axil
  generic map (
    G_CH_MODE   => G_CH_MODE,
    G_CH_SYNC   => G_CH_SYNC,
    G_CH_DFLT_O => G_CH_DFLT_O,
    G_CH_DFLT_T => G_CH_DFLT_T
  )
  port map (
    clk        => clk,
    srst       => srst,
    irq        => irq,
    s_axil_req => s_axil_req,
    s_axil_rsp => s_axil_rsp,
    gpio_i     => gpio_i,
    gpio_o     => gpio_o,
    gpio_t     => gpio_t
  );

  -- ---------------------------------------------------------------------------
  u_axil_bfm : entity work.bfm_axil_man
  generic map (
    G_BUS_HANDLE => AXIM
  )
  port map (
    clk        => clk,
    m_axil_req => s_axil_req,
    m_axil_rsp => s_axil_rsp
  );

end architecture;
