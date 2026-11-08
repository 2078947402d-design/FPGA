set first [get_cells -hier -regexp {.*gen_input_sync\[[0-3]\].*sync_ff_reg\[0\]$}]
if {[llength $first] < 1 || [llength $first] > 4} {error "Expected 1..4 enabled first synchronizer cells: $first"}
foreach stage {0 1 2} {
    set pattern [format {.*gen_input_sync\[[0-3]\].*sync_ff_reg\[%d\]$} $stage]
    set cells [get_cells -hier -regexp $pattern]
    if {[llength $cells] != [llength $first]} {error "Synchronizer stage count mismatch"}
    foreach c $cells {
        if {![get_property ASYNC_REG $c]} {error "Missing ASYNC_REG: $c"}
        if {[get_property REF_NAME $c] ni {FDCE FDRE}} {error "Unexpected synchronizer primitive: $c"}
    }
}
puts "SYNC_CHAIN_ATTRIBUTES_PASS channels=[llength $first] stages=3"
