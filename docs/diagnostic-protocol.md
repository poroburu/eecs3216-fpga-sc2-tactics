> Earlier transport diagnostic only: use `quartus/uart_diagnostic.qpf` with
> `host/protocol.py` / `host/transport.py`. The working SC2 demo uses a different
> [wire contract](protocol.md). These frames and bitstreams are incompatible;
> this contract is not the proposed tactical extension's interface.

# UART protocol v1

Canonical implementation contract for #2, dated 2026-11-08. Python 3.12 is the
initial transport runtime. Producer/consumer owner sign-off and physical
interoperability remain pending; a wire-incompatible change requires a new
version. The UART modules and framing tests implement the byte layer. The
tactical core, session/reply cache and SC2 client are integration work, not
implemented hardware implied by this specification.

## Frame

115200 baud, 8 data bits, no parity, one stop bit, no flow control. Integers are
unsigned little-endian. Offsets below are bytes from the beginning of a frame.

| Offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | 2 | Sync `A5 5A` |
| 2 | 1 | Version `01` |
| 3 | 1 | START `01`, SNAPSHOT `02`, RESULT `81` |
| 4 | 4 | Nonzero round ID |
| 8 | 4 | Snapshot ID |
| 12 | 2 | Payload length (0–462) |
| 14 | length | Payload |
| 14 + length | 1 | Additive checksum |

Checksum is the two's-complement of the sum of bytes at offsets 2 through the
last payload byte, modulo 256. Including the checksum, that sum is zero modulo
256. Sync is excluded. This detects accidental corruption, not adversarial
modification. No escaping: sync inside a payload has no special meaning.

The receiver hunts for `A5 5A`. An overlapping `A5 A5 5A` starts at the second
`A5`. Invalid version/type/oversize header aborts the candidate and resumes the
hunt. After a plausible header, consume the declared payload and checksum;
checksum/semantic errors discard that candidate. The Python diagnostic decoder
may additionally search the rejected candidate for sync. A truncated candidate
may consume a following frame: after a failure, the host must wait at least
100 ms without sending bytes before retrying. A gap **>=100 ms** between received
bytes abandons any partial frame. UART framing error also abandons it. A
coincident byte at the timeout boundary starts a new sync hunt. A complete valid
frame is committed atomically; malformed frames never change active input.

Malformed envelopes are silently discarded and counted locally because their
IDs cannot be trusted. A semantically rejected, checksum-valid request can receive
RESULT with INVALID. Unsupported version/type is discarded. Never truncate counts
or lengths. One outstanding request, no pipelining. The compute consumer holds
the committed frame until finished; bytes sent while it is busy may be discarded.

## START and round/session rules

START has snapshot ID zero and an empty payload. It clears retreat history,
reservations and the cached decision. Success is RESULT/OK/HOLD with zero cycles
and no commands, matching both IDs. Repeat the identical START before the first
snapshot to obtain the same ACK. START in an already active round after any
snapshot is STALE; it must not reset retreat. Use a new round ID to start a new
observed round or to recover from a board reset. Do not guess a game round from
missing units. IDs never wrap; restart the session before exhaustion. Round IDs
must not be reused during a host process/session; close/reopen UART alone does
not reset the FPGA. A host restart must explicitly reset the FPGA before issuing
its first START, preventing collision with a cached round from a prior process.

SNAPSHOT IDs start at one and increase strictly within a round (gaps allowed).
Before START or after FPGA reset, return NOT_STARTED. A different round ID on a
SNAPSHOT returns NOT_STARTED. Repeating the last accepted ID with **identical
payload bytes** returns the cached complete reply without recomputing or changing
history. Same ID/different payload is CONFLICT; older IDs are STALE. Busy requests
may be dropped; BUSY may be returned only if the request IDs are trustworthy.
Invalid requests never advance the last accepted ID. Retain request and reply
bytes to compare duplicates; the additive checksum is insufficient for identity.

Default host deadline is 1 s per attempt; at most two retries, identical bytes.
Each retry follows >=100 ms transmit silence and clears incomplete RX parsing.
A matching explicit error fails immediately. Unmatched replies are logged and
ignored until deadline. A reset/NOT_STARTED aborts the run: establish a new round
with the scenario's **original** initial health, never silently capture reduced
mid-round health or substitute software tactics. A late OK for the same retried
ID is still valid. Start the deadline before write/flush; never mix retries into
one successful latency sample.

## SNAPSHOT payload

