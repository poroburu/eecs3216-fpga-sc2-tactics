param(
    [string]$Port = 'COM5',
    [ValidateRange(1, 10000)][int]$Blocks = 100
)
$ErrorActionPreference = 'Stop'
$uart = New-Object System.IO.Ports.SerialPort $Port,115200,([System.IO.Ports.Parity]::None),8,([System.IO.Ports.StopBits]::One)
$uart.Handshake = [System.IO.Ports.Handshake]::None
$uart.DtrEnable = $false
$uart.RtsEnable = $false
$uart.ReadTimeout = 2000
$uart.WriteTimeout = 2000
[byte[]]$payload = 0..255
[byte[]]$received = New-Object byte[] 256
$watch = [System.Diagnostics.Stopwatch]::StartNew()
try {
    $uart.Open()
    $uart.DiscardInBuffer()
    $uart.DiscardOutBuffer()
    for ($block = 0; $block -lt $Blocks; $block++) {
        # Rotate each block so a stale previous block cannot pass the comparison.
        for ($i = 0; $i -lt 256; $i++) {
            $payload[$i] = [byte](($i + $block) % 256)
        }
        $uart.Write($payload, 0, 256)
        $count = 0
        $deadline = [System.Diagnostics.Stopwatch]::StartNew()
        while ($count -lt 256) {
            if ($deadline.ElapsedMilliseconds -ge 2000) {
                throw "Block ${block}: timed out after receiving $count/256 bytes."
            }
            $uart.ReadTimeout = [Math]::Max(1, 2000 - [int]$deadline.ElapsedMilliseconds)
            try {
                $count += $uart.Read($received, $count, 256 - $count)
            } catch [System.TimeoutException] {
                throw "Block ${block}: timed out after receiving $count/256 bytes."
            }
        }
        for ($i = 0; $i -lt 256; $i++) {
            if ($received[$i] -ne $payload[$i]) {
                throw "Block ${block}, byte ${i}: expected $($payload[$i]), received $($received[$i])."
            }
        }
    }
    Start-Sleep -Milliseconds 50
    if ($uart.BytesToRead -ne 0) {
        throw "Unexpected trailing data: $($uart.BytesToRead) bytes."
    }
    Write-Output ("PASS: {0} bytes matched across {1} blocks on {2}, 115200 8-N-1, no flow control; {3:N2}s." -f ($Blocks * 256), $Blocks, $Port, $watch.Elapsed.TotalSeconds)
} catch {
    Write-Output "FAIL: $($_.Exception.Message)"
    exit 1
} finally {
    if ($uart.IsOpen) { $uart.Close() }
    $uart.Dispose()
}
