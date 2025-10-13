--##############################################################################
--# File : strm_switch.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! Stream switch
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;

entity strm_switch is
  generic (
    G_NUM_OUTPUTS : positive := 2;
    G_DATA_WIDTH  : positive := 8
  );
  port (
    clk  : in    std_logic;
    srst : in    std_logic;
    --
    s_valid : in    std_logic;
    s_ready : out   std_logic;
    s_data  : in    std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    --
    m_valid : out   sl_arr_t(0 to G_NUM_OUTPUTS - 1);
    m_ready : in    sl_arr_t(0 to G_NUM_OUTPUTS - 1);
    m_data  : out   slv_arr_t(0 to G_NUM_OUTPUTS - 1)(G_DATA_WIDTH - 1 downto 0)
  );
end entity;

architecture rtl of strm_switch is

begin

end architecture;
