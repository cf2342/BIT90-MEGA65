source [file join [file dirname [info script]] sources.tcl]
file mkdir [file join $root build]
file mkdir [file join $root helper reports]
read_vhdl -vhdl2008 $sources
read_xdc [file join $root constraints mega65_r6.xdc]
synth_design -top bit90_m2_r6 -part xc7a200tfbg484-2
report_utilization -file [file join $root helper reports utilization_synth.rpt]
opt_design
place_design
phys_opt_design
route_design
# The tape descriptor BRAM leaves the 100 MHz domain close to its limit.
# Give Vivado one post-route physical-optimization pass when the initial route
# retains a setup violation, then route the changed cells again.
if {[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]] < 0} {
    phys_opt_design -directive AggressiveExplore
    route_design
}
report_timing_summary -report_unconstrained -file [file join $root helper reports timing_routed.rpt]
report_drc -file [file join $root helper reports drc.rpt]
report_cdc -file [file join $root helper reports cdc.rpt]
report_utilization -file [file join $root helper reports utilization_routed.rpt]
write_checkpoint -force [file join $root build bit90_m2_r6.dcp]
if {[get_property SLACK [get_timing_paths -delay_type max -max_paths 1]] < 0} {error "Setup timing failed"}
if {[get_property SLACK [get_timing_paths -delay_type min -max_paths 1]] < 0} {error "Hold timing failed"}
write_bitstream -force [file join $root build bit90_m2_r6.bit]
