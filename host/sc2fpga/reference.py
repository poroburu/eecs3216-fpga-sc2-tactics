"""Independent software reference for the FPGA's target selection.

Written from the specification in docs/protocol.md with Python tuples, NOT by translating
the HDL's concatenated-key trick, so the two implementations can disagree if either is wrong.
"""
from __future__ import annotations
from .protocol import Snapshot, Reply, NO_TARGET, MAX_UNITS, COORD_MAX, OK, BAD_RANGE, CLOSEST


def select_targets(s: Snapshot, policy: int) -> list[int]:
    out = []
    for fx, fy in s.friends:
        best_key, best_j = None, NO_TARGET
        for j, (ex, ey, hp) in enumerate(s.enemies):
            d2 = (fx - ex) ** 2 + (fy - ey) ** 2
            if policy == CLOSEST:
                key = (d2, j)                                   # nearest, then lowest index
            else:
                in_range = d2 <= s.reach2
                key = (0, hp, d2, j) if in_range else (1, 0, d2, j)   # in range & weakest, else nearest
            if best_key is None or key < best_key:
                best_key, best_j = key, j
        out.append(best_j)
    return out


def expected_cycles(s: Snapshot) -> int:
    """Specified datapath latency: one pair per clock through a 3-stage pipeline."""
    nf, ne = len(s.friends), len(s.enemies)
    return 1 if nf == 0 or ne == 0 else nf * ne + 2


def expected_reply(s: Snapshot, policy: int) -> Reply:
    """What a correct FPGA must answer for a well-formed request."""
    coords = [c for f in s.friends for c in f] + [c for e in s.enemies for c in e[:2]]
    assert len(s.friends) <= MAX_UNITS and len(s.enemies) <= MAX_UNITS
    if any(c > COORD_MAX for c in coords):
        return Reply(s.snap, BAD_RANGE, policy, [], 0)
    return Reply(s.snap, OK, policy, select_targets(s, policy), expected_cycles(s))


def reply_for_bytes(req: bytes, policy: int) -> Reply:
    """Specified reply to an arbitrary byte string (one frame, then silence), including errors."""
    from .protocol import REQ_SYNC, checksum, BAD_CHECKSUM, BAD_COUNT, TIMEOUT, decode_request
    i = req.find(bytes([REQ_SYNC]))
    if i < 0:
        return None                                     # nothing to answer
    b = req[i:]
    snap = b[1] if len(b) > 1 else 0
    for k in (2, 3):                                    # counts are checked as soon as they arrive
        if len(b) > k and b[k] > MAX_UNITS:
            return Reply(snap, BAD_COUNT, policy, [], 0)
    if len(b) < 4:
        return Reply(snap, TIMEOUT, policy, [], 0)
    need = 6 + 4 * b[2] + 5 * b[3] + 1
    if len(b) < need:
        return Reply(snap, TIMEOUT, policy, [], 0)
    b = b[:need]
    if checksum(b[1:-1]) != b[-1]:
        return Reply(snap, BAD_CHECKSUM, policy, [], 0)
    return expected_reply(decode_request(b), policy)
