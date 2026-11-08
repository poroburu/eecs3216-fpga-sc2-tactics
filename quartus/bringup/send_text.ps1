param([string]$Port = 'COM5', [string]$Text = 'UARTon')
$ErrorActionPreference = 'Stop'
if ($Text.Length -gt 6 -or $Text -match '[^\x20-\x7E]') {
    throw 'Use at most six printable ASCII characters.'
}
$uart = New-Object System.IO.Ports.SerialPort $Port,115200,([System.IO.Ports.Parity]::None),8,([System.IO.Ports.StopBits]::One)
$uart.Handshake = [System.IO.Ports.Handshake]::None
$uart.DtrEnable = $false
$uart.RtsEnable = $false
$uart.ReadTimeout = 2000
$uart.WriteTimeout = 2000
try {
    $uart.Open()
    $uart.DiscardInBuffer()
    # Clear the display, then send the requested characters over the actual wire.
    [byte[]]$payload = @(12) + [System.Text.Encoding]::ASCII.GetBytes($Text)
    [byte[]]$received = New-Object byte[] $payload.Length
    $uart.Write($payload, 0, $payload.Length)
    $count = 0
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($count -lt $payload.Length) {
        if ($watch.ElapsedMilliseconds -ge 2000) { throw 'Echo timeout.' }
        $uart.ReadTimeout = [Math]::Max(1, 2000 - [int]$watch.ElapsedMilliseconds)
        $count += $uart.Read($received, $count, $payload.Length - $count)
    }
    for ($i = 0; $i -lt $payload.Length; $i++) {
        if ($received[$i] -ne $payload[$i]) { throw "Echo mismatch at byte $i." }
    }
    Write-Output "SENT over ${Port}: clear + '$Text'; all $($payload.Length) echoed bytes matched at 115200 8-N-1."
} catch {
    Write-Output "FAIL: $($_.Exception.Message)"
    exit 1
} finally {
    if ($uart.IsOpen) { $uart.Close() }
    $uart.Dispose()
}
