"""Wire protocol between the PC host and the DE10-Lite (V1 legacy + V2 two-squad Lanchester).

V1 Request : A5 | snap | nF | nE | reach2_hi | reach2_lo | nF x {x_hi,x_lo,y_hi,y_lo}
                | nE x {x_hi,x_lo,y_hi,y_lo,hp} | chk
V1 Reply   : 5A | snap | status | policy | n | n x target | cycles_hi | cycles_lo | chk

V2 Request : A6 | snap | nF | nE | reach2_hi | reach2_lo | nF x {x_hi,x_lo,y_hi,y_lo,squad}
                | nE x {x_hi,x_lo,y_hi,y_lo,hp} | chk
V2 Reply   : 5B | snap | status | flags  | n | n x target | meta | rally_a(4) | rally_b(4)
                | p_a(2) | p_b(2) | p_ab(2) | p_e(2) | cycles(2) | chk
"""
from __future__ import annotations
from dataclasses import dataclass, field

REQ_SYNC, RSP_SYNC = 0xA5, 0x5A
REQ_SYNC_V2, RSP_SYNC_V2 = 0xA6, 0x5B
MAX_UNITS = 16
COORD_MAX = 2047          # unsigned Q7.4: 1/16 map unit
NO_TARGET = 0xFF
CLOSEST, FOCUS = 0, 1
SQ_ATTACK, SQ_REGROUP, SQ_HOLD = 0, 1, 2
STATE_NAME = {0: "ATTACK", 1: "REGROUP", 2: "HOLD"}
STATUS = {0: "OK", 1: "BAD_CHECKSUM", 2: "BAD_COUNT", 3: "TIMEOUT", 4: "BAD_RANGE"}
OK, BAD_CHECKSUM, BAD_COUNT, TIMEOUT, BAD_RANGE = range(5)


@dataclass
class Snapshot:
    snap: int
    reach2: int
    friends: list[tuple[int, int]] = field(default_factory=list)          # (x, y)
    enemies: list[tuple[int, int, int]] = field(default_factory=list)     # (x, y, hp)
    squads: list[int] | None = None                                       # None -> V1, list[0|1] -> V2

    @property
    def is_v2(self) -> bool:
        return self.squads is not None


@dataclass
class Reply:
    snap: int
    status: int
    policy: int
    targets: list[int]
    cycles: int
    # V2 Lanchester fields
    is_v2: bool = False
    regroup_en: int = 0
    state_a: int = SQ_ATTACK
    state_b: int = SQ_ATTACK
    together: bool = False
    rally_a: tuple[int, int] = (0, 0)
    rally_b: tuple[int, int] = (0, 0)
    p_a: int = 0
    p_b: int = 0
    p_ab: int = 0
    p_e: int = 0

    @property
    def ok(self) -> bool:
        return self.status == OK


def checksum(body: bytes) -> int:
    return sum(body) & 0xFF


def encode_request(s: Snapshot) -> bytes:
    body = bytearray([s.snap & 0xFF, len(s.friends), len(s.enemies), (s.reach2 >> 8) & 0xFF, s.reach2 & 0xFF])
    if s.is_v2:
        assert s.squads is not None and len(s.squads) == len(s.friends)
        for (x, y), sq in zip(s.friends, s.squads):
            body += bytes([x >> 8, x & 0xFF, y >> 8, y & 0xFF, sq & 0xFF])
        sync = REQ_SYNC_V2
    else:
        for x, y in s.friends:
            body += bytes([x >> 8, x & 0xFF, y >> 8, y & 0xFF])
        sync = REQ_SYNC
    for x, y, hp in s.enemies:
        body += bytes([x >> 8, x & 0xFF, y >> 8, y & 0xFF, hp])
    return bytes([sync]) + bytes(body) + bytes([checksum(body)])


