# Listen on the adapter and print a histogram of received byte values (each value = FPGA pin index).
param([string]$Port="COM5",[int]$Seconds=12)
$p=New-Object System.IO.Ports.SerialPort $Port,115200,None,8,One
$p.ReadTimeout=100; $p.Open(); $h=@{}; $end=(Get-Date).AddSeconds($Seconds)
while((Get-Date) -lt $end){ while($p.BytesToRead -gt 0){ $b=$p.ReadByte(); $h[$b]=1+$h[$b] }; Start-Sleep -Milliseconds 10 }
$p.Close(); foreach($k in $h.Keys){ "BYTE $k COUNT $($h[$k])" }