| Payload offset | Bytes | Meaning |
| --- | --- | --- |
| 0 | 1 | Friendly count, 0–16 |
| 1 | 1 | Enemy count, 0–16 |
| 2 | 4 | Initial total friendly maximum health, Q28.4 |
| 6, 8 | 2 each | Objective x, y, Q10.6 |
| 10, 12 | 2 each | Safety x, y, Q10.6 |
| 14 | 14 per unit | Friendly records then enemy records |

Each record: `index:u8, ready:u8, x:u16, y:u16, health:u16,
max_health:u16, damage:u16, reach:u16`. Length must be exactly
`14 + 14*(friendly_count + enemy_count)`.

Indices are 0–15, strictly ascending within each side. Host maps native 64-bit
SC2 tags separately for each side for the entire round; dead/disappeared indices
are never reassigned. Invisible enemies are absent from the current snapshot;
retain their tag mapping. More than 16 distinct tags on a side during a round is
unsupported, even if at most 16 are visible simultaneously. Native tags are
never sent to hardware. Send only current, eligible, living units; mixed types,
upgrades and abilities require separate scenario qualification.

`ready` is exactly 0 or 1 for friends and 0 for enemies. Health, max-health and
damage are Q12.4; health and damage are positive, health <= max-health. Positions,
effective reach and waypoints are Q10.6 (0–1023.984375 map units). All fields
are unsigned; a scenario must provide an authored coordinate origin if needed.
Convert finite nonnegative values by `floor(value * 2^fraction_bits + 0.5)`;
reject overflow and positive health/damage that rounds to zero. No saturation.
Reach must already include the qualified center-distance/radius conversion,
constant for the supported target type. An in-range test uses `dx² + dy² <= reach²`
without further rounding. Differences require signed 17 bits, sum 35 bits.

Initial health is captured once from the complete starting friendly squad and
sent unchanged each snapshot, including after deaths. It is <=1,048,560 raw
(16*65535), and >=sum of the current friendly max-health values. Empty squads
are legal, including initial health zero for an empty starting squad. A scenario
that introduces new friendly units is unsupported. Stable health/type facts
and constant initial health are checked by the host/scenario integration.

## RESULT payload

Prefix: `status:u8, state:u8, count:u8, reserved:u8=0, cycles:u32`.
Then exactly `count` commands (8 bytes each):
`actor:u8, intent:u8, target:u8, reserved:u8=0, x:u16, y:u16`.

Statuses: OK=0, NOT_STARTED=1, STALE=2, CONFLICT=3, BUSY=4, INVALID=5,
UNSUPPORTED=6. Error replies have state=0, cycles=0, count=0. No error reply
is a gameplay decision. State: HOLD=0, ADVANCE=1, ATTACK=2, RETREAT=3.
For a successful SNAPSHOT, return one command for every current friendly,
in ascending actor order, even for holds. Zero friends means zero commands.

Intent HOLD=0 requires target=255 and x=y=0; it means **submit no new order**,
preserving existing game orders. ATTACK=1 requires an eligible present enemy
index, x=y=0 and a ready actor. MOVE=2 requires target=255 and one of the two
authored waypoints. Coordinates are Q10.6. Host validates all commands before
submitting any, checks the captured tag map against the same observation, and
deduplicates unchanged attack/move orders. Reject unknown/reserved values.
The eventual tactical FSM determines which valid intent to emit; the wire
contract does not claim that core exists yet.

Cycles count 50 MHz compute clocks from accepted snapshot through finalized
commands, excluding UART and serialization; report overflow as an explicit error,
not wrap. A transport-only ACK does not measure tactical computation.

## Size and line-time budgets

At 115200 8N1, each byte costs 10/115200 s. The 15-byte envelope is included.
The reply has `8+8*friendly_count` payload bytes.

| Friends/enemies | Request bytes | Reply bytes | Total bytes | Minimum line time |
| --- | --- | --- | --- | --- |
| START/ACK | 15 | 23 | 38 | 3.299 ms |
| 0/0 | 29 | 23 | 52 | 4.514 ms |
| 4/4 | 141 | 55 | 196 | 17.014 ms |
| 8/8 | 253 | 87 | 340 | 29.514 ms |
| 16/16 | 477 | 151 | 628 | 54.514 ms |

The physical throughput ceiling is 11,520 bytes/s, before framing or driver
overhead. FTDI buffering, host scheduling, compute and software add latency.
Actual timing, resource utilization and SC2 compatibility require measurement.
See `sim/fixtures/protocol.json` for independent, committed byte fixtures and
the component READMEs for executable tests.
