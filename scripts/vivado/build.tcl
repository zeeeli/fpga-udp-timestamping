# =====================================================
# scripts/vivado/build.tcl
# Create Project -> Synthesize -> Implement -> Gen Bit
# USAGE: vivado -mode batch -source scripts/vivado/build.tcl -tclargs <TOP>
# ======================================================

#------- Config------------
set TOP [lindex $argv 0]
set PART xc7a100tcsg324-1


#--- Create Build Folder---
set BASE "build/vivado"
set TS [clock format [clock seconds] -format "%Y-%m-%d_%H-%M-%S"]
set OUT "$BASE/$TOP/$TS"
file mkdir $OUT
file mkdir $OUT/bit
file mkdir $OUT/reports
file mkdir $OUT/checkpoints

#------- Read Design-------
read_verilog -sv [glob src/rtl/**/*.sv]

# --- constraints ---
read_xdc constraints/top_fpga.xdc

# ---NOTE: For XPM Sources---
set XPM_DIR $::env(XILINX_VIVADO)/data/ip/xpm
read_verilog -sv -library xpm \
  $XPM_DIR/xpm_cdc/hdl/xpm_cdc.sv \
  $XPM_DIR/xpm_memory/hdl/xpm_memory.sv \
  $XPM_DIR/xpm_fifo/hdl/xpm_fifo.sv

# ------- synth / impl / bit -------
synth_design -top $TOP -part $PART
write_checkpoint -force $OUT/checkpoints/post_synth.dcp
report_utilization -file $OUT/reports/util_synth.rpt
report_timing_summary -file $OUT/reports/timing_synth.rpt

opt_design
place_design
write_checkpoint -force $OUT/checkpoints/post_place.dcp
report_utilization -file $OUT/reports/util_place.rpt
report_timing_summary -file $OUT/reports/timing_place.rpt
report_io -file $OUT/reports/io_place.rpt

route_design
write_checkpoint -force $OUT/checkpoints/post_route.dcp
report_utilization -file $OUT/reports/util_route.rpt
report_timing_summary -file $OUT/reports/timing_route.rpt
report_drc -file $OUT/reports/drc_route.rpt

write_bitstream -force $OUT/bit/${TOP}_${TS}.bit
puts "Bitstream: $OUT/bit/${TOP}_${TS}.bit"
