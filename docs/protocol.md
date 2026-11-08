# Host ↔ FPGA contract

This is the whole specification of what the FPGA computes. Three files implement it
independently:

- `rtl/` is the hardware.
- `host/sc2fpga/reference.py` is the software reference used to check the hardware.
- `host/sc2fpga/protocol.py` is the encoder/decoder.

## Link

UART at 115200 baud, 8-N-1, LSB first.

| Signal | DE10-Lite pin | Adapter |
|---|---|---|
| FPGA RX | `GPIO[0]` = PIN_V10 (header pin 1) | FT232R TXD |
| FPGA TX | `GPIO[1]` = PIN_W10 (header pin 2) | FT232R RXD |
| Ground | header GND | GND |

The pins were found on November 8, 2026 with `tools/pinfind`, a safe pin-discovery
bitstream. The adapter is COM5 on Windows.

The PC sends one request and waits for one reply. The board never transmits on its own.

## Request frame (PC → FPGA)

| Bytes | Field | Rule |
|---|---|---|
| 1 | `A5` | sync |
| 1 | `snap` | snapshot id, echoed in the reply |
| 1 | `nF` | friendly count, 0–16 |
| 1 | `nE` | enemy count, 0–16 |
| 2 | `reach2` | big-endian, squared attack reach in Q.4 units² |
| 4·nF | `x_hi x_lo y_hi y_lo` | friendly positions |
| 5·nE | `x_hi x_lo y_hi y_lo hp` | enemy positions and HP (0–255) |
| 1 | `chk` | 8-bit sum of every byte after `A5` and before `chk` |

Coordinates are unsigned **Q7.4**: 1 LSB = 1/16 map unit, valid range 0–2047. The
largest frame (16 + 16 units) is 151 bytes, which takes 13.1 ms at 115200 baud.

## Reply frame (FPGA → PC)

| Bytes | Field |
|---|---|
| 1 | `5A` sync |
| 1 | `snap` (copied from the request) |
| 1 | `status` (see below) |
| 1 | `policy` used: 0 = CLOSEST, 1 = FOCUS (this is `SW0`) |
| 1 | `n` (= `nF` on success, 0 on error) |
| n | `target[i]`: enemy index 0..nE−1 for friendly unit i, or `FF` = none |
| 2 | `cycles` (big-endian) |
| 1 | `chk` (8-bit sum of every byte after `5A`) |

`cycles` is the number of 50 MHz clocks the datapath took. It is exactly
`nF·nE + 2`, or 1 if either count is 0. The maximum is 258 clocks (5.16 µs).

## The rule

For every friendly unit `i`, the target is the enemy `j` with the smallest key:

```
d2 = (x_i − x_j)² + (y_i − y_j)²          exact integer, no rounding
in = d2 ≤ reach2

CLOSEST (SW0 = 0): key = (d2, j)
FOCUS   (SW0 = 1): key = (0, hp_j, d2, j)   if in range
                   key = (1, 0,    d2, j)   if out of range
```

Keys compare left to right. So FOCUS means:

1. Prefer any enemy in range over any enemy out of range.
2. Among in-range enemies, take the lowest HP.
3. If HP ties, take the nearest.
4. If distance also ties, take the lowest index.

If nothing is in range, FOCUS falls back to the nearest enemy. With `nE = 0`, every
target is `FF`. Because the index is the last field, every input has exactly one
correct answer.

## Errors

| Status | HEX2 | Name | When |
|---|---|---|---|
| 0 | `0` | OK | |
| 1 | `1` | BAD_CHECKSUM | `chk` does not match |
| 2 | `2` | BAD_COUNT | `nF` or `nE` > 16 (reply sent as soon as that byte arrives) |
| 3 | `3` | TIMEOUT | more than 10 ms gap between bytes inside a frame |
| 4 | `4` | BAD_RANGE | a coordinate high byte > 7, which means a value > 2047 (checksum must be good) |

Error rules:

- An error reply carries the `snap` received so far (0 if none) and `n = 0`.
- A frame is copied into the working registers only after its checksum and fields pass.
  A bad frame never changes the result shown on HEX or VGA.
- After an error the parser hunts for the next `A5`. The host waits about 30 ms and
  flushes its input before sending again.
- A frame that completes while the FPGA is still computing or replying is dropped,
  and `LEDR3` (overrun) lights. The host never does this: it always waits for the reply.
