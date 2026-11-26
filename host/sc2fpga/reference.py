"""Independent software reference for the FPGA's target selection and Lanchester squad FSM."""
from __future__ import annotations
from .protocol import (
    Snapshot, Reply, NO_TARGET, MAX_UNITS, COORD_MAX, OK, BAD_RANGE,
    CLOSEST, SQ_ATTACK, SQ_REGROUP, SQ_FALLBACK,
)

K_MARINE = 1
K_ROACH = 4
HYST_MARGIN = 8
REGROUP_DIST2 = 6400  # (5.0 map units * 16)^2
FALLBACK_STEP = 96    # 6.0 map units in Q.4
FB_TIMEOUT = 28       # decisions in FALLBACK before a committed last-stand ATTACK

RECIP_LUT = {n: round(32768 / n) for n in range(1, MAX_UNITS + 1)}


def _centroid(coords: list[tuple[int, int]]) -> tuple[int, int]:
    n = len(coords)
    if n == 0:
        return (0, 0)
    r = RECIP_LUT[n]
    cx = min(COORD_MAX, (sum(x for x, _ in coords) * r + 16384) >> 15)
    cy = min(COORD_MAX, (sum(y for _, y in coords) * r + 16384) >> 15)
    return (cx, cy)


def threshold(p_e: int, cautious: int, reckless: int) -> int:
    """Engagement threshold P_T: tuned P_E, cautious 2*P_E, reckless P_E/2 (cautious wins)."""
    if cautious:
        return p_e << 1
    if reckless:
        return p_e >> 1
    return p_e


def _away(self_c: int, enemy_c: int) -> int:
    if self_c > enemy_c:
        v = self_c + FALLBACK_STEP
    elif self_c < enemy_c:
        v = self_c - FALLBACK_STEP
    else:
        v = self_c
    return max(0, min(COORD_MAX, v))


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


def _rule(cur: int, n_other: int, together: bool, p_self: int, p_comb: int, p_t: int) -> int:
    need = p_t if cur == SQ_ATTACK else p_t + HYST_MARGIN
    p_use = p_comb if together else p_self
    if p_use >= need:
        return SQ_ATTACK
    if not together and n_other != 0:
        return SQ_REGROUP
    return SQ_FALLBACK


class _Squad:
    def __init__(self):
        self.state = SQ_ATTACK
        self.last = False
        self.fb_cnt = 0
        self.prev_n = 0
        self.fb_pt = (0, 0)


