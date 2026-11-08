# Pin finder

Finds which DE10-Lite header pins a USB-UART adapter is wired to, without risking
contention. It produced the wiring in [docs/protocol.md](../../docs/protocol.md) on
November 8, 2026: adapter TXD → `GPIO[0]`, adapter RXD → `GPIO[1]`.

- All 52 `GPIO`/`ARDUINO_IO` pins start as inputs with weak pull-ups.
- **Phase 1** (`phase1.tcl` + `send.ps1`): the PC transmits `0x00` with RTS/DTR asserted,
  and JTAG (In-System Sources and Probes) reads which pins were seen low. That gives the
  adapter's TXD, plus RTS/DTR if they are wired.
- **Phase 2** (`phase2.tcl` + `listen.ps1`): drives one pin at a time, never pin 0 or any
  pin found in phase 1, with a repeating UART byte equal to its own index. The byte value
  that reaches the PC names the pin wired to the adapter's RXD.

```bash
tools/qbuild.sh tools/pinfind pinfind && tools/program.sh tools/pinfind/build/pinfind.sof
cd /mnt/c/Users/$USER_WIN/AppData/Local/Temp/sc2fpga/pinfind      # the build copy
/mnt/c/altera_lite/25.1std/quartus/bin64/quartus_stp.exe -t phase1.tcl
# then start listen.ps1 in the background and run phase2.tcl, as in the scripts
```

Before phase 2, edit `phase2.tcl` to skip any pins phase 1 reported.
