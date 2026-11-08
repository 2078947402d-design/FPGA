# PROVISIONAL offline-build configuration, explicitly requested on 2026-10-29.
# Assumption: Bank13 is supplied from +3.3V through fitted R221/R223 (0 ohm),
# as drawn in the V2.5 schematic. ACTUAL VCCO_B13 AND RESISTOR FITTING UNVERIFIED.
# User measured ordinary J4 +3.3V = 3.239V; this does NOT measure VCCO_B13.
# Physical board revision, J4 orientation and continuity remain unverified.
# Compiling or generating a bitstream does NOT establish electrical safety.
# DO NOT PROGRAM OR CONNECT SIGNALS until the board-level checks are complete.
set_property PACKAGE_PIN U5 [get_ports {external_ch[0]}]
set_property PACKAGE_PIN V7 [get_ports {external_ch[1]}]
set_property PACKAGE_PIN W8 [get_ports {external_ch[2]}]
set_property PACKAGE_PIN U9 [get_ports {external_ch[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {external_ch[*]}]
set_property PULLDOWN true [get_ports {external_ch[*]}]
