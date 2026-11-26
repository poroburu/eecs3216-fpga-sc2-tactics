"""Independent software reference for the FPGA's target selection and Lanchester squad FSM."""
from __future__ import annotations
from .protocol import (
    Snapshot, Reply, NO_TARGET, MAX_UNITS, COORD_MAX, OK, BAD_RANGE,
    CLOSEST, SQ_ATTACK, SQ_REGROUP, SQ_HOLD,
)

K_MARINE = 1
K_ROACH = 4
HYST_MARGIN = 8
REGROUP_DIST2 = 6400  # (5.0 map units * 16)^2

RECIP_LUT = {n: round(32768 / n) for n in range(1, MAX_UNITS + 1)}


def _centroid(coords: list[tuple[int, int]]) -> tuple[int, int]:
    n = len(coords)
    if n == 0:
        return (0, 0)
    r = RECIP_LUT[n]
    cx = min(COORD_MAX, (sum(x for x, _ in coords) * r + 16384) >> 15)
    cy = min(COORD_MAX, (sum(y for _, y in coords) * r + 16384) >> 15)
    return (cx, cy)


def select_targets(s: Snapshot, policy: int) -> list[int]:
    out = []
    for fx, fy in s.friends:
        best_key, best_j = None, NO_TARGET
        for j, (ex, ey, hp) in enumerate(s.enemies):
            d2 = (fx - ex) ** 2 + (fy - ey) ** 2
            if policy == CLOSEST:
                key = (d2, j)
            else:
                in_range = d2 <= s.reach2
                key = (0, hp, d2, j) if in_range else (1, 0, d2, j)
            if best_key is None or key < best_key:
                best_key, best_j = key, j
        out.append(best_j)
    return out


def expected_cycles(s: Snapshot) -> int:
    nf, ne = len(s.friends), len(s.enemies)
    return 1 if nf == 0 or ne == 0 else nf * ne + 2


def _next_state(cur: int, en: bool, n_self: int, n_other: int, n_e: int,
                together: bool, p_self: int, p_comb: int, p_e: int) -> int:
    if not en or n_e == 0 or n_self == 0:
        return SQ_ATTACK
    reengage = p_e + HYST_MARGIN
    if together:
        if cur == SQ_ATTACK:
            return SQ_ATTACK if p_comb >= p_e else SQ_HOLD
        return SQ_ATTACK if p_comb >= reengage else SQ_HOLD
    if cur == SQ_ATTACK:
        if p_self >= p_e:
            return SQ_ATTACK
        return SQ_REGROUP if n_other != 0 else SQ_HOLD
    if p_self >= reengage:
        return SQ_ATTACK
    return SQ_REGROUP if n_other != 0 else SQ_HOLD


class LanchesterState:
    """Tracks the stateful two-squad FSM to match rtl/lanchester_ctrl.sv."""
    def __init__(self):
        self.reset()

    def reset(self):
        self.state_a = SQ_ATTACK
        self.state_b = SQ_ATTACK

    def step(self, s: Snapshot, policy: int, regroup_en: int = 1) -> Reply:
        assert s.is_v2 and s.squads is not None
        coords = [c for f in s.friends for c in f] + [c for e in s.enemies for c in e[:2]]
        if any(c > COORD_MAX for c in coords) or any(sq > 1 for sq in s.squads):
            return Reply(s.snap, BAD_RANGE, policy, [], 0, is_v2=True, regroup_en=regroup_en)

        sq_a = [pos for pos, sq in zip(s.friends, s.squads) if sq == 0]
        sq_b = [pos for pos, sq in zip(s.friends, s.squads) if sq == 1]
        na, nb, ne = len(sq_a), len(sq_b), len(s.enemies)
        p_a = K_MARINE * (na ** 2)
        p_b = K_MARINE * (nb ** 2)
        p_ab = K_MARINE * ((na + nb) ** 2)
        p_e = K_ROACH * (ne ** 2)

        ca, cb = _centroid(sq_a), _centroid(sq_b)
        d2_ab = (ca[0] - cb[0]) ** 2 + (ca[1] - cb[1]) ** 2
        together = (na > 0 and nb > 0 and d2_ab <= REGROUP_DIST2)

        self.state_a = _next_state(self.state_a, bool(regroup_en), na, nb, ne, together, p_a, p_ab, p_e)
        self.state_b = _next_state(self.state_b, bool(regroup_en), nb, na, ne, together, p_b, p_ab, p_e)
        rally_a = cb if nb > 0 else ca
        rally_b = ca if na > 0 else cb

        return Reply(
            snap=s.snap, status=OK, policy=policy, targets=select_targets(s, policy),
            cycles=expected_cycles(s), is_v2=True, regroup_en=regroup_en,
            state_a=self.state_a, state_b=self.state_b, together=together,
            rally_a=rally_a, rally_b=rally_b, p_a=p_a, p_b=p_b, p_ab=p_ab, p_e=p_e,
        )


def expected_reply(s: Snapshot, policy: int, regroup_en: int = 1,
                   lc_state: LanchesterState | None = None) -> Reply:
    assert len(s.friends) <= MAX_UNITS and len(s.enemies) <= MAX_UNITS
    if s.is_v2:
        st = lc_state if lc_state is not None else LanchesterState()
        return st.step(s, policy, regroup_en)
    coords = [c for f in s.friends for c in f] + [c for e in s.enemies for c in e[:2]]
    if any(c > COORD_MAX for c in coords):
        return Reply(s.snap, BAD_RANGE, policy, [], 0)
    return Reply(s.snap, OK, policy, select_targets(s, policy), expected_cycles(s))


def reply_for_bytes(req: bytes, policy: int, regroup_en: int = 1,
                    lc_state: LanchesterState | None = None) -> Reply | None:
    from .protocol import (
        REQ_SYNC, REQ_SYNC_V2, checksum, BAD_CHECKSUM, BAD_COUNT, TIMEOUT, decode_request,
    )
    i = -1
    for idx, byte in enumerate(req):
        if byte in (REQ_SYNC, REQ_SYNC_V2):
            i = idx
            break
    if i < 0:
        return None
    b = req[i:]
    v2 = (b[0] == REQ_SYNC_V2)
    snap = b[1] if len(b) > 1 else 0
    for k in (2, 3):
        if len(b) > k and b[k] > MAX_UNITS:
            return Reply(snap, BAD_COUNT, policy, [], 0, is_v2=v2, regroup_en=regroup_en)
    if len(b) < 4:
        return Reply(snap, TIMEOUT, policy, [], 0, is_v2=v2, regroup_en=regroup_en)
    f_stride = 5 if v2 else 4
    need = 6 + f_stride * b[2] + 5 * b[3] + 1
    if len(b) < need:
        return Reply(snap, TIMEOUT, policy, [], 0, is_v2=v2, regroup_en=regroup_en)
    b = b[:need]
    if checksum(b[1:-1]) != b[-1]:
        return Reply(snap, BAD_CHECKSUM, policy, [], 0, is_v2=v2, regroup_en=regroup_en)
    return expected_reply(decode_request(b), policy, regroup_en, lc_state)
