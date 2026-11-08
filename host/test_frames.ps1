# Physical diagnostic endpoint test, independent of Python codec and RTL.
param([string]$Port='COM5', [string]$Fixtures)
$ErrorActionPreference='Stop'
$cases=Get-Content -Raw $Fixtures | ConvertFrom-Json
$uart=New-Object System.IO.Ports.SerialPort $Port,115200,([System.IO.Ports.Parity]::None),8,([System.IO.Ports.StopBits]::One)
$uart.Handshake=[System.IO.Ports.Handshake]::None
$uart.DtrEnable=$false; $uart.RtsEnable=$false
$uart.ReadTimeout=250; $uart.WriteTimeout=1000
try {
    $uart.Open()
    foreach ($case in $cases) {
        # >=100 ms silence recovers a previous partial/oversized candidate.
        Start-Sleep -Milliseconds 120
        $uart.DiscardInBuffer()
        $hex=$case.hex
        [byte[]]$payload=for ($i=0; $i -lt $hex.Length; $i+=2) { [Convert]::ToByte($hex.Substring($i,2),16) }
        $clock=[System.Diagnostics.Stopwatch]::StartNew()
        $uart.Write($payload,0,$payload.Length)
        [byte[]]$reply=New-Object byte[] 23
        $count=0
        try {
            while ($count -lt 23) { $count+=$uart.Read($reply,$count,23-$count) }
        } catch [System.TimeoutException] {
            if ($case.request_ok) { throw "Missing reply for $($case.name)" }
        }
        $elapsed=$clock.Elapsed.TotalMilliseconds
        if ($case.request_ok) {
            [byte[]]$expected=New-Object byte[] 23
            [Array]::Copy($payload,0,$expected,0,14)
            $expected[3]=129; $expected[12]=8; $expected[13]=0
            if ($payload[3] -eq 2) { $expected[14]=6 } # no tactical core
            $sum=0
            for ($i=2; $i -lt 22; $i++) { $sum+=$expected[$i] }
            $expected[22]=[byte]((256-($sum%256))%256)
            for ($i=0; $i -lt 23; $i++) {
                if ($reply[$i] -ne $expected[$i]) { throw "Reply mismatch for $($case.name) at byte $i" }
            }
        } elseif ($count -ne 0) { throw "Invalid request produced a reply for $($case.name)" }
        [pscustomobject]@{ name=$case.name;valid=$true;tx_hex=$case.hex;
            rx_hex=([BitConverter]::ToString($reply,0,$count)).Replace('-','').ToLower();
            request_bytes=$payload.Length;reply_bytes=$count;elapsed_ms=$elapsed;
            diagnostic_only=$true } | ConvertTo-Json -Compress
    }
} finally { if ($uart.IsOpen) { $uart.Close() }; $uart.Dispose() }
