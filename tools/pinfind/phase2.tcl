# Drive pins 1..51 one at a time (pin 0 = detected adapter TX is never driven).
set hw [lindex [get_hardware_names] 0]
set dev [lindex [get_device_names -hardware_name $hw] 0]
start_insystem_source_probe -device_name $dev -hardware_name $hw
for {set k 1} {$k < 52} {incr k} {
  write_source_data -instance_index 0 -value_in_hex -value [format %02X [expr {0x40 | $k}]]
  after 150
}
write_source_data -instance_index 0 -value_in_hex -value 00
end_insystem_source_probe
puts DONE
