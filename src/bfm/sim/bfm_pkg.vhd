-- -------------------------------------------------------------------------------------------------
-- Copyright (c) Lukas Vik. All rights reserved.
--
-- This file is part of the hdl-modules project, a collection of reusable, high-quality,
-- peer-reviewed VHDL building blocks.
-- https://hdl-modules.com
-- https://github.com/hdl-modules/hdl-modules
-- -------------------------------------------------------------------------------------------------
-- Convenience methods for working with VUnit ``integer_array_t``.
-- Used by some BFMs.
-- -------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library vunit_lib;
use vunit_lib.integer_array_pkg.all;
use vunit_lib.queue_pkg.all;

library osvvm;
use osvvm.randompkg.randomptype;

package bfm_pkg is

  -- This is a clone of the 'stall_config_t' from VUnit 'axi_stream_pkg'.
  -- We use this type instead so that we don't have to include the huge 'axi_stream_pkg' in
  -- small testbenches, thereby saving simulation startup time.
  type     stall_configuration_t is record
    stall_probability : real range 0.0 to 1.0;
    min_stall_cycles  : natural;
    max_stall_cycles  : natural;
  end record;
  constant ZERO_STALL_CONFIGURATION : stall_configuration_t := (
    stall_probability => 0.0,
    min_stall_cycles  => 0,
    max_stall_cycles  => 0
  );

  procedure random_stall (
    stall_config : in stall_configuration_t;
    rnd          : inout RandomPType;
    signal clk   : in std_ulogic
  );

  impure function concatenate_integer_arrays (
    base_array : integer_array_t;
    end_array : integer_array_t
  ) return integer_array_t;

  -- Convenience method for getting vector of BFM/VC elements.
  -- When doing e.g.
  --
  --   constant my_queues : queue_vec_t(0 to 1) := (others => new_queue);
  --
  -- works well in some simulators (GHDL), meaning that the function is evaluated once for each
  -- element of the vector. In e.g. Modelsim the function is only evaluated once, and all elements
  -- get the same value. Hence the need for this function.
  impure function get_new_queues (
    count : positive
  ) return queue_vec_t;

  function is_01 (
    value : std_ulogic
  ) return boolean;

  function is_01 (
    value : std_ulogic_vector
  ) return boolean;

  function to_real (
    b : boolean
  ) return real;

end package;

package body bfm_pkg is

  procedure random_stall (
    stall_config : in stall_configuration_t;
    rnd          : inout RandomPType;
    signal clk   : in std_ulogic
  ) is
    variable num_stall_cycles : natural := 0;
  begin
    if rnd.Uniform(0.0, 1.0) < stall_config.stall_probability then
      num_stall_cycles := rnd.FavorSmall(
          stall_config.min_stall_cycles,
          stall_config.max_stall_cycles
        );

      for stall in 1 to num_stall_cycles loop
        wait until rising_edge(clk);
      end loop;
    end if;
  end procedure;

  -- Concatenate two arrays with data.
  -- Will copy contents to new array, will not deallocate either of the input arrays.
  impure function concatenate_integer_arrays (
    base_array : integer_array_t;
    end_array : integer_array_t
  ) return integer_array_t is
    constant TOTAL_LENGTH : natural   := length(base_array) + length(end_array);
    variable result : integer_array_t := new_1d(
      length    => TOTAL_LENGTH,
      bit_width => bit_width(base_array),
      is_signed => is_signed(base_array)
    );
  begin
    assert bit_width(base_array) = bit_width(end_array)
      report "Can only concatenate similar arrays";
    assert is_signed(base_array) = is_signed(end_array)
      report "Can only concatenate similar arrays";

    assert height(base_array) = 1
      report "Can only concatenate one dimensional arrays";
    assert height(end_array) = 1
      report "Can only concatenate one dimensional arrays";

    assert depth(base_array) = 1
      report "Can only concatenate one dimensional arrays";
    assert depth(end_array) = 1
      report "Can only concatenate one dimensional arrays";

    for byte_idx in 0 to length(base_array) - 1 loop
      set(
          arr   => result,
          idx   => byte_idx,
          value => get(arr=> base_array, idx=> byte_idx)
        );
    end loop;

    for byte_idx in 0 to length(end_array) - 1 loop
      set(
          arr   => result,
          idx   => length(base_array) + byte_idx,
          value => get(arr=> end_array, idx=> byte_idx)
        );
    end loop;

    return result;
  end function;

  impure function get_new_queues (
    count : positive
  ) return queue_vec_t is
    variable result : queue_vec_t(0 to count - 1) := (others => null_queue);
  begin
    for queue_idx in result'range loop
      result(queue_idx) := new_queue;
    end loop;
    return result;
  end function;

  function is_01 (
    value : std_ulogic
  ) return boolean is
  begin
    return value = '0' or value = '1';
  end function;

  function is_01 (
    value : std_ulogic_vector
  ) return boolean is
  begin
    for idx in value'range loop
      if value(idx) /= '0' and value(idx) /= '1' then
        return false;
      end if;
    end loop;

    return true;
  end function;

  function to_real (
    b : boolean
  ) return real is
  begin
    if b then
      return 1.0;
    else
      return 0.0;
    end if;
  end function;

end package body;
