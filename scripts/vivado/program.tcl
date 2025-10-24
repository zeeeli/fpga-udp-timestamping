# =====================================================
# scripts/vivado/program.tcl
# USAGE: After running build.tcl ->
# vivado -mode tcl -sroucre scripts/vivado/prorgam.tcl -tclargs <PATH TO .bit FILE>
# ======================================================
set BITFILE [lindex $argv 0]
open_hw
connect_hw_server
open_hw_target

set devs [get_hw_devices]
current_hw_device [lindex $devs 0]

set_property PROGRAM.FILE $BITFILE [current_hw_device]
program_hw_devices [current_hw_device]
refresh_hw_device [current_hw_device]

close_hw_target
disconnect_hw_server
