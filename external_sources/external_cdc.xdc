# Cut asynchronous pad -> first stage D only. All inter-stage paths stay timed.
set first [get_cells -hier -regexp {.*gen_input_sync\[[0-3]\].*sync_ff_reg\[0\]$}]
# Assertions live in external_scripts/check_cdc.tcl (XDC forbids Tcl control flow).
set_false_path -from [get_ports {external_ch[*]}] -to [get_pins -of_objects $first -filter {REF_PIN_NAME == D}]
