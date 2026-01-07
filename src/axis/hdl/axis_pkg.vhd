--##############################################################################
--# File : axis_pkg.vhd
--# Auth : David Gussler
--# ============================================================================
--# Shrikebyte VHDL Library - https://github.com/shrikebyte/sblib
--# Copyright (C) Shrikebyte, LLC
--# Licensed under the Apache 2.0 license, see LICENSE for details.
--# ============================================================================
--# AXI-Stream type definitions.
--##############################################################################

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package axis_pkg is

  -- AXI-Stream type
  type axis_t is record
    tready : std_ulogic;
    tvalid : std_ulogic;
    tlast  : std_ulogic;
    tkeep  : std_ulogic_vector;
    tdata  : std_ulogic_vector;
    tuser  : std_ulogic_vector;
  end record;

  -- AXI-Stream array
  type axis_arr_t is array(natural range <>) of axis_t;

  -- Manager view
	view m_axis_v of axis_t is
    tready : in;
    tvalid : out;
    tlast  : out;
    tkeep  : out;
    tdata  : out;
    tuser  : out;
  end view;

  -- Subordinate view
  alias s_axis_v is m_axis_v'converse;

  -- Monitor view
  view mon_axis_v of axis_t is
    tready : in;
    tvalid : in;
    tlast  : in;
    tkeep  : in;
    tdata  : in;
    tuser  : in;
  end view;

  procedure axis_attach (
    signal s_axis : view s_axis_v of axis_t;
    signal m_axis : view m_axis_v of axis_t
  );

  procedure axis_attach (
    signal s_axis : view (s_axis_v) of axis_arr_t;
    signal m_axis : view (m_axis_v) of axis_arr_t
  );

end package;

package body axis_pkg is

  procedure axis_attach (
    signal s_axis : view s_axis_v of axis_t;
    signal m_axis : view m_axis_v of axis_t
  ) is
  begin
    s_axis.tready <= m_axis.tready;
    m_axis.tvalid <= s_axis.tvalid;
    m_axis.tlast  <= s_axis.tlast ; 
    m_axis.tkeep  <= s_axis.tkeep ; 
    m_axis.tdata  <= s_axis.tdata ; 
    m_axis.tuser  <= s_axis.tuser ; 
  end procedure;

  procedure axis_attach (
    signal s_axis : view (s_axis_v) of axis_arr_t;
    signal m_axis : view (m_axis_v) of axis_arr_t
  ) is
  begin
    for i in s_axis'range loop
      axis_attach(s_axis(i), m_axis(i));
    end loop;
  end procedure;

end package body;
