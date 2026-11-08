# Quartus

- `common/de10_lite_pins.tcl`: pin and I/O-standard assignments, extracted from Intel's
  `DE10_LITE_Golden_Top` that ships with Quartus 25.1std.
- `sc2fpga/`: the demo project (`sc2fpga_top`, device `10M50DAF484C7G`, one 50 MHz clock).

```bash
tools/qbuild.sh quartus/sc2fpga sc2fpga     # compiles in a Windows temp copy; reports and .sof land in build/
tools/program.sh                            # JTAG, volatile
```

Measured utilization and timing are in [results.md](../docs/results.md). The UART adapter
must be 3.3 V. Its TXD goes to `GPIO[0]`, its RXD to `GPIO[1]`, and the grounds are shared.