class LanchesterState:
    """Tracks the stateful two-squad FSM to match rtl/lanchester_ctrl.sv bit for bit."""
    def __init__(self):
        self.reset()

    def reset(self):
        self.sq = [_Squad(), _Squad()]
        self.prev_ne = 0

    @property
    def state_a(self) -> int:
        return self.sq[0].state

    @property
    def state_b(self) -> int:
        return self.sq[1].state

    def step(self, s: Snapshot, policy: int, regroup_en: int = 1,
             cautious: int = 0, reckless: int = 0) -> Reply:
        assert s.is_v2 and s.squads is not None
        reckless = reckless if not cautious else 0
        coords = [c for f in s.friends for c in f] + [c for e in s.enemies for c in e[:2]]
        if any(c > COORD_MAX for c in coords) or any(sq > 1 for sq in s.squads):
            return Reply(s.snap, BAD_RANGE, policy, [], 0, is_v2=True, regroup_en=regroup_en,
                         cautious=cautious, reckless=reckless)

        pos = [[p for p, sq in zip(s.friends, s.squads) if sq == i] for i in (0, 1)]
        n = [len(pos[0]), len(pos[1])]
        ne = len(s.enemies)
        p_self = [K_MARINE * n[0] ** 2, K_MARINE * n[1] ** 2]
        p_ab = K_MARINE * (n[0] + n[1]) ** 2
        p_e = K_ROACH * ne ** 2
        p_t = threshold(p_e, cautious, reckless)

        c = [_centroid(pos[0]), _centroid(pos[1])]
        ce = _centroid([e[:2] for e in s.enemies])
        d2_ab = (c[0][0] - c[1][0]) ** 2 + (c[0][1] - c[1][1]) ** 2
        together = n[0] > 0 and n[1] > 0 and d2_ab <= REGROUP_DIST2
        new_wave = ne > self.prev_ne

        rally = []
        for i in (0, 1):
            q, o = self.sq[i], 1 - i
            cur = q.state
            cnt, last = 0, False
            if not regroup_en or ne == 0 or n[i] == 0:
                ns = SQ_ATTACK
            elif q.last and not new_wave and not n[i] > q.prev_n:
                ns, last = SQ_ATTACK, True
            else:
                ns = _rule(cur, n[o], together, p_self[i], p_ab, p_t)
                if ns == SQ_FALLBACK:
                    if q.fb_cnt >= FB_TIMEOUT - 1:
                        ns, last = SQ_ATTACK, True
                    else:
                        cnt = q.fb_cnt + 1
            if ns == SQ_FALLBACK:
                if cur != SQ_FALLBACK:
                    q.fb_pt = (_away(c[i][0], ce[0]), _away(c[i][1], ce[1]))
                rally.append(q.fb_pt)
            else:
                rally.append(c[o] if n[o] else c[i])
            q.state, q.last, q.fb_cnt, q.prev_n = ns, last, cnt, n[i]
        self.prev_ne = ne

        return Reply(
            snap=s.snap, status=OK, policy=policy, targets=select_targets(s, policy),
            cycles=expected_cycles(s), is_v2=True, regroup_en=regroup_en,
            cautious=cautious, reckless=reckless,
            state_a=self.sq[0].state, state_b=self.sq[1].state,
            last_a=self.sq[0].last, last_b=self.sq[1].last, together=together,
            rally_a=rally[0], rally_b=rally[1], p_a=p_self[0], p_b=p_self[1], p_ab=p_ab, p_e=p_e,
        )


def expected_reply(s: Snapshot, policy: int, regroup_en: int = 1,
                   lc_state: LanchesterState | None = None, cautious: int = 0, reckless: int = 0) -> Reply:
    assert len(s.friends) <= MAX_UNITS and len(s.enemies) <= MAX_UNITS
    if s.is_v2:
        st = lc_state if lc_state is not None else LanchesterState()
        return st.step(s, policy, regroup_en, cautious, reckless)
    coords = [c for f in s.friends for c in f] + [c for e in s.enemies for c in e[:2]]
    if any(c > COORD_MAX for c in coords):
        return Reply(s.snap, BAD_RANGE, policy, [], 0)
    return Reply(s.snap, OK, policy, select_targets(s, policy), expected_cycles(s))


def reply_for_bytes(req: bytes, policy: int, regroup_en: int = 1,
                    lc_state: LanchesterState | None = None, cautious: int = 0, reckless: int = 0) -> Reply | None:
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
            return Reply(snap, BAD_COUNT, policy, [], 0, is_v2=v2, regroup_en=regroup_en, cautious=cautious if v2 else 0,
                         reckless=(reckless if not cautious else 0) if v2 else 0)
    if len(b) < 4:
        return Reply(snap, TIMEOUT, policy, [], 0, is_v2=v2, regroup_en=regroup_en, cautious=cautious if v2 else 0,
                         reckless=(reckless if not cautious else 0) if v2 else 0)
    f_stride = 5 if v2 else 4
    need = 6 + f_stride * b[2] + 5 * b[3] + 1
    if len(b) < need:
        return Reply(snap, TIMEOUT, policy, [], 0, is_v2=v2, regroup_en=regroup_en, cautious=cautious if v2 else 0,
                         reckless=(reckless if not cautious else 0) if v2 else 0)
    b = b[:need]
    if checksum(b[1:-1]) != b[-1]:
        return Reply(snap, BAD_CHECKSUM, policy, [], 0, is_v2=v2, regroup_en=regroup_en, cautious=cautious if v2 else 0,
                         reckless=(reckless if not cautious else 0) if v2 else 0)
    return expected_reply(decode_request(b), policy, regroup_en, lc_state, cautious, reckless)
