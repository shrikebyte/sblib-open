-- -------------------------------------------------------------------------------------------------
-- Copyright (c) Lukas Vik. All rights reserved.
--
-- This file is part of the hdl-modules project, a collection of reusable, high-quality,
-- peer-reviewed VHDL building blocks.
-- https://hdl-modules.com
-- https://github.com/hdl-modules/hdl-modules
-- -------------------------------------------------------------------------------------------------
-- Check that an AXI-Stream-like handshaking bus is compliant with the AXI-Stream standard.
-- Will perform the following checks at each rising clock edge:
--
-- 1. The handshake signals ``ready`` and ``valid`` must be well-defined
--    (not ``'X'``, ``'-'``, etc).
-- 2. ``valid`` must not fall without a transaction (``ready and valid``).
-- 3. No payload on the bus may change while ``valid`` is asserted, unless there is a transaction.
-- 4. ``strobe`` must be well-defined when ``valid`` is asserted.
--
-- If any rule violation is detected, an assertion will be triggered.
-- Use the ``logger_name_suffix`` generic to customize the error message.
--
-- .. note::
--
--   This entity can be instantiated in simulation code as well as in synthesis code.
--   The code is simple and will be stripped by synthesis.
--   Can be useful to check the behavior of a stream that is deep in a hierarchy.
--
--
-- Comparison to VUnit checker
-- ___________________________
--
-- This entity was created as a lightweight and synthesizable alternative to the VUnit AXI-Stream
-- protocol checker (``axi_stream_protocol_checker.vhd``).
-- The VUnit checker is clearly more powerful and has more features, but it also consumes a lot more
-- CPU cycles when simulating.
-- One testbench in this project that uses five protocol checkers decreased its execution time by
-- 45% when switching to this protocol checker instead.
--
-- Compared to the VUnit checker, this entity is missing these features:
--
-- 1. Checking for undefined bits in payload fields.
-- 2. Checking that all started packets finish with a proper ``last``.
-- 3. Performance checking that ``ready`` is asserted within a certain number of cycles.
-- 4. Logger support. Meaning, it is not possible to mock or disable the checks in this entity.
-- -------------------------------------------------------------------------------------------------

library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.axis_pkg.all;
use work.bfm_pkg.all;

entity bfm_axis_protocol_check is
  generic (
    -- Suffix for error log messages. Can be used to differentiate between
    -- multiple instances.
    G_LOGGER_NAME_SUFFIX : string := "";
    -- Time to wait after rising edge of clock before checking data
    G_CLK_TO_Q : time := 0.1 ns
  );
  port (
    clk  : in    std_ulogic;
    srst : in    std_ulogic := '0';
    --
    mon_axis : view monitor_axis_v
  );
end entity;

architecture sim of bfm_axis_protocol_check is

  constant DW : integer := mon_axis.tdata'length;
  constant KW : integer := mon_axis.tkeep'length;
  constant UW : integer := mon_axis.tuser'length;

  constant BASE_ERROR_MESSAGE : string := "bfm_axis_protocol_check - " &
    G_LOGGER_NAME_SUFFIX & ": ";

  function get_unstable_error_message (
    signal_name : string
  ) return string is
  begin
    return BASE_ERROR_MESSAGE & "'" & signal_name
      & "' changed without transaction while bus was 'valid'.";
  end function;

  signal bus_must_be_same_as_previous : std_ulogic := '0';

