#=============================================================================
# ORCA v6.3 ZEN++ FPGA Constraints
# File: syn/fpga/orca_v63_fpga.xdc
# Target: AMD/Xilinx VCU128 (Virtex UltraScale+ VU37P)
# Description: Timing and pin constraints for 4-core reduced prototype
#=============================================================================

# ---------------------------------------------------------------------------
# Clock Definitions
# ---------------------------------------------------------------------------
create_clock -name sys_clk -period 10.000 [get_ports sys_clk_p]
create_clock -name jtag_clk -period 100.000 [get_ports jtag_tck]

# ---------------------------------------------------------------------------
# Clock Groups
# ---------------------------------------------------------------------------
set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks jtag_clk]

# ---------------------------------------------------------------------------
# Input/Output Delays
# ---------------------------------------------------------------------------
set_input_delay -clock sys_clk -max 2.000 [get_ports {rst_n *}]
set_input_delay -clock sys_clk -min 0.500 [get_ports {rst_n *}]

set_output_delay -clock sys_clk -max 2.000 [get_ports {led_* uart_tx}]
set_output_delay -clock sys_clk -min 0.500 [get_ports {led_* uart_tx}]

# ---------------------------------------------------------------------------
# False Paths
# ---------------------------------------------------------------------------
set_false_path -from [get_ports rst_n]
set_false_path -to [get_ports led_*]
set_false_path -from [get_ports jtag_*]

# ---------------------------------------------------------------------------
# Multi-Cycle Paths (for slow operations)
# ---------------------------------------------------------------------------
set_multicycle_path -setup 3 -from [get_cells *mul*] -to [get_cells *ro*]
set_multicycle_path -hold 2 -from [get_cells *mul*] -to [get_cells *ro*]

# ---------------------------------------------------------------------------
# Area Constraints
# ---------------------------------------------------------------------------
set_property MAX_FANOUT 32 [get_nets *]

# ---------------------------------------------------------------------------
# Power Optimization
# ---------------------------------------------------------------------------
set_property POWER_OPTIMIZATION true [get_designs *]

# ---------------------------------------------------------------------------
# Placement Constraints (for critical paths)
# ---------------------------------------------------------------------------
# Place ROB near commit stage
#create_pblock pblock_rob
#resize_pblock pblock_rob -add {SLICE_X100Y100:SLICE_X150Y150}
#add_cells_to_pblock pblock_rob [get_cells *cmt_rob*]

# ---------------------------------------------------------------------------
# Debug Core (ILA) for FPGA bring-up
# ---------------------------------------------------------------------------
set_property MARK_DEBUG true [get_nets *retire_valid*]
set_property MARK_DEBUG true [get_nets *exception*]
set_property MARK_DEBUG true [get_nets *aix_send*]
