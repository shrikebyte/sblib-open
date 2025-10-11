--##############################################################################
--# File : ram.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! Vendor agnostic read-first bram generator. Can be used as a tdpr, sdpr,
--! spr, rom, etc. Just leave unused ports disconnected.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util_pkg.all;

entity ram is
  generic (
    --! Number of "bytes" per addressable ram element; Each "byte" can be 
    --! exclusively written; Set to 1 if individual bytes within each memory
    --! word do not need to be exclusively written.
    --! Typically this generic is set in conjunction with G_BYTE_WIDTH when
    --! byte write granularity is required. For example: a RAM with 32 bit
    --! words and byte writes would set G_BYTES_PER_ROW=4 and G_BYTE_WIDTH=8.
    --! If byte writes are not required for the same 32 bit RAM, then
    --! G_BYTES_PER_ROW=1 and G_BYTE_WIDTH=32
    G_BYTES_PER_ROW : integer range 1 to 64 := 4;

    --! Bit width of each "byte." "Byte" is in quotations because it does not
    --! necessarily mean 8 bits in this context (but this would typically be
    --! set to 8 if interfacing with a microprocessor).
    G_BYTE_WIDTH : integer range 1 to 64 := 8;

    --! Log base 2 of the memory depth; ie: total size of the memory in bits =
    --! (2**G_ADDR_WIDTH) * (G_BYTES_PER_ROW * G_BYTE_WIDTH)
    G_ADDR_WIDTH : positive := 10;

    --! Ram synthesis attribute; Will suggest the style of memory to the
    --! synthesizer but if other generics are set in a way that is
    --! incompatible with the suggested memory type, then the synthesizer
    --! will make the final style decision.
    --! If this generic is left blank or if an unknown string is passed in,
    --! then the synthesizer will decide what to do.
    --! See Xilinx UG901 - Vivado Synthesis for more information on dedicated
    --! BRAMs.
    --! Options: "auto", "block", "ultra", "distributed", "registers"
    G_RAM_STYLE : string := "auto";

    --! Data to initialize the ram with at FPGA startup. Only compatible with
    --! SRAM-based FPGAs.
    G_RAM_INIT : slv_arr_t(0 to (2 ** G_ADDR_WIDTH) - 1)(G_BYTES_PER_ROW * G_BYTE_WIDTH - 1 downto 0) := (others=> (others=> '0'));

    --! Read latency
    G_RD_LATENCY : positive := 1
  );
  port (
    a_clk  : in    std_logic                                                     := '0';
    a_en   : in    std_logic                                                     := '1';
    a_wen  : in    std_logic_vector(G_BYTES_PER_ROW - 1 downto 0)                := (others=> '0');
    a_addr : in    std_logic_vector(G_ADDR_WIDTH - 1 downto 0)                   := (others=> '0');
    a_wdat : in    std_logic_vector(G_BYTES_PER_ROW * G_BYTE_WIDTH - 1 downto 0) := (others=> '0');
    a_rdat : out   std_logic_vector(G_BYTES_PER_ROW * G_BYTE_WIDTH - 1 downto 0);
    b_clk  : in    std_logic                                                     := '0';
    b_en   : in    std_logic                                                     := '1';
    b_wen  : in    std_logic_vector(G_BYTES_PER_ROW - 1 downto 0)                := (others=> '0');
    b_addr : in    std_logic_vector(G_ADDR_WIDTH - 1 downto 0)                   := (others=> '0');
    b_wdat : in    std_logic_vector(G_BYTES_PER_ROW * G_BYTE_WIDTH - 1 downto 0) := (others=> '0');
    b_rdat : out   std_logic_vector(G_BYTES_PER_ROW * G_BYTE_WIDTH - 1 downto 0)
  );
end entity;

architecture rtl of ram is

  -- ---------------------------------------------------------------------------
  constant DATA_WIDTH : integer := G_BYTES_PER_ROW * G_BYTE_WIDTH;

  -- ---------------------------------------------------------------------------
  signal a_idx  : natural range 0 to 2 ** G_ADDR_WIDTH - 1;
  signal b_idx  : natural range 0 to 2 ** G_ADDR_WIDTH - 1;
  signal a_pipe : slv_arr_t(0 to G_RD_LATENCY - 1)(DATA_WIDTH - 1 downto 0);
  signal b_pipe : slv_arr_t(0 to G_RD_LATENCY - 1)(DATA_WIDTH - 1 downto 0);
  signal ram    : slv_arr_t(0 to 2 ** G_ADDR_WIDTH - 1)(DATA_WIDTH - 1 downto 0) := G_RAM_INIT;

  -- ---------------------------------------------------------------------------
  attribute ram_style : string;
  attribute ram_style of ram : signal is G_RAM_STYLE;

begin

  a_idx  <= to_integer(unsigned(a_addr));
  b_idx  <= to_integer(unsigned(b_addr));

  -- ---------------------------------------------------------------------------
  -- Notice that this process is sensitive to both clocks. Somewhat non-standard
  -- but it works for implementing a tdpr without a shared variable, making it
  -- compliant with VHDL 08.
  prc_ram : process (a_clk, b_clk) is begin

    -- -------------------------------------------------------------------------
    -- Port A
    if rising_edge(a_clk) then
      if a_en then

        for i in 0 to G_BYTES_PER_ROW - 1 loop
          if a_wen(i) then
            ram(a_idx)(i * G_BYTE_WIDTH + G_BYTE_WIDTH - 1 downto i * G_BYTE_WIDTH) <=
              a_wdat(i * G_BYTE_WIDTH + G_BYTE_WIDTH - 1 downto i * G_BYTE_WIDTH);
          end if;
        end loop;

        a_pipe(0) <= ram(a_idx);
        a_pipe(1 to G_RD_LATENCY - 1) <= a_pipe(0 to G_RD_LATENCY - 2);

      end if;
    end if;

    -- -------------------------------------------------------------------------
    -- Port B
    if rising_edge(b_clk) then
      if b_en then

        for i in 0 to G_BYTES_PER_ROW - 1 loop
          if b_wen(i) then
            ram(b_idx)(i * G_BYTE_WIDTH + G_BYTE_WIDTH - 1 downto i * G_BYTE_WIDTH) <=
              b_wdat(i * G_BYTE_WIDTH + G_BYTE_WIDTH - 1 downto i * G_BYTE_WIDTH);
          end if;
        end loop;

        b_pipe(0) <= ram(b_idx);
        b_pipe(1 to G_RD_LATENCY - 1) <= b_pipe(0 to G_RD_LATENCY - 2);

      end if;
    end if;

  end process;

  a_rdat <= a_pipe(G_RD_LATENCY - 1);
  b_rdat <= b_pipe(G_RD_LATENCY - 1);

end architecture;
