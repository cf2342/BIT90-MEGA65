# Recreate and build the separate MEGA65 R3/R3A project through bitstream generation.
set root [file dirname [file dirname [file normalize [info script]]]]
file mkdir [file join $root build]
file mkdir [file join $root helper reports]
source [file join $root scripts create_r3_project.tcl]
reset_run synth_1
launch_runs synth_1 -jobs 12
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "R3 synthesis status: $synth_status"
if {![string match "*Complete*" $synth_status]} {error "MEGA65 R3/R3A synthesis failed: $synth_status"}
launch_runs impl_1 -to_step write_bitstream -jobs 12
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "R3 implementation status: $impl_status"
if {![string match "*Complete*" $impl_status]} {error "MEGA65 R3/R3A implementation failed: $impl_status"}
open_run impl_1
set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $setup_path] == 0 || [llength $hold_path] == 0} {error "R3 timing check returned no paths"}
set r3_wns [get_property SLACK [lindex $setup_path 0]]
set r3_whs [get_property SLACK [lindex $hold_path 0]]
puts "R3 post-route WNS: $r3_wns ns"
puts "R3 post-route WHS: $r3_whs ns"
report_timing_summary -report_unconstrained -file [file join $root helper reports timing_r3_routed.rpt]
report_drc -file [file join $root helper reports drc_r3.rpt]
report_cdc -file [file join $root helper reports cdc_r3.rpt]
report_utilization -file [file join $root helper reports utilization_r3_routed.rpt]
if {$r3_wns < 0.0} {error "MEGA65 R3/R3A setup timing failed: WNS=$r3_wns ns"}
if {$r3_whs < 0.0} {error "MEGA65 R3/R3A hold timing failed: WHS=$r3_whs ns"}
set run_bit [file join $project_dir ${project_name}.runs impl_1 bit90_m2_r3.bit]
if {![file exists $run_bit]} {error "R3 bitstream was not generated: $run_bit"}
file mkdir [file join $root build]
file copy -force $run_bit [file join $root build bit90_m2_r3.bit]
puts "R3 bitstream: [file join $root build bit90_m2_r3.bit]"