def encode_reply(r: Reply) -> bytes:
    if not r.is_v2:
        body = bytes([r.snap & 0xFF, r.status, r.policy & 1, len(r.targets), *r.targets,
                      r.cycles >> 8, r.cycles & 0xFF])
        return bytes([RSP_SYNC]) + body + bytes([checksum(body)])
    flags = ((r.regroup_en & 1) << 1) | (r.policy & 1)
    if r.status == OK:
        meta = ((1 if r.together else 0) << 4) | ((r.state_b & 3) << 2) | (r.state_a & 3)
        ext = bytes([
            meta,
            r.rally_a[0] >> 8, r.rally_a[0] & 0xFF, r.rally_a[1] >> 8, r.rally_a[1] & 0xFF,
            r.rally_b[0] >> 8, r.rally_b[0] & 0xFF, r.rally_b[1] >> 8, r.rally_b[1] & 0xFF,
            r.p_a >> 8, r.p_a & 0xFF, r.p_b >> 8, r.p_b & 0xFF,
            r.p_ab >> 8, r.p_ab & 0xFF, r.p_e >> 8, r.p_e & 0xFF,
        ])
    else:
        ext = bytes(17)
    body = bytes([r.snap & 0xFF, r.status, flags, len(r.targets), *r.targets]) + ext + bytes([
        r.cycles >> 8, r.cycles & 0xFF
    ])
    return bytes([RSP_SYNC_V2]) + body + bytes([checksum(body)])


def reply_length(n: int, v2: bool = False) -> int:
    return (25 + n) if v2 else (8 + n)


def decode_reply(b: bytes) -> Reply:
    if len(b) < 8 or b[0] not in (RSP_SYNC, RSP_SYNC_V2):
        raise ValueError(f"bad reply header: {b.hex()}")
    v2 = (b[0] == RSP_SYNC_V2)
    n = b[4]
    exp_len = reply_length(n, v2)
    if len(b) != exp_len:
        raise ValueError(f"reply length {len(b)} != {exp_len}: {b.hex()}")
    if checksum(b[1:-1]) != b[-1]:
        raise ValueError(f"reply checksum mismatch: {b.hex()}")
    targets = list(b[5:5 + n])
    if not v2:
        return Reply(snap=b[1], status=b[2], policy=b[3] & 1, targets=targets,
                     cycles=(b[5 + n] << 8) | b[6 + n])
    o = 5 + n
    meta = b[o]
    u16 = lambda k: (b[o + k] << 8) | b[o + k + 1]
    return Reply(
        snap=b[1], status=b[2], policy=b[3] & 1, targets=targets,
        cycles=(b[o + 17] << 8) | b[o + 18],
        is_v2=True, regroup_en=(b[3] >> 1) & 1,
        state_a=meta & 3, state_b=(meta >> 2) & 3, together=bool((meta >> 4) & 1),
        rally_a=(u16(1), u16(3)), rally_b=(u16(5), u16(7)),
        p_a=u16(9), p_b=u16(11), p_ab=u16(13), p_e=u16(15),
    )


def decode_request(b: bytes) -> Snapshot:
    """Parse a well-formed V1 or V2 request."""
    if not b or b[0] not in (REQ_SYNC, REQ_SYNC_V2) or checksum(b[1:-1]) != b[-1]:
        raise ValueError("not a well-formed request")
    v2 = (b[0] == REQ_SYNC_V2)
    nf, ne = b[2], b[3]
    s = Snapshot(b[1], (b[4] << 8) | b[5], squads=[] if v2 else None)
    o = 6
    for _ in range(nf):
        s.friends.append(((b[o] << 8) | b[o + 1], (b[o + 2] << 8) | b[o + 3]))
        if v2:
            assert s.squads is not None
            s.squads.append(b[o + 4])
            o += 5
        else:
            o += 4
    for _ in range(ne):
        s.enemies.append(((b[o] << 8) | b[o + 1], (b[o + 2] << 8) | b[o + 3], b[o + 4]))
        o += 5
    return s
