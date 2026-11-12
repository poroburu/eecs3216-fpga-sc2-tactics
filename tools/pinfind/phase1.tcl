set hw [lindex [get_hardware_names] 0]
set dev [lindex [get_device_names -hardware_name $hw] 0]
start_insystem_source_probe -device_name $dev -hardware_name $hw
foreach phase {idle sending} {
  write_source_data -instance_index 0 -value_in_hex -value 80
  after 200
  write_source_data -instance_index 0 -value_in_hex -value 00
  if {$phase eq "sending"} { exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File send.ps1 }
  after 1500
  puts "PROBE $phase [read_probe_data -instance_index 0 -value_in_hex]"
}
end_insystem_source_probe
