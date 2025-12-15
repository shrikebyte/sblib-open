-- --##############################################################################
-- --# File : axis_slice.vhd
-- --# Auth : David Gussler
-- --# Lang : VHDL'19
-- --# ============================================================================
-- --! Slice one input packet into several output packets
-- --##############################################################################

-- library ieee;
-- use ieee.std_logic_1164.all;
-- use ieee.numeric_std.all;
-- use work.util_pkg.all;
-- use work.axis_pkg.all;

-- entity axis_slice is
--   generic (
--     G_PACK_OUTPUT : boolean := true;
--   );
--   port (
--     clk    : in    std_ulogic;
--     srst   : in    std_ulogic;
--     --
--     s_axis : view s_axis_v;
--     --
--     m0_axis : view m_axis_v;
--     m1_axis : view m_axis_v;
--     --! Enable split operation. Otherwise, this module is just a passthru.
--     enable : in std_ulogic;
--     --! Number of bytes from the start of the input to send to the first output
--     --! packet. The remaining input bytes, until tlast, will be sent to the
--     --! second output packet. Note that this does not necessarily have to be
--     --! 8-bit bytes. For example, if data width is 32 and keep width is 2, then
--     --! byte width would be 16.
--     slice_bytes  : in u_unsigned;
--     --! Pulses if the length of the input packet was shorter than split_bytes.
--     sts_err_runt : out std_ulogic;
--   );
-- end entity;

-- architecture rtl of axis_slice is

--   constant KW : integer := s_axis.tkeep'length;
--   constant DW : integer := s_axis.tdata'length;
--   constant UW : integer := s_axis.tuser'length;
--   constant DBW : integer := DW / KW;
--   constant UBW : integer := UW / KW;

--   type state_t is (ST_IDLE, ST_TX0, ST_FIRST_PARTIAL, ST_TX1, ST_PASSTHRU);
       
--   signal state : state_t;

--   signal m0_oe : std_ulogic;
--   signal m1_oe : std_ulogic;

--   signal slice_bytes_cnt : u_unsigned(slice_bytes'range);

--   signal int0_axis : axis_t (
--     tdata(s_axis.tdata'range),
--     tkeep(s_axis.tkeep'range),
--     tuser(s_axis.tuser'range)
--   );

--   signal int1_axis : axis_t (
--     tdata(s_axis.tdata'range),
--     tkeep(s_axis.tkeep'range),
--     tuser(s_axis.tuser'range)
--   );

--   signal input_num_valid_bytes : natural range 0 to s_axis.tkeep'length;

-- begin

--   input_num_valid_bytes <= cnt_ones(s_axis.tkeep);

--   -- ---------------------------------------------------------------------------

--   m0_oe <= m0_axis.tready or not m0_axis.tvalid;
--   m1_oe <= m1_axis.tready or not m1_axis.tvalid;

--   prc_s_ready : process (all) begin
--     case state is
--       when ST_IDLE =>
--         s_axis.tready <= '0';
--       when ST_TX | ST_PASSTHRU =>
--         s_axis.tready <= m0_oe;
--       when ST_M1 =>
--         s_axis.tready <= m1_oe;
--     end case;
--   end process;

--   -- ---------------------------------------------------------------------------
--   prc_fsm : process (clk) begin
--     if rising_edge(clk) then

--       -- Pulse;
--       sts_err_runt <= '0';

--       -- By default, clear mvalid if mready. The FSM might override this if it
--       -- has new data to send.
--       if int0_axis.tready then
--         int0_axis.tvalid <= '0';
--       end if;

--       case state is
--         -- ---------------------------------------------------------------------
--         when ST_IDLE =>
--           if s_axis.tvalid then
--             if enable then
--               slice_bytes_cnt <= slice_bytes;
--               state           <= ST_TX0;
--               sel
--             else
--               state <= ST_PASSTHRU;
--             end if;
--           end if;

--         -- ---------------------------------------------------------------------
--         when ST_TX0 =>
--           if s_axis.tvalid and s_axis.tready then
--             if slice_bytes_cnt > KW then
--               int0_axis.tvalid  <= '1';
--               int0_axis.tdata   <= s_axis.tdata;
--               int0_axis.tkeep   <= s_axis.tkeep;
--               slice_bytes_cnt   <= slice_bytes_cnt - input_num_valid_bytes;
--             else 
--               int0_axis.tvalid  <= '1';
--               int0_axis.tdata   <= s_axis.tdata;
--               int0_axis.tkeep(slice_bytes_cnt)   <= s_axis.tkeep;

--             if s_axis.tlast then
--               int0_axis.tlast  <= '1';
--               sts_err_runt   <= '1';
--               state          <= ST_IDLE;
--             else
--               int0_axis.tlast  <= '0';

--               if 

--               if (and s0_axis.tkeep) then
--                 -- If the last beat of s0 is full, skip repacking and simply
--                 -- forward s1 to the output. This saves one bubble cycle.
--             end if;
--           end if;

--         -- ---------------------------------------------------------------------
--         when ST_FIRST_PARTIAL =>
--           if s1_axis.tvalid and s1_axis.tready then

--             m_axis.tvalid <= '1';
--             m_axis.tdata  <= pack.packed_data;
--             m_axis.tkeep  <= pack.packed_keep;
--             resid_tdata   <= pack.resid_data;
--             resid_tkeep   <= pack.resid_keep;

--             if s1_axis.tlast then
--               if (or pack.resid_keep) then
--                 -- If there are any residual bytes, we need to transmit
--                 -- one extra beat to finish the packet.
--                 m_axis.tlast  <= '0';
--                 state <= ST_LAST;
--               else
--                 -- Otherwise, if there are no residual bytes left at this point,
--                 -- we're done.
--                 m_axis.tlast  <= '1';
--                 resid_tkeep   <= (others => '0');
--                 state         <= ST_IDLE;
--               end if;
--             else 
--               m_axis.tlast  <= '0';
--             end if;

--           end if;

--         -- ---------------------------------------------------------------------
--         when ST_PASSTHRU =>
--           if s_axis.tvalid and s_axis.tready then

--             int0_axis.tvalid <= '1';
--             int0_axis.tdata  <= s_axis.tdata;
--             int0_axis.tkeep  <= s_axis.tkeep;

--             if s_axis.tlast then
--               int0_axis.tlast  <= '1';
--               state          <= ST_IDLE;
--             else 
--               int0_axis.tlast  <= '0';
--             end if;
--           end if;

--         when others =>
--           null;
--       end case;

--       if srst then
--         int0_axis.tvalid  <= '0';
--         sts_err_runt    <= '0';
--         state           <= ST_IDLE;
--       end if;
--     end if;
--   end process;


-- end architecture;
