--##############################################################################
--# File : util_pkg.vhd
--# Auth : David Gussler
--# Lang : VHDL '08
--# ============================================================================
--! General library utilities package
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

package util_pkg is

  -- ---------------------------------------------------------------------------
  -- AXI Lite
  constant AXIL_DATA_WIDTH : integer := 32;
  constant AXIL_ADDR_WIDTH : integer := 32;

  subtype axil_data_range is natural range AXIL_DATA_WIDTH - 1 downto 0;

  subtype axil_addr_range is natural range AXIL_ADDR_WIDTH - 1 downto 0;

  subtype axil_strb_range is natural range AXIL_DATA_WIDTH / 8 - 1 downto 0;

  subtype axil_prot_range is natural range 2 downto 0;

  subtype axil_resp_range is natural range 1 downto 0;

  constant AXI_RSP_OKAY   : std_logic_vector(AXIL_RESP_RANGE) := b"00";
  constant AXI_RSP_EXOKAY : std_logic_vector(AXIL_RESP_RANGE) := b"01";
  constant AXI_RSP_SLVERR : std_logic_vector(AXIL_RESP_RANGE) := b"10";
  constant AXI_RSP_DECERR : std_logic_vector(AXIL_RESP_RANGE) := b"11";

  type axil_req_t is record
    awvalid : std_logic;
    awprot  : std_logic_vector(AXIL_PROT_RANGE);
    awaddr  : std_logic_vector(AXIL_ADDR_RANGE);
    wvalid  : std_logic;
    wdata   : std_logic_vector(AXIL_DATA_RANGE);
    wstrb   : std_logic_vector(AXIL_STRB_RANGE);
    bready  : std_logic;
    arvalid : std_logic;
    arprot  : std_logic_vector(AXIL_PROT_RANGE);
    araddr  : std_logic_vector(AXIL_ADDR_RANGE);
    rready  : std_logic;
  end record;

  type axil_rsp_t is record
    awready : std_logic;
    wready  : std_logic;
    bvalid  : std_logic;
    bresp   : std_logic_vector(AXIL_RESP_RANGE);
    arready : std_logic;
    rvalid  : std_logic;
    rdata   : std_logic_vector(AXIL_DATA_RANGE);
    rresp   : std_logic_vector(AXIL_RESP_RANGE);
  end record;

  type axil_req_arr_t is array (natural range <>) of axil_req_t;

  type axil_rsp_arr_t is array (natural range <>) of axil_rsp_t;

  -- ---------------------------------------------------------------------------
  -- Wishbone (Non-pipelined)

  type wb_req_t is record
    stb  : std_logic;
    wen  : std_logic;
    addr : std_logic_vector(AXIL_ADDR_RANGE);
    wdat : std_logic_vector(AXIL_DATA_RANGE);
    wsel : std_logic_vector(AXIL_STRB_RANGE);
  end record;

  type wb_rsp_t is record
    ack  : std_logic;
    err  : std_logic;
    rdat : std_logic_vector(AXIL_DATA_RANGE);
  end record;

  type wb_req_arr_t is array (natural range <>) of wb_req_t;

  type wb_rsp_arr_t is array (natural range <>) of wb_rsp_t;

  -- ---------------------------------------------------------------------------
  -- Advanced Peripheral Bus
  type apb_req_t is record
    psel    : std_logic;
    penable : std_logic;
    pwrite  : std_logic;
    pprot   : std_logic_vector(AXIL_PROT_RANGE);
    paddr   : std_logic_vector(AXIL_ADDR_RANGE);
    pwdata  : std_logic_vector(AXIL_DATA_RANGE);
    pstrb   : std_logic_vector(AXIL_STRB_RANGE);
  end record;

  type apb_rsp_t is record
    prdata  : std_logic_vector(AXIL_DATA_RANGE);
    pready  : std_logic;
    pslverr : std_logic;
  end record;

  type apb_req_arr_t is array (natural range <>) of apb_req_t;

  type apb_rsp_arr_t is array (natural range <>) of apb_rsp_t;

  -- ---------------------------------------------------------------------------
  -- Register Bus
  -- ..This is a simple bus interface for basic components that don't need
  -- most of the features offered by busses like axi, but
  -- still require higher performance than can be offered by busses like apb.
  -- Read and write channels can operate independently.
  -- Slave is expected to always respond in a fixed number of cycles that is
  -- known by the master.
  -- Full duplex communication at 1 transfer per cycle for maximum bandwidth.
  -- Recommended to use this for user logic and connect to an axil adaptor for
  -- external pipelining and interconnect logic.
  type reg_req_t is record
    ren   : std_logic;
    raddr : std_logic_vector(AXIL_ADDR_RANGE);
    wen   : std_logic;
    waddr : std_logic_vector(AXIL_ADDR_RANGE);
    wstrb : std_logic_vector(AXIL_STRB_RANGE);
    wdata : std_logic_vector(AXIL_DATA_RANGE);
  end record;

  type reg_rsp_t is record
    rdata : std_logic_vector(AXIL_DATA_RANGE);
    rerr  : std_logic;
    werr  : std_logic;
  end record;

  type reg_req_arr_t is array (natural range <>) of reg_req_t;

  type reg_rsp_arr_t is array (natural range <>) of reg_rsp_t;

  -- ---------------------------------------------------------------------------
  -- Transaction type
  type bus_cmd_t is (BUS_WRITE, BUS_CHECK);

  type bus_xact_t is record
    cmd   : bus_cmd_t;
    wstrb : std_logic_vector(AXIL_STRB_RANGE);
    addr  : std_logic_vector(AXIL_ADDR_RANGE);
    data  : std_logic_vector(AXIL_DATA_RANGE);
    mask  : std_logic_vector(AXIL_DATA_RANGE);
  end record;

  type bus_xact_arr_t is array (natural range <>) of bus_xact_t;

  -- ---------------------------------------------------------------------------
  -- Array types
  type sl_arr_t is array (natural range <>) of std_logic;

  type slv_arr_t is array (natural range <>) of std_logic_vector;

  type unsigned_arr_t is array (natural range <>) of u_unsigned;
  type signed_arr_t is array (natural range <>) of u_signed;

  type int_arr_t is array (natural range <>) of integer;

  type pos_arr_t is array (natural range <>) of positive;

  type nat_arr_t is array (natural range <>) of natural;

  type bool_arr_t is array (natural range <>) of boolean;

  type string_arr_t is array (natural range <>) of string;

  -- ---------------------------------------------------------------------------
  -- Functions
  function cnt_ones (
    vec : std_logic_vector
  ) return natural;

  function cnt_ones (
    vec : u_unsigned
  ) return natural;

  function cnt_ones_contig (
    vec : std_ulogic_vector
  ) return natural;

  function is_contig(
    vec : std_ulogic_vector
  ) return boolean;

  function is_onehot (
    vec : std_logic_vector
  ) return boolean;

  function is_onehot (
    vec : std_logic_vector
  ) return std_logic;

  function bin_to_gray (
    bin : std_logic_vector
  ) return std_logic_vector;

  function gray_to_bin (
    gray : std_logic_vector
  ) return std_logic_vector;

  function clog2 (
    value : positive
  ) return natural;

  function is_pwr2 (
    value : positive
  ) return boolean;

  function find_hi_idx (
    vec : std_logic_vector
  ) return natural;

  function find_lo_idx (
    vec : std_logic_vector
  ) return natural;

  function to_sl (val : boolean) return std_ulogic;
  function to_sl(val : natural range 0 to 1) return std_ulogic;
  function to_int(val : std_ulogic) return integer;
  function to_int(val : boolean) return integer;
  function to_bool(val : std_ulogic) return boolean;
  function to_bool(val : natural range 0 to 1) return boolean;

  function find_max (
    arr : int_arr_t
  ) return integer;

  function find_min (
    arr : int_arr_t
  ) return integer;

  function find_max (
    arr : nat_arr_t
  ) return integer;

  function find_min (
    arr : nat_arr_t
  ) return integer;

  function find_max (
    arr : pos_arr_t
  ) return integer;

  function find_min (
    arr : pos_arr_t
  ) return integer;

  function expand_bits(
    vec : std_ulogic_vector;
    N : positive
  ) return std_ulogic_vector;

  function contract_bits(
    vec : std_ulogic_vector;
    N : positive
  ) return std_ulogic_vector;

