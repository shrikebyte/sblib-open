--##############################################################################
--# File : iserdes_4x_model.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! Simulation model of a 1:4 input deserializer
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;

entity iserdes_4x_model is
  port (
    clk_2x : in    std_logic;
    clk_1x : in    std_logic;
    d      : in    std_logic;
    q      : out   std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of iserdes_4x_model is

  signal dp   : std_logic;
  signal dn   : std_logic;
  signal q1   : std_logic;
  signal q2   : std_logic;
  signal q1ff : std_logic;
  signal q2ff : std_logic;
  signal q1f2 : std_logic;
  signal q2f2 : std_logic;

begin

  prc_0 : process (clk_2x) is begin
    if rising_edge(clk_2x) then
      dp <= d;
    end if;
  end process;

  prc_1 : process (clk_2x) is begin
    if falling_edge(clk_2x) then
      dn <= d;
    end if;
  end process;

  prc_2 : process (clk_2x) is begin
    if rising_edge(clk_2x) then
      q1 <= dp;
      q2 <= dn;
    end if;
  end process;

  prc_3 : process (clk_2x) is begin
    if rising_edge(clk_2x) then
      q1ff <= q1;
      q2ff <= q2;
      q1f2 <= q1ff;
      q2f2 <= q2ff;
    end if;
  end process;

  prc_4 : process (clk_1x) is begin
    if rising_edge(clk_1x) then
      q <= q2ff & q1ff & q2f2 & q1f2;
    end if;
  end process;

end architecture;
