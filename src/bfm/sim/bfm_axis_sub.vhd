-- -------------------------------------------------------------------------------------------------
-- Copyright (c) Lukas Vik. All rights reserved.
--
-- This file is part of the hdl-modules project, a collection of reusable, high-quality,
-- peer-reviewed VHDL building blocks.
-- https://hdl-modules.com
-- https://github.com/hdl-modules/hdl-modules
-- -------------------------------------------------------------------------------------------------
-- BFM for verifying data on an AXI-Stream interface.
--
-- Reference data is pushed to the ``reference_data_queue``
-- :doc:`VUnit queue <vunit:data_types/queue>` as a
-- :doc:`VUnit integer_array <vunit:data_types/integer_array>`.
-- Each element in the integer array should be an unsigned byte.
-- Little endian byte order is assumed.
--
--
-- Randomization
-- _____________
--
-- This BFM can inject random handshake stall/jitter, for good verification coverage.
-- Modify the ``stall_config`` generic to get your desired behavior.
-- The random seed is provided by a VUnit mechanism
-- (see the "seed" portion of `this document <https://vunit.github.io/run/user_guide.html>`__).
-- Use the ``--seed`` command line argument if you need to set a static seed.
--
--
-- Unaligned packet length
-- _______________________
--
-- The byte length of the packets (as indicated by the length of the ``reference_data_queue``
-- arrays) does not need to be aligned with the ``data`` width of the bus.
-- If unaligned, the last beat will not have all ``data`` byte lanes checked against reference data.
--
--
-- ID field check
-- ______________
--
-- An optional expected ID can be pushed as a ``natural`` to the ``reference_id_queue`` in order to
-- enable ID check of each beat.
--
--
-- User field check
-- ________________
--
-- Furthermore, an optional check of the ``user`` field can be enabled by setting the
-- ``user_width`` to a non-zero value and pushing reference data to the ``reference_user_queue``.
-- Reference user data should be a :doc:`VUnit integer_array <vunit:data_types/integer_array>` just
-- as for the regular data.
-- -------------------------------------------------------------------------------------------------

library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

library vunit_lib;
use vunit_lib.check_pkg.all;
use vunit_lib.integer_array_pkg.all;
use vunit_lib.queue_pkg.all;

use work.util_pkg.all;
use work.axis_pkg.all;
use work.bfm_pkg.all;


entity bfm_axis_sub is
  generic (
    -- Push reference data (integer_array_t with push_ref()) to this queue.
    -- The integer arrays will be deallocated after this BFM is done with them.
    G_REF_DATA_QUEUE : queue_t;
    -- Push reference 'user' for each data beat to this queue.
    -- One value for each 'user' byte in each beat.
    -- If 'user_width' is zero, no check will be performed and nothing shall be pushed to
    -- this queue.
    G_REF_USER_QUEUE : queue_t := null_queue;
    -- Assign non-zero to randomly insert jitter/stalling in the data stream.
    G_STALL_CONFIG : stall_configuration_t := zero_stall_configuration;
    -- Suffix for error log messages. Can be used to differentiate between multiple instances.
    G_LOGGER_NAME_SUFFIX : string := "";
    -- Optionally, disable the checking of 'tkeep' bits.
    G_ENABLE_TKEEP : boolean := true;
    -- If true: Once asserted, 'ready' will not fall until valid has been asserted (i.e. a
    -- handshake has happened).
    -- Note that according to the AXI-Stream standard 'ready' may fall at any
    -- time (regardless of 'valid').
    -- However, many modules are developed with this well-behavedness as a way of saving resources.
    G_WELL_BEHAVED_STALL : boolean := false;
    -- For buses that do not have the 'last' indicator, the check for 'last' on the last beat of
    -- data can be disabled.
    G_ENABLE_TLAST : boolean := true
  );
  port (
    clk : in std_ulogic;
    --
    s_axis : view s_axis_v;
    --
    -- Optionally, the consuming and checking of data can be disabled.
    -- Can be done between or in the middle of packets.
    enable : in std_ulogic := '1';
    -- Counter for the number of packets that have been consumed and checked against reference data.
    num_packets_checked : out natural := 0
  );
end entity;

