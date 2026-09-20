#=============================================================================
# ORCA v6.3 ZEN++ FPGA Build Script
# File: syn/fpga_build.tcl
# Target: AMD/Xilinx VCU128 (Virtex UltraScale+ VU37P)
#=============================================================================

set project_name "orca_v63_fpga"
set part "xcvu37p-fsvh2892-2L-e"
set top_module "orca_v63_soc"
set out_dir "build/fpga"

# Create project
create_project -force ${project_name} ${out_dir} -part ${part}

# Set project properties
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib work [current_project]

# Read sources
read_verilog -sv [glob rtl/common/*.sv]
read_verilog -sv [glob rtl/soc/*.sv]
read_verilog -sv [glob rtl/cpu/*.sv]
read_verilog -sv [glob rtl/cpu/*/*.sv]
read_verilog -sv [glob rtl/ai/*.sv]
read_verilog -sv [glob rtl/ai/*/*.sv]
read_verilog -sv [glob rtl/noc/*.sv]
read_verilog -sv [glob rtl/pad/*.sv]

# Read constraints
read_xdc syn/fpga/orca_v63_fpga.xdc

# Set top module
set_property top ${top_module} [get_filesets sources_1]

# Run synthesis
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# Check synthesis results
set synth_status [get_property STATUS [get_runs synth_1]]
if {$synth_status != "synth_design Complete!"} {
    puts "ERROR: Synthesis failed with status: $synth_status"
    exit 1
}

# Run implementation
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

# Check implementation results
set impl_status [get_property STATUS [get_runs impl_1]]
if {$impl_status != "write_bitstream Complete!"} {
    puts "ERROR: Implementation failed with status: $impl_status"
    exit 1
}

# Report timing
open_run impl_1
report_timing_summary -file ${out_dir}/timing_summary.rpt -warn_on_violation
report_utilization -file ${out_dir}/utilization.rpt
report_power -file ${out_dir}/power.rpt

puts "FPGA build complete!"
puts "Bitstream: ${out_dir}/${project_name}.runs/impl_1/${top_module}.bit"
