# Verification and issue disposition — November 8, 2026

This is the retained November 8 diagnostic/SDK evidence and issue disposition
from PR #5, not the current game-demo status. See [demo results](results.md) and
[demo contract](protocol.md) for PR #6. Issues #2–#4 remain open: the two contracts
are distinct, and the proposed strength/FSM extension still needs a versioned
interface. No earlier acceptance/sign-off is inferred from integrating the demo.

The diagnostic UART source files now live under `rtl/diagnostic/`; their contents
are unchanged. Historical source-hash paths describe the tested pre-integration
layout; the diagnostic QSF and simulation runner select the relocated files.
No new board, Quartus or game runs are claimed by this integration.

## Reproduced evidence

- Python 3.12.3: 19 host tests covering committed fixtures, numeric bounds,
  parsing, retries, stale/corrupt/truncated replies, reset, capacity, tags and
  fail-closed single-step sequencing. These use serial/backend test doubles.
- Icarus Verilog 12.0: 21 fixed fixtures plus 1,000 seeded random transport
  snapshots; active payload/metadata preservation, malformed inputs, timeout,
  consumer locking, framing errors and reset recovery. UART RX/TX cover every
  byte, back-to-back input, baud skew, false starts and invalid stop bits.
- Real COM5, Windows 11 Pro 10.0.26300, FTDI VCP 2.12.36.20: **25,600 bytes**
  across 100 rotated blocks passed through the existing FPGA GPIO loopback in
  **3.73 s**. Includes `00 FF 55 AA`. This is not an adapter-only test or a
  transmitter-FSM test.
- After the user unplugged/reconnected the SH-U09C5, the new UART diagnostic
  passed **all 21 fixed frame cases** on COM5. Exact TX/RX and elapsed times are
  retained in [JSONL](evidence/diagnostic-frames.jsonl). Valid snapshots receive
  UNSUPPORTED, never a manufactured successful HOLD decision.
- Quartus Lite 25.1std.0 Build 1129, exact 10M50DAF484C7G: diagnostic fit
  **993 logic elements, 492 registers, 3 pins**, no PLL/multipliers, and
  **+5.788 ns** worst setup / **+0.149 ns** worst hold slack at 50 MHz.
  [Fit/timing summary](evidence/uart-diagnostic-fit-and-timing.txt),
  [warnings](evidence/uart-diagnostic-warnings.txt),
  [tested source hashes](evidence/uart-diagnostic-source-sha256.json).
  The Quartus-rewritten QSF was normalized from CRLF to LF for source control;
  assignments are unchanged.
  The first fit failed timing; replacing combinational record-offset division
  with counters produced the reported passing result. The diagnostic does not
  read payload RAM, so Quartus trims it: zero RAM in this fit is not a fitted
  tactical-controller memory result. No full-controller timing claim follows.
- FTDI LatencyTimer read as **16 ms**, unchanged. No alternative timer/CPU-load
  comparison or independently measured wire timing has been performed.
- Windows SC2 installation contains **Base97563** and **Simple64.SC2Map**.
  Presence is not proof of a qualified scenario, live API control or legal action.
- WSL also has the Linux **4.10.0 / Base75689** client at `~/StarCraftII`.
  The pinned Blizzard C++ SDK and `host/sc2` target build with CMake 3.28.3/GCC 13.
  A real headless smoke check successfully launches, pings, creates/joins
  `BelShirVestigeLE.SC2Map`, validates **13 visible self units** via raw
  observations and advances exactly **0 → 8 game loops** with eight one-loop
  steps. No game orders or FPGA exchanges are issued. The legacy SDK's converted
  unit list incorrectly reports zero due to `CloakedUnknown` handling; see
  [Linux setup and limitation](sc2-linux.md) and
  [retained environment/result](evidence/sc2-linux-smoke.json).

The earlier UART-driven HEX design was restored after framed testing. Flash was
not modified. See [bring-up](uart-bringup.md) for sources, wiring and commands.
The preserved bring-up source comes from the earlier project's temporary working
directory; it was absent from the scaffold's Git history.

## Issue-by-issue acceptance

### #1 — USB-UART bring-up

Confirmed user-supplied 3.3 V setup, actual header/package mappings, checked-in
3.3-V LVTTL assignments, drivers/port, successful full-binary through-FPGA test,
and successful post-reconnect framed traffic. Reproducible scripts and wiring
are now in the repository. Wire colours were not recorded; use pin labels.

The adapter-only checklist step is superseded by successful through-FPGA binary
loopback and post-reconnect framed traffic, which exercise the adapter as part
of the actual electrical path. Adapter-only isolation is useful if that path
fails; no extra rewiring is needed for this successful bring-up. No adapter-only
measurement is claimed. Issue #1 can be closed with this explicit disposition.

### #2 — Packet contract and golden vectors

[Protocol v1](diagnostic-protocol.md) fixes offsets, lengths, checksum coverage, numeric
bounds/rounding, tags/indices, IDs, commands/status/cycles, timeout, resync,
atomic commit, handshake and full-byte duplicate/retry rules. Independent fixture
bytes are consumed by the Python and RTL tests and physical diagnostic test.
Size/line-time budgets are included. Ready for producer/consumer review.

Owner agreement is not fabricated: obtain the interface sign-off required by
CONTRIBUTING before merging dependent work. Session semantics are specified here;
the diagnostic endpoint does not implement the tactical/session consumer.

### #3 — UART RTL and framed snapshot ingestion

Implemented/tested synchronizer, RX/TX FSMs, field/count/length/checksum checks,
100 ms timeout, staging/atomic active storage, reply serialization, golden and
randomized transport tests, verified pins and physical frame exchange. Diagnostic
MAX 10 fit/timing evidence is retained.

Keep open: integrate the session cache/tactical consumer; serialize successful
per-unit decisions/cycles; fit and time the **complete** design including payload
memory and compute; repeat actual decision tests on hardware. The diagnostic ACK
and UNSUPPORTED reply do not meet successful tactical-decision acceptance.

### #4 — Host transport, latency and SC2

Implemented configurable serial transport, codec, matching IDs, bounded retries,
strict error handling, raw logs, serialization/line/compute/whole-exchange fields,
stable native tags, numeric conversion, command validation, confirmed/current
order deduplication, and single-step backend sequencing. Added physical loopback
and synthetic capacity benchmark tools, and inspected the actual FTDI setting.

Keep open: qualify a supported micro map/client/API binding; implement/integrate
the backend and tactical FPGA consumer; demonstrate a legal native action from
a successful hardware decision; retain true decision latency/cycle/CPU/throughput
results across capacity and supported FTDI timer settings. The synthetic benchmark
intentionally fails on the present UNSUPPORTED endpoint. No gameplay run, speedup,
win rate or successful SC2 decision is claimed.

The Linux runtime/API launch/observe/step smoke check above now establishes that
headless infrastructure is available. It does not qualify the tactical scenario
or a hardware-driven native action. The SDK build is also checked by CI without
requiring game binaries; live smoke testing uses the external WSL installation.

## Re-run

Use the component [host](../host/README.md), [simulation](../sim/README.md),
[RTL](../rtl/README.md), and [Quartus](../quartus/README.md) instructions.
The CI workflow runs the same Python and Icarus tests; hardware tests require
the documented physical setup and are not represented by a green CI run.