architecture sim of bfm_axis_sub is

  constant DW  : integer := s_axis.tdata'length;
  constant KW  : integer := s_axis.tkeep'length;
  constant UW  : integer := s_axis.tuser'length;
  constant DBW : integer := DW / KW;
  constant UBW : integer := UW / KW;

  constant BASE_ERROR_MESSAGE : string := "bfm_axis_sub - " &
    G_LOGGER_NAME_SUFFIX & ": ";

  signal checker_is_ready : std_ulogic := '0';
  signal data_is_ready : std_ulogic := '0';

  signal mon_axis : axis_t(
    tdata(s_axis.tdata'range),
    tuser(s_axis.tuser'range),
    tkeep(s_axis.tkeep'range)
  );

begin

  assert DW mod KW = 0 report (
    BASE_ERROR_MESSAGE &
    "Data width must be an integer multiple of keep width."
  );

  assert UW mod KW = 0 report (
    BASE_ERROR_MESSAGE &
    "User width must be an integer multiple of keep width."
  );

  -- ---------------------------------------------------------------------------
  prc_main : process
    variable ref_data : integer_array_t := null_integer_array;
    variable packet_length_bytes : positive := 1;
    variable packet_length_beats : positive := 1;

    variable k : natural range 0 to KW - 1 := 0;
    variable is_last_beat : boolean := false;
    variable got_byte : std_ulogic_vector(DBW - 1 downto 0) := (others => '0');
  begin
    while is_empty(G_REF_DATA_QUEUE) or enable /= '1' loop
      wait until rising_edge(clk);
    end loop;
    ref_data := pop_ref(G_REF_DATA_QUEUE);

    packet_length_bytes := length(ref_data);
    packet_length_beats := (packet_length_bytes + KW - 1) / KW;

    checker_is_ready <= '1';

    for i in 0 to packet_length_bytes - 1 loop
      k := i mod KW;

      if k = 0 then
        wait until s_axis.tready = '1' and s_axis.tvalid = '1' and rising_edge(clk);

        if G_ENABLE_TLAST then
          is_last_beat := i / KW = packet_length_beats - 1;
          check_equal(
            s_axis.tlast,
            is_last_beat,
            (
              BASE_ERROR_MESSAGE
              & "'tlast' check at packet_idx="
              & to_string(num_packets_checked)
              & ",byte_idx="
              & to_string(i)
            )
          );
        end if;
      end if;

      if G_ENABLE_TKEEP then
        check_equal(
          s_axis.tkeep(k),
          '1',
          (
            BASE_ERROR_MESSAGE
            & "'tkeep' check at packet_idx="
            & to_string(num_packets_checked)
            & ", byte_idx="
            & to_string(i)
          )
        );
      end if;

      got_byte := s_axis.tdata((k + 1) * DBW - 1 downto k * DBW);
      if is_signed(ref_data) then
        check_equal(
          u_signed(got_byte),
          get(ref_data, i),
          (
            BASE_ERROR_MESSAGE
            & "'tdata' check at packet_idx="
            & to_string(num_packets_checked)
            & ", byte_idx="
            & to_string(i)
          )
        );
      else
        check_equal(
          u_unsigned(got_byte),
          get(ref_data, i),
          (
            BASE_ERROR_MESSAGE
            & ": 'tdata' check at packet_idx="
            & to_string(num_packets_checked)
            & ", byte_idx="
            & to_string(i)
          )
        );
      end if;
    end loop;

    if G_ENABLE_TKEEP then
      -- Check tkeep for last data beat. If packet length aligns with the bus
      -- width, all lanes will
      -- have been checked as '1' above. If packet is not aligned, one or more
      -- byte lanes at the top shall be nulled out.
      for i in k + 1 to KW - 1 loop
        check_equal(
          s_axis.tkeep(i),
          '0',
          (
            BASE_ERROR_MESSAGE
            & "'tkeep' check at packet_idx="
            & to_string(num_packets_checked)
            & ", byte_idx="
            & to_string(i)
          )
        );
      end loop;
    end if;

    -- Deallocate after we are done with the data.
    deallocate(ref_data);

    -- Default: Signal "not ready" to handshake BFM before next packet.
    -- If queue is not empty, it will instantly be raised again (no bubble cycle).
    checker_is_ready <= '0';

    num_packets_checked <= num_packets_checked + 1;
  end process;

  data_is_ready <= checker_is_ready and enable;


  -- ---------------------------------------------------------------------------
  gen_check_tuser : if UW > 0 generate
  begin

    assert G_REF_USER_QUEUE /= null_queue
      report "Must set tuser reference queue";

    -- -------------------------------------------------------------------------
    prc_check_tuser : process
      variable user_packet : integer_array_t := null_integer_array;
      variable packet_length_bytes : positive := 1;

      variable k : natural range 0 to KW - 1 := 0;
    begin
    while is_empty(G_REF_USER_QUEUE) or enable /= '1' loop
      wait until rising_edge(clk);
    end loop;

      user_packet := pop_ref(G_REF_USER_QUEUE);
      packet_length_bytes := length(user_packet);

      for i in 0 to packet_length_bytes - 1 loop
        k := i mod KW;

        if k = 0 then
          wait until s_axis.tready = '1' and s_axis.tvalid = '1' and rising_edge(clk);
        end if;

        check_equal(
          u_unsigned(s_axis.tuser((k + 1) * UBW - 1 downto k * UBW)),
          get(user_packet, i),
          BASE_ERROR_MESSAGE &
          "'tuser' check at packet_idx=" &
          to_string(num_packets_checked)
        );

        if G_ENABLE_TLAST and i = packet_length_bytes - 1 then
          check_equal(
            s_axis.tlast,
            true,
            BASE_ERROR_MESSAGE &
            "Length mismatch between data packet and user packet"
          );
        end if;
      end loop;

      -- Deallocate after we are done with the data.
      deallocate(user_packet);
    end process;

  end generate;


  ------------------------------------------------------------------------------
  u_bfm_handshake_sub : entity work.bfm_handshake_sub
  generic map(
    g_stall_config => g_stall_config,
    g_well_behaved_stall => g_well_behaved_stall
  )
  port map(
    clk => clk,
    --
    data_is_ready => data_is_ready,
    --
    ready => s_axis.tready,
    valid => s_axis.tvalid
  );


  ------------------------------------------------------------------------------
  u_bfm_axis_protocol_check : entity work.bfm_axis_protocol_check
  generic map (
    G_LOGGER_NAME_SUFFIX => BASE_ERROR_MESSAGE
  )
  port map (
    clk => clk,
    --
    mon_axis => mon_axis
  );

  mon_axis.tready <= s_axis.tready;
  mon_axis.tvalid <= s_axis.tvalid;
  mon_axis.tlast  <= s_axis.tlast ;
  mon_axis.tkeep  <= s_axis.tkeep ;
  mon_axis.tdata  <= s_axis.tdata ;
  mon_axis.tuser  <= s_axis.tuser;

end architecture;
