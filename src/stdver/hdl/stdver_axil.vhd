--##############################################################################
--# File : stdver_axil.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! Standard Version module. These Registers
--! should be instantiated at the base address of every FPGA design.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.util_pkg.all;
use work.stdver_regs_pkg.all;
use work.stdver_register_record_pkg.all;

entity stdver_axil is
  generic (
    G_DEVICE_ID   : std_logic_vector(31 downto 0) := x"DEAD_BEEF";
    G_VER_MAJOR   : natural range 0 to 255        := 0;
    G_VER_MINOR   : natural range 0 to 255        := 1;
    G_VER_PATCH   : natural range 0 to 255        := 0;
    G_LOCAL_BUILD : boolean                       := true;
    G_DEV_BUILD   : boolean                       := true;
    G_BUILD_DATE  : std_logic_vector(31 downto 0) := x"DEAD_BEEF";
    G_BUILD_TIME  : std_logic_vector(23 downto 0) := x"DE_BEEF";
    G_GIT_HASH    : std_logic_vector(31 downto 0) := x"DEAD_BEEF";
    G_GIT_DIRTY   : boolean                       := true
  );
  port (
    clk  : in    std_logic;
    srst : in    std_logic;
    --
    s_axil_req : in    axil_req_t;
    s_axil_rsp : out   axil_rsp_t
  );
end entity;

architecture rtl of stdver_axil is

  -- ---------------------------------------------------------------------------
  signal i            : stdver_regs_up_t         := stdver_regs_up_init;
  signal o            : stdver_regs_down_t       := stdver_regs_down_init;
  signal r            : stdver_reg_was_read_t    := stdver_reg_was_read_init;
  signal w            : stdver_reg_was_written_t := stdver_reg_was_written_init;

begin

  -- ---------------------------------------------------------------------------
  u_stdver_reg_file : entity work.stdver_register_file_axi_lite
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
  i.id.id           <= unsigned(G_DEVICE_ID);
  i.version.dirty   <= '1' when G_GIT_DIRTY = true else '0';
  i.version.local   <= '1' when G_LOCAL_BUILD = true else '0';
  i.version.dev     <= '1' when G_DEV_BUILD = true else '0';
  i.version.major   <= G_VER_MAJOR;
  i.version.minor   <= G_VER_MINOR;
  i.version.patch   <= G_VER_PATCH;
  i.date.year       <= unsigned(G_BUILD_DATE(31 downto 16));
  i.date.month      <= unsigned(G_BUILD_DATE(15 downto 8));
  i.date.day        <= unsigned(G_BUILD_DATE(7 downto 0));
  i.time.hour       <= unsigned(G_BUILD_TIME(23 downto 16));
  i.time.minute     <= unsigned(G_BUILD_TIME(15 downto 8));
  i.time.second     <= unsigned(G_BUILD_TIME(7 downto 0));
  i.githash.githash <= unsigned(G_GIT_HASH);

end architecture;
