################################################################################
# File : fifo_async.tcl
# Auth : Lukas Vik, with minor edits by David Gussler
# Lang : Xilinx Design Constraints (TCL)
# ==============================================================================
# Scoped constraint. Use: "read_xdc -ref fifo_async fifo_async.tcl"
# Heavily inspired by
# https://github.com/hdl-modules/hdl-modules/blob/main/modules/fifo/scoped_constraints/asynchronous_fifo.tcl
################################################################################

set clk_write [get_clocks -quiet -of_objects [get_ports "s_clk"]]
set read_data [
  get_cells \
    -quiet \
    -filter {PRIMITIVE_GROUP==FLOP_LATCH || PRIMITIVE_GROUP==REGISTER} \
    "ram_data_reg*"
]

# These registers exist as FFs when the RAM is implemented as distributed RAM (LUTRAM).
# In this case there is a timing path from write clock to the read data registers which
# can be safely ignored in order for timing to pass.
# If the RAM is instead implemented as BRAM, the read data registers are internal in the
# BRAM primitive.
# This is also discussed in AMD UG903 and in various places in the forum.
# In recent Vivado versions (at least 2023.2), the cells show up even when the RAM is implemented as
# BRAM, hence why we filter for the primitive type.
if {${read_data} != "" && ${clk_write} != ""} {
  puts "INFO: fifo_async.tcl: Setting false path to read data registers."
  set_false_path -setup -hold -from ${clk_write} -to ${read_data}

  # Waive "LUTRAM read/write potential collision" warning to make reports a little cleaner.
  # The 'report_cdc' command lists all the data bits as a warning, for example
  # * From: asynchronous_fifo_inst/memory.mem_reg_0_15_0_5/RAMA_D1/CLK
  # * To: asynchronous_fifo_inst/memory.memory_read_data_reg[0]
  # The wildcards below aim to catch all these paths.
  set cdc_from [get_pins -quiet "memory.mem_reg*/*/CLK"]
  set cdc_to [get_pins -quiet "memory.memory_read_data_reg*/D"]
  create_waiver \
    -quiet \
    -id "CDC-26" \
    -from ${cdc_from} \
    -to ${cdc_to} \
    -description "Read/write pointer logic guarantees no collision"
}
