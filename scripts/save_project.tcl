set script_name "scripts/create_project.tcl"
set tmp_script_name [ string map { ".tcl" "_old.tcl" } ${script_name} ]

set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_*]
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs impl_*]

remove_files  -fileset utils_1 *.dcp

write_project_tcl -force -origin_dir_override "scripts" -target_proj_dir "vivado" ${script_name}

file copy -force $script_name $tmp_script_name

set origfile [open $tmp_script_name r] 
set newfile  [open $script_name w+] 
while {[eof $origfile] != 1} { 
    gets $origfile lineInfo
    if {! [string match "*file normalize *kintex_wrapper.v*" $lineInfo]} {
    	if [ string equal $lineInfo "add_files -norecurse -fileset \$obj \$files"] {
            puts $newfile "add_files -norecurse -quiet -fileset \$obj \$files"
        } else {
            puts $newfile $lineInfo
        }
    }
}

close $origfile
close $newfile
file delete -force scripts/create_project_old.tcl 