begin

  -- ---------------------------------------------------------------------------

  blk_tready_well_defined : block is

    constant ERROR_MESSAGE : string := BASE_ERROR_MESSAGE &
      "'tready' has undefined value.";

  begin

    -- -------------------------------------------------------------------------
    prc_tready_well_defined_check : process is begin
      wait until rising_edge(clk);
      wait for G_CLK_TO_Q;

      assert is_01(mon_axis.tready)
        report ERROR_MESSAGE;
    end process;

  end block;

  -- ---------------------------------------------------------------------------

  blk_tvalid_well_defined : block is

    constant ERROR_MESSAGE : string := BASE_ERROR_MESSAGE &
      "'tvalid' has undefined value.";

  begin

    -- -------------------------------------------------------------------------
    prc_tvalid_well_defined_check : process is begin
      wait until rising_edge(clk);
      wait for G_CLK_TO_Q;

      assert is_01(mon_axis.tvalid)
        report ERROR_MESSAGE;
    end process;

  end block;

  -- ---------------------------------------------------------------------------

  blk_handshaking : block is

    signal tready_ff : std_ulogic := '0';
    signal tvalid_ff : std_ulogic := '0';

    constant ERROR_MESSAGE : string := BASE_ERROR_MESSAGE &
      "'tvalid' fell without transaction.";

  begin

    -- -------------------------------------------------------------------------
    prc_handshaking_check : process is begin
      wait until rising_edge(clk);
      wait for G_CLK_TO_Q;

      if mon_axis.tvalid = '0' and tvalid_ff = '1' then
        assert tready_ff or srst
          report ERROR_MESSAGE;
      end if;

      tready_ff <= mon_axis.tready;
      tvalid_ff <= mon_axis.tvalid;
    end process;

    -- Nothing on the bus may change while 'valid' is asserted, unless there is
    -- a transaction (i.e. 'ready and valid' is true at a rising edge).
    bus_must_be_same_as_previous <= mon_axis.tvalid and tvalid_ff and not tready_ff;

  end block;

  -- ---------------------------------------------------------------------------

  blk_tlast : block is

    constant ERROR_MESSAGE : string     := get_unstable_error_message("tlast");
    signal   tlast_ff      : std_ulogic := '0';

  begin

    -- -------------------------------------------------------------------------
    prc_tlast_check : process is begin
      wait until rising_edge(clk);
      wait for G_CLK_TO_Q;

      if bus_must_be_same_as_previous then
        assert mon_axis.tlast = tlast_ff
          report ERROR_MESSAGE;
      end if;

      tlast_ff <= mon_axis.tlast;
    end process;

  end block;

  -- ---------------------------------------------------------------------------
  gen_tdata : if DW > 0 generate
    constant ERROR_MESSAGE : string := get_unstable_error_message("tdata");
    signal   tdata_ff      : std_ulogic_vector(mon_axis.tdata'range) := (others => '0');
  begin

    -- -------------------------------------------------------------------------
    prc_tdata_check : process is begin
      wait until rising_edge(clk);
      wait for G_CLK_TO_Q;

      if bus_must_be_same_as_previous then
        assert mon_axis.tdata = tdata_ff
          report error_message;
      end if;

      tdata_ff <= mon_axis.tdata;
    end process;

  end generate;

  -- ---------------------------------------------------------------------------
  gen_tkeep : if KW > 0 generate
    constant UNSTABLE_ERROR_MESSAGE  : string :=
      get_unstable_error_message("tkeep");
    constant UNDEFINED_ERROR_MESSAGE : string := (
      BASE_ERROR_MESSAGE & "'tkeep' has undefined value while bus is 'valid'."
    );

    signal tkeep_ff : std_ulogic_vector(mon_axis.tkeep'range) := (others => '0');
  begin

    -- -------------------------------------------------------------------------
    prc_tkeep_check : process is begin
      wait until rising_edge(clk);
      wait for G_CLK_TO_Q;

      if bus_must_be_same_as_previous then
        assert mon_axis.tkeep = tkeep_ff
          report unstable_error_message;
      end if;

      if mon_axis.tready and mon_axis.tvalid then
        assert is_01(mon_axis.tkeep)
          report undefined_error_message;
      end if;

      tkeep_ff <= mon_axis.tkeep;
    end process;

  end generate;

  -- ---------------------------------------------------------------------------
  gen_tuser : if UW > 0 generate
    constant ERROR_MESSAGE : string := get_unstable_error_message("tuser");
    signal   tuser_ff      : std_ulogic_vector(mon_axis.tuser'range) := (others => '0');
  begin

    -- -------------------------------------------------------------------------
    prc_tuser_check : process is begin
      wait until rising_edge(clk);
      wait for G_CLK_TO_Q;

      if bus_must_be_same_as_previous then
        assert mon_axis.tuser = tuser_ff
          report error_message;
      end if;

      tuser_ff <= mon_axis.tuser;
    end process;

  end generate;

end architecture;
