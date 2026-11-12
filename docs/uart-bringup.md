# SH-U09C5 / DE10-Lite bring-up

## Established setup

The earlier project thread established COM5, an Altera USB-Blaster, 3.3 V
settings confirmed by the user, and this wiring from the user's diagram:

```text
SH-U09C5 TXD -----------------> JP1 pin 1 / GPIO[0] / MAX 10 V10 (uart_rx)
SH-U09C5 RXD <----------------- JP1 pin 2 / GPIO[1] / MAX 10 W10 (uart_tx)
SH-U09C5 GND ------------------ JP1 pin 12 (GND)
SH-U09C5 VCC                    disconnected; board powered via USB
```

JP1 physical pin numbers differ from GPIO indices. Confirm pin 1 from board
markings. Wire colours were not recorded and are not signal identifiers.
The diagram transcription and checked-in QSF preserve the actual signal mapping.

Sources: [Terasic-authored manual, June 5 2020, GPIO section](https://e2e.ti.com/cfs-file/__key/communityserver-discussions-components-files/73/DE10_2D00_Lite_5F00_User_5F00_Manual.pdf)
and [DSD TECH adapter specifications](https://www.deshide.com/product-details_1663161.html).
Confirm **TX and RX** selections are 3.3 V on the actual adapter, with USB
disconnected before changing jumpers. Do not infer TX/RX levels from VCC alone.
Leave VCC disconnected; no 5 V UART may reach the FPGA. Remove any TEST/TXD–RXD
loopback for normal use. Power the FPGA separately.

## Reproduce the GPIO path test

Windows 11 Pro 10.0.26300, FTDI VCP 2.12.36.20, USB-Blaster driver 2.12.28.0;
Quartus Lite 25.1std.0 Build 1129. FTDI LatencyTimer was read as 16 ms without
modification. COM5 belongs to Windows; no Linux ttyUSB device is required.
List ports with `[System.IO.Ports.SerialPort]::GetPortNames()`.

From Windows PowerShell in `quartus/bringup`, with the actual Quartus path:

```powershell
& 'C:\altera_lite\25.1std\quartus\bin64\quartus_sh.exe' --flow compile uart_loopback
& 'C:\altera_lite\25.1std\quartus\bin64\quartus_pgm.exe' -m JTAG -c 'USB-Blaster [USB-0]' -o 'p;output_files\uart_loopback.sof@1'
powershell -NoProfile -ExecutionPolicy Bypass -File .\test_loopback.ps1 -Port COM5
powershell -NoProfile -ExecutionPolicy Bypass -File .\send_text.ps1 -Port COM5 -Text UARTon
```

The process-only execution policy permits inspected local scripts; persistent
machine policy is unchanged. `.sof` programming is volatile, leaving flash
unchanged. The loopback compares 100 rotated blocks of all 256 byte values
(25,600 bytes), including `00 FF 55 AA`. The text command restores the earlier
UART-driven `UArton` display. This project's TX is a direct GPIO echo: it
verifies the electrical path, not a transmitter FSM.

An **adapter-only** test requires disconnecting the FPGA and joining adapter
TXD to RXD. Run the same loopback script. This physical rewiring has not been
performed by the agent; the through-FPGA test is a separate measurement.
For reconnect reliability, unplug/replug the adapter and rerun after enumeration;
record the resulting port. Enumeration alone is not a binary communication test.

## Framed-UART diagnostic

Compile `quartus/uart_diagnostic.qpf` and program its `.sof` with the same command,
substituting that project/output path. From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File host\test_frames.ps1 -Port COM5 -Fixtures sim\fixtures\protocol.json
```

Valid STARTs receive byte-exact ACKs; valid snapshots receive UNSUPPORTED because
the tactical core is absent. Invalid requests must produce no response. The test
enforces 120 ms silence between cases for recovery and emits raw TX/RX, sizes
and host elapsed time as JSONL. This checks the new UART RX/TX, not gameplay.
Restore the bring-up bitstream and send `UARTon` after testing if preserving the
previous display is desired.

See [protocol](diagnostic-protocol.md) for deadlines/IDs and [verification](verification.md)
for measured results and remaining acceptance work.
