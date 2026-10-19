# Create the separate MEGA65 R3/R3A Vivado project.
# The existing BIT90-MEGA65.xpr remains the R6 project.
set root [file dirname [file dirname [file normalize [info script]]]]
set project_dir [file join $root BIT90-MEGA65-R3]
set project_name BIT90-MEGA65-R3
set mega65_part xc7a200tfbg484-2
source [file join $root scripts sources.tcl]
create_project $project_name $project_dir -part $mega65_part -force
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]
add_files -fileset sources_1 -norecurse $sources
set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sources_1] *.vhd]
add_files -fileset constrs_1 -norecurse [file join $root constraints mega65_r3.xdc]
set_property top bit90_m2_r3 [get_filesets sources_1]
update_compile_order -fileset sources_1
# Match the implementation strategy proven by the Nascom2 R3/R3A target.
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraPostPlacementOpt [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
puts "Created MEGA65 R3/R3A project: $project_dir/$project_name.xpr"
puts "Top: bit90_m2_r3"
puts "Part: $mega65_part"
