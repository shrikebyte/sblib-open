--##############################################################################
--# File : axis_pkg.vhd
--# Auth : David Gussler
--# Lang : VHDL'19
--# ============================================================================
--! AXIS type definitions
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package axis_pkg is

  -- AXI-Stream type
  type axis_t is record
    tready     : std_ulogic;
    tvalid     : std_ulogic;
    tlast      : std_ulogic;
    tdata      : std_ulogic_vector;
    tkeep      : std_ulogic_vector;
    tuser      : std_ulogic_vector;
  end record;

  -- AXI-Stream array
  type axis_arr_t is array (natural range <>) of axis_t;

  -- Manager view
	view m_axis_v of axis_t is
    tready : in;
    tvalid : out;
    tlast  : out;
    tdata  : out;
    tkeep  : out;
    tuser  : out;
  end view;

  -- Subordinate view
  alias s_axis_v is m_axis_v'converse;

  -- Debug view
  view d_axis_v of axis_t is
    tready : in;
    tvalid : in;
    tlast  : in;
    tdata  : in;
    tkeep  : in;
    tuser  : in;
  end view;

end package;
