--##############################################################################
--# File : strm_arbiter.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! Stream arbiter
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;

entity strm_arbiter is
  generic (
    G_NUM_INPUTS : positive := 2;
    G_DATA_WIDTH : positive := 8
  );
  port (
    clk  : in    std_logic;
    srst : in    std_logic;
    --
    s_valid : in    sl_arr_t(0 to G_NUM_INPUTS - 1);
    s_ready : out   sl_arr_t(0 to G_NUM_INPUTS - 1);
    s_data  : in    slv_arr_t(0 to G_NUM_INPUTS - 1)(G_DATA_WIDTH - 1 downto 0);
    --
    m_valid : out   std_logic;
    m_ready : in    std_logic;
    m_data  : out   std_logic_vector(G_DATA_WIDTH - 1 downto 0)
  );
end entity;

architecture rtl of strm_arbiter is

begin

end architecture;
