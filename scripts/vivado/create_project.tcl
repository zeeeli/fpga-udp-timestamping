# ============================================
# create_project.tcl
# Starter script for Vivado 2019.1
# ============================================

# Set project name and location
set proj_name "FPGA_UDP_Timestamp"
set proj_dir "./${proj_name}"

# Create the project
create_project $proj_name $proj_dir -part xc7a100ticsg324-1L

# Set project properties
set_property board_part digilent.com:nexys-a7-100t:part0:1.0 [current_project]

# Create RTL, IP, and TB folders
file mkdir "$proj_dir/rtl"
file mkdir "$proj_dir/ip"
file mkdir "$proj_dir/tb"

# Optionally create empty top-level HDL file
set top_file "$proj_dir/rtl/top.sv"
if {![file exists $top_file]} {
    set f [open $top_file "w"]
    puts $f "// Top-level module placeholder"
    puts $f "module top();"
    puts $f "endmodule"
    close $f
}

# Add the RTL folder to project
add_files "$proj_dir/rtl/*.sv"
set_property top top [current_fileset]

# Save project
save_project
puts "Project $proj_name created at $proj_dir"
