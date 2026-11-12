# Serial bridge so a WSL process can use a Windows COM port (the FTDI adapter is not visible in WSL).
# Line protocol on stdin/stdout:
#   X <hex>  -> write the request bytes, then read one reply frame (5A ... chk) -> "R <hex>"
#               (or "T <hex-so-far>" if the frame does not complete within the timeout)
#   F        -> discard any pending input bytes -> "OK"
#   Q        -> close and exit
param([string]$Port = "COM5", [int]$Baud = 115200, [int]$TimeoutMs = 500)
$p = New-Object System.IO.Ports.SerialPort $Port, $Baud, None, 8, One
$p.ReadTimeout = $TimeoutMs
$p.Open()
[Console]::Out.WriteLine("READY $Port"); [Console]::Out.Flush()
function ReadByteOrNull { try { return $p.ReadByte() } catch [System.TimeoutException] { return $null } }
while ($true) {
  $line = [Console]::In.ReadLine()
  if ($null -eq $line -or $line -eq "Q") { break }
  if ($line -eq "F") { $p.DiscardInBuffer(); [Console]::Out.WriteLine("OK"); [Console]::Out.Flush(); continue }
  if ($line.StartsWith("X ")) {
    $hex = $line.Substring(2).Trim()
    $buf = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $buf.Length; $i++) { $buf[$i] = [Convert]::ToByte($hex.Substring(2 * $i, 2), 16) }
    $p.Write($buf, 0, $buf.Length)
    $got = New-Object System.Collections.Generic.List[byte]
    $ok = $false
    while ($true) {                                  # hunt for the reply sync byte
      $b = ReadByteOrNull; if ($null -eq $b) { break }
      if ($b -eq 0x5A) { $got.Add([byte]$b); break }
    }
    if ($got.Count -eq 1) {
      $need = 4                                      # snap, status, policy, n
      for ($i = 0; $i -lt $need; $i++) { $b = ReadByteOrNull; if ($null -eq $b) { break }; $got.Add([byte]$b) }
      if ($got.Count -eq 5) {
        $rest = $got[4] + 3                          # targets + cycles(2) + chk
        for ($i = 0; $i -lt $rest; $i++) { $b = ReadByteOrNull; if ($null -eq $b) { break }; $got.Add([byte]$b) }
        $ok = ($got.Count -eq 5 + $rest)
      }
    }
    $h = -join ($got | ForEach-Object { $_.ToString("x2") })
    if ($ok) { [Console]::Out.WriteLine("R $h") } else { [Console]::Out.WriteLine("T $h") }
    [Console]::Out.Flush()
  }
}
$p.Close()
