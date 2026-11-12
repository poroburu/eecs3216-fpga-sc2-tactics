"""Wire protocol between the PC host and the DE10-Lite (see docs/protocol.md).

Request : A5 | snap | nF | nE | reach2_hi | reach2_lo | nF x {x_hi,x_lo,y_hi,y_lo}
             | nE x {x_hi,x_lo,y_hi,y_lo,hp} | chk
Reply   : 5A | snap | status | policy | n | n x target | cycles_hi | cycles_lo | chk
chk     : 8-bit sum of every byte after the sync byte and before chk.
"""
from __future__ import annotations
from dataclasses import dataclass, field

REQ_SYNC, RSP_SYNC = 0xA5, 0x5A
MAX_UNITS = 16
COORD_MAX = 2047          # unsigned Q7.4: 1/16 map unit
NO_TARGET = 0xFF
CLOSEST, FOCUS = 0, 1
STATUS = {0: "OK", 1: "BAD_CHECKSUM", 2: "BAD_COUNT", 3: "TIMEOUT", 4: "BAD_RANGE"}
OK, BAD_CHECKSUM, BAD_COUNT, TIMEOUT, BAD_RANGE = range(5)


@dataclass
class Snapshot:
    snap: int
    reach2: int
    friends: list[tuple[int, int]] = field(default_factory=list)          # (x, y)
    enemies: list[tuple[int, int, int]] = field(default_factory=list)     # (x, y, hp)


@dataclass
class Reply:
    snap: int
    status: int
    policy: int
    targets: list[int]
    cycles: int

    @property
    def ok(self) -> bool:
        return self.status == OK


def checksum(body: bytes) -> int:
    return sum(body) & 0xFF


def encode_request(s: Snapshot) -> bytes:
    body = bytearray([s.snap & 0xFF, len(s.friends), len(s.enemies), (s.reach2 >> 8) & 0xFF, s.reach2 & 0xFF])
    for x, y in s.friends:
        body += bytes([x >> 8, x & 0xFF, y >> 8, y & 0xFF])
    for x, y, hp in s.enemies:
        body += bytes([x >> 8, x & 0xFF, y >> 8, y & 0xFF, hp])
    return bytes([REQ_SYNC]) + bytes(body) + bytes([checksum(body)])


def encode_reply(r: Reply) -> bytes:
    body = bytes([r.snap & 0xFF, r.status, r.policy, len(r.targets), *r.targets, r.cycles >> 8, r.cycles & 0xFF])
    return bytes([RSP_SYNC]) + body + bytes([checksum(body)])


def reply_length(n: int) -> int:
    return 8 + n


def decode_reply(b: bytes) -> Reply:
    if len(b) < 8 or b[0] != RSP_SYNC:
        raise ValueError(f"bad reply header: {b.hex()}")
    n = b[4]
    if len(b) != reply_length(n):
        raise ValueError(f"reply length {len(b)} != {reply_length(n)}: {b.hex()}")
    if checksum(b[1:-1]) != b[-1]:
        raise ValueError(f"reply checksum mismatch: {b.hex()}")
    return Reply(snap=b[1], status=b[2], policy=b[3], targets=list(b[5:5 + n]), cycles=(b[5 + n] << 8) | b[6 + n])


def decode_request(b: bytes) -> Snapshot:
    """Parse a well-formed request (used by the software model and the on-board check)."""
    if b[0] != REQ_SYNC or checksum(b[1:-1]) != b[-1]:
        raise ValueError("not a well-formed request")
    nf, ne = b[2], b[3]
    s = Snapshot(b[1], (b[4] << 8) | b[5])
    o = 6
    for _ in range(nf):
        s.friends.append(((b[o] << 8) | b[o + 1], (b[o + 2] << 8) | b[o + 3])); o += 4
    for _ in range(ne):
        s.enemies.append(((b[o] << 8) | b[o + 1], (b[o + 2] << 8) | b[o + 3], b[o + 4])); o += 5
    return s