end package;

package body util_pkg is

  -- ---------------------------------------------------------------------------
  -- Count the number of ones in a vector.
  function cnt_ones (
    vec : std_logic_vector
  ) return natural is
    variable tmp : natural := 0;
  begin
    for i in vec'range loop
      if vec(i) = '1' then
        tmp := tmp + 1;
      end if;
    end loop;
    return tmp;
  end function;

  function cnt_ones (
    vec : u_unsigned
  ) return natural is
    variable tmp : natural := 0;
  begin
    for i in vec'range loop
      if vec(i) = '1' then
        tmp := tmp + 1;
      end if;
    end loop;
    return tmp;
  end function;

  -- ---------------------------------------------------------------------------
  -- Optimized version of cnt_ones that assumes input bits are
  -- contiguous from low to high.
  function cnt_ones_contig (
    vec : std_ulogic_vector
  ) return natural is
    constant VEC_LEN : natural := vec'length;
    variable vec_norm : std_ulogic_vector(VEC_LEN - 1 downto 0);
    variable result  : natural := 0;
  begin
    vec_norm := vec;
    for i in 0 to VEC_LEN - 1 loop
      if vec_norm(i) then
        result := i + 1;
      end if;
    end loop;
    return result;
  end function;

  -- Return true if a vector has contiguous ones from low to high.
  function is_contig(vec : std_ulogic_vector) return boolean is
    variable saw_zero : boolean := false;
  begin
    for i in vec'low to vec'high loop
      if vec(i) = '0' then
        saw_zero := true;
      elsif saw_zero then
        return false;
      end if;
    end loop;
    return true;
  end function;

  -- ---------------------------------------------------------------------------
  -- Return true if the vector has only one bit set to 1, otherwise false
  function is_onehot (
    vec : std_logic_vector
  ) return boolean is
    variable tmp : boolean := false;
  begin
    for i in vec'range loop
      if vec(i) = '1' and tmp = false then
        tmp := true;
      elsif vec(i) = '1' and tmp = true then
        return false;
      end if;
    end loop;
    return tmp;
  end function;

  -- ---------------------------------------------------------------------------
  -- Return 1 if the vector has only one bit set to 1, otherwise 0
  function is_onehot (
    vec : std_logic_vector
  ) return std_logic is
    variable tmp : std_logic := '0';
  begin
    for i in vec'range loop
      if vec(i) = '1' and tmp = '0' then
        tmp := '1';
      elsif vec(i) = '1' and tmp = '1' then
        return '0';
      end if;
    end loop;
    return tmp;
  end function;

  -- ---------------------------------------------------------------------------
  -- Convert a binary coded number to a gray coded number
  function bin_to_gray (
    bin : std_logic_vector
  ) return std_logic_vector is
    variable gray : std_logic_vector(bin'range);
  begin
    gray(gray'high) := bin(gray'high);
    for i in gray'high - 1 downto 0 loop
      gray(i) := bin(i + 1) xor bin(i);
    end loop;
    return gray;
  end function;

  -- ---------------------------------------------------------------------------
  -- Convert a gray coded number to a binary coded number
  function gray_to_bin (
    gray : std_logic_vector
  ) return std_logic_vector is
    variable bin : std_logic_vector(gray'range);
  begin
    bin(gray'high) := gray(gray'high);
    for i in gray'high - 1 downto 0 loop
      bin(i) := bin(i + 1) xor gray(i);
    end loop;
    return bin;
  end function;

  -- ---------------------------------------------------------------------------
  -- 2-base logarithm rounded up. This should only be used in testbenches or to
  -- calculate compile-time values.
  function clog2 (
    value : positive
  ) return natural is
  begin
    return natural(ceil(log2(real(value))));
  end function;

  -- ---------------------------------------------------------------------------
  -- Return true if input is a power of two. Otherwise false.
  function is_pwr2 (
    value : positive
  ) return boolean is
  begin
    return is_onehot(std_logic_vector(to_unsigned(value, 32)));
  end function;

  -- ---------------------------------------------------------------------------
  -- Find the left-most index of an slv that is '1'. If no match, return
  -- left-most idx.
  function find_hi_idx (
    vec : std_logic_vector
  ) return natural is
  begin
    for i in vec'high downto vec'low loop
      if vec(i) then
        return i;
      end if;
    end loop;
    return vec'high;
  end function;

  -- ---------------------------------------------------------------------------
  -- Find the right-most index of an slv that is '1'. If no match, return
  -- left-most idx.
  function find_lo_idx (
    vec : std_logic_vector
  ) return natural is
  begin
    for i in vec'low to vec'high loop
      if vec(i) then
        return i;
      end if;
    end loop;
    return vec'high;
  end function;

  -- ---------------------------------------------------------------------------
  -- Convert a boolean to standard logic
  function to_sl(val : boolean) return std_ulogic is
  begin
    if val then
      return '1';
    end if;
    return '0';
  end function;

  function to_sl(val : natural range 0 to 1) return std_ulogic is
  begin
    if val = 1 then
      return '1';
    end if;
    return '0';
  end function;

  function to_int(val : std_ulogic) return integer is
  begin
    if val = '1' then
      return 1;
    else
      return 0;
    end if;
  end function;

  function to_int(val : boolean) return integer is
  begin
    if val = true then
      return 1;
    else
      return 0;
    end if;
  end function;

  function to_bool(val : std_ulogic) return boolean is
  begin
    if val = '1' then
      return true;
    end if;
    return false;
  end function;

  function to_bool(val : natural range 0 to 1) return boolean is
  begin
    return val = 1;
  end function;

  -- ---------------------------------------------------------------------------
  -- Find the max value of an integer array
  function find_max (
    arr : int_arr_t
  ) return integer is
    variable rtn : integer := arr(arr'low);
  begin
    for i in arr'range loop
      if arr(i) > rtn then
        rtn := arr(i);
      end if;
    end loop;
    return rtn;
  end function;

  -- ---------------------------------------------------------------------------
  -- Find the min value of an integer array
  function find_min (
    arr : int_arr_t
  ) return integer is
    variable rtn : integer := arr(arr'low);
  begin
    for i in arr'range loop
      if arr(i) < rtn then
        rtn := arr(i);
      end if;
    end loop;
    return rtn;
  end function;

  function find_max (
    arr : nat_arr_t
  ) return integer is
    variable rtn : integer := arr(arr'low);
  begin
    for i in arr'range loop
      if arr(i) > rtn then
        rtn := arr(i);
      end if;
    end loop;
    return rtn;
  end function;

  function find_min (
    arr : nat_arr_t
  ) return integer is
    variable rtn : integer := arr(arr'low);
  begin
    for i in arr'range loop
      if arr(i) < rtn then
        rtn := arr(i);
      end if;
    end loop;
    return rtn;
  end function;

  function find_max (
    arr : pos_arr_t
  ) return integer is
    variable rtn : integer := arr(arr'low);
  begin
    for i in arr'range loop
      if arr(i) > rtn then
        rtn := arr(i);
      end if;
    end loop;
    return rtn;
  end function;

  function find_min (
    arr : pos_arr_t
  ) return integer is
    variable rtn : integer := arr(arr'low);
  begin
    for i in arr'range loop
      if arr(i) < rtn then
        rtn := arr(i);
      end if;
    end loop;
    return rtn;
  end function;


  function expand_bits(
    vec : std_ulogic_vector;
    N : positive
  ) return std_ulogic_vector is
    constant VEC_LEN : natural := vec'length;
    constant OUT_LEN : natural := VEC_LEN * N;
    variable result  : std_ulogic_vector(OUT_LEN - 1 downto 0);
    variable vec_norm : std_ulogic_vector(VEC_LEN - 1 downto 0);
  begin
    vec_norm := vec;

    for i in 0 to VEC_LEN - 1 loop
      for j in 0 to N - 1 loop
        result((i * N) + j) := vec_norm(i);
      end loop;
    end loop;

    return result;
  end function;

  function contract_bits(
    vec : std_ulogic_vector;
    N : positive
  ) return std_ulogic_vector is
    constant VEC_LEN : natural := vec'length;
    constant OUT_LEN : natural := VEC_LEN / N;
    variable result  : std_ulogic_vector(OUT_LEN - 1 downto 0);
    variable vec_norm : std_ulogic_vector(VEC_LEN - 1 downto 0);
  begin
    assert (VEC_LEN mod N) = 0
      report "contract_bits: Vector length must be divisible by N."
      severity failure;

    vec_norm := vec;

    for i in 0 to OUT_LEN - 1 loop
      result(i) := vec_norm(i * N);
    end loop;

    return result;
  end function;

end package body;
