--#############################################################################
--# File : cdc_grey.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ==========================================================================
--! Gray code counter synchronizer. The 'src_cnt' input may only increment by
--! one, decrement by one, or remain the same on each clock cycle to ensure
--! that the count is reliably transferred.
--#############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;

entity cdc_gray is
  generic (
    G_SYNC_LEN : positive := 2;
    G_OUT_REG  : boolean  := false
  );
  port (
    src_clk : in    std_ulogic;
    src_cnt : in    u_unsigned;
    dst_clk : in    std_ulogic;
    dst_cnt : out   u_unsigned
  );
end entity;

architecture rtl of cdc_gray is

  signal src_gray : std_ulogic_vector(src_cnt'length - 1 downto 0);
  signal dst_gray : std_ulogic_vector(src_cnt'length - 1 downto 0);

begin

  -- ---------------------------------------------------------------------------
  u_cdc_bit : entity work.cdc_bit
  generic map (
    G_USE_SRC_REG => true,
    G_SYNC_LEN    => G_SYNC_LEN,
    G_WIDTH       => src_cnt'length
  )
  port map (
    src_clk => src_clk,
    src_bit => src_gray,
    dst_clk => dst_clk,
    dst_bit => dst_gray
  );

  src_gray <= bin_to_gray(src_cnt);

  -- ---------------------------------------------------------------------------
  gen_out_reg : if G_OUT_REG generate

    prc_out_reg : process (dst_clk) is begin
      if rising_edge(dst_clk) then
        dst_cnt <= gray_to_bin(dst_gray);
      end if;
    end process;

  else generate

    dst_cnt <= gray_to_bin(dst_gray);

  end generate;

end architecture;
