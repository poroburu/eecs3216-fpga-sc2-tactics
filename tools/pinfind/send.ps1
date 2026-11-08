# Transmit 0x00 bytes on the adapter for 2 s with RTS/DTR asserted (so those lines, if wired, also show as low).
param([string]$Port="COM5")
$p=New-Object System.IO.Ports.SerialPort $Port,115200,None,8,One
$p.DtrEnable=$true; $p.RtsEnable=$true; $p.Open()
$buf=New-Object byte[] 64; $end=(Get-Date).AddSeconds(2)
while((Get-Date) -lt $end){ $p.Write($buf,0,64); Start-Sleep -Milliseconds 5 }
$p.Close()
