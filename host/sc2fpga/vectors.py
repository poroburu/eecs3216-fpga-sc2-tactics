"""Test-case generation shared by the HDL testbench and the on-board check.

Every case is (name, policy, request_bytes, expected_reply_bytes). Expected replies come
only from reference.py / the protocol definition, never from running the HDL.
"""
from __future__ import annotations
import json, random
from pathlib import Path
from .protocol import (Snapshot, Reply, encode_request, encode_reply, checksum, REQ_SYNC,
                       OK, BAD_CHECKSUM, BAD_COUNT, TIMEOUT, BAD_RANGE, COORD_MAX, MAX_UNITS)
from .reference import expected_reply, LanchesterState, FB_TIMEOUT
from .protocol import REQ_SYNC_V2, OP_ADD, OP_REMOVE, UNIT_MARINE, UNIT_ROACH

REACH2 = 8836          # Marine vs Roach: ((5 + 0.375 + 0.5) * 16)^2


def case(name, snap: Snapshot, policy):
    return (name, policy, encode_request(snap), encode_reply(expected_reply(snap, policy)))


def err(name, policy, req: bytes, snap_id: int, status: int):
    return (name, policy, req, encode_reply(Reply(snap_id, status, policy, [], 0)))


def directed() -> list:
    c = []
    for p in (0, 1):
        P = f"p{p}"
        c.append(case(f"{P}_empty", Snapshot(1, REACH2), p))
        c.append(case(f"{P}_no_enemies", Snapshot(2, REACH2, [(100, 100), (200, 200)]), p))
        c.append(case(f"{P}_no_friends", Snapshot(3, REACH2, [], [(100, 100, 50)]), p))
        c.append(case(f"{P}_one_one", Snapshot(4, REACH2, [(500, 500)], [(510, 500, 145)]), p))
        # equidistant enemies -> lowest index wins
        c.append(case(f"{P}_tie_distance", Snapshot(5, REACH2, [(500, 500)], [(520, 500, 90), (480, 500, 90), (500, 520, 90)]), p))
        # exact range boundary: d2 == reach2 (94^2) is in range, 95^2 is not
        c.append(case(f"{P}_range_boundary", Snapshot(6, REACH2, [(500, 500)], [(594, 500, 100), (500, 595, 10), (500, 405, 120)]), p))
        # all out of range: focus falls back to nearest
        c.append(case(f"{P}_all_out_of_range", Snapshot(7, REACH2, [(100, 100)], [(900, 900, 5), (800, 100, 200), (100, 700, 1)]), p))
        # in range, equal hp -> nearest; then lowest hp beats nearer
        c.append(case(f"{P}_hp_vs_distance", Snapshot(8, REACH2, [(500, 500), (520, 500)], [(560, 500, 60), (540, 500, 60), (530, 530, 59)]), p))
        # extreme coordinates: largest possible d2
        c.append(case(f"{P}_max_coords", Snapshot(9, 65535, [(0, 0), (COORD_MAX, COORD_MAX)], [(COORD_MAX, COORD_MAX, 255), (0, COORD_MAX, 0), (COORD_MAX, 0, 1)]), p))
        c.append(case(f"{P}_hp_zero", Snapshot(10, REACH2, [(500, 500)], [(510, 500, 5), (505, 500, 0)]), p))
        full = Snapshot(11, REACH2, [(400 + 7 * i, 450 + 9 * i) for i in range(MAX_UNITS)],
                        [(480 + 5 * j, 470 + 11 * j, 145 - 7 * j) for j in range(MAX_UNITS)])
        c.append(case(f"{P}_full_16x16", full, p))
        # ---- error handling ----
        good = encode_request(Snapshot(0x21, REACH2, [(500, 500)], [(510, 500, 145)]))
        bad = bytearray(good); bad[-1] ^= 0x01
        c.append(err(f"{P}_bad_checksum", p, bytes(bad), 0x21, BAD_CHECKSUM))
        c.append(err(f"{P}_bad_count_f", p, bytes([REQ_SYNC, 0x22, 17]), 0x22, BAD_COUNT))
        c.append(err(f"{P}_bad_count_e", p, bytes([REQ_SYNC, 0x23, 1, 17]), 0x23, BAD_COUNT))
        c.append(err(f"{P}_bad_range", p, encode_request(Snapshot(0x24, REACH2, [(COORD_MAX + 1, 5)], [(5, 5, 5)])), 0x24, BAD_RANGE))
        c.append(err(f"{P}_timeout", p, good[:7], 0x21, TIMEOUT))
        # a good frame right after errors must still work
        c.append(case(f"{P}_recover", Snapshot(0x25, REACH2, [(500, 500), (600, 600)], [(510, 500, 145), (590, 600, 20)]), p))
    return c


def random_cases(n: int, seed: int = 3216) -> list:
    rng = random.Random(seed)
    out = []
    for k in range(n):
        nf, ne = rng.randint(0, MAX_UNITS), rng.randint(0, MAX_UNITS)
        spread = rng.choice([40, 200, COORD_MAX])          # clustered fights produce many ties/in-range cases
        cx, cy = rng.randint(0, COORD_MAX), rng.randint(0, COORD_MAX)
        pt = lambda: (min(COORD_MAX, max(0, cx + rng.randint(-spread, spread))), min(COORD_MAX, max(0, cy + rng.randint(-spread, spread))))
        hp_pool = [rng.randint(0, 255) for _ in range(3)]      # repeated hp values -> hp ties
        s = Snapshot(k & 0xFF, rng.choice([REACH2, rng.randint(0, 65535)]),
                     [pt() for _ in range(nf)], [(*pt(), rng.choice(hp_pool)) for _ in range(ne)])
        out.append(case(f"rand{k}", s, rng.randint(0, 1)))
    return out


def trace_cases(path: Path) -> list:
    out = []
    for k, line in enumerate(open(path)):
        r = json.loads(line)
        s = Snapshot(k & 0xFF, r["friend"][0]["reach2"], [(f["x"], f["y"]) for f in r["friend"]][:MAX_UNITS],
                     [(e["x"], e["y"], min(255, e["hp"])) for e in r["enemy"]][:MAX_UNITS])
        for p in (0, 1):
            out.append(case(f"sc2_{k}_p{p}", s, p))
    return out


def write_mem(cases, path: Path):
    """Testbench format: one 12-bit hex word per line.
    4pp = set SW7:0 to pp, 1bb = request byte, 2bb = expected reply byte, 300 = run case,
    6kk = tap the keys in kk (bit0 KEY0, bit1 KEY1), 7kk = hold them past the reset time, FFF = end."""
    with open(path, "w") as f:
        for item in cases:
            if item[0] == "@sw":
                f.write(f"// switches\n4{item[1]:02x}\n")
                continue
            if item[0] == "@key":
                _, kk, long = item
                f.write(f"// keys {kk} {'hold' if long else 'tap'}\n{7 if long else 6}{kk:02x}\n")
                continue
            name, p, req, exp = item
            f.write(f"// {name}\n4{p:02x}\n")
            f.writelines(f"1{b:02x}\n" for b in req)
            f.writelines(f"2{b:02x}\n" for b in exp)
            f.write("300\n")
        f.write("fff\n")


def write_json(cases, path: Path):
    with open(path, "w") as f:
        for item in cases:
            if item[0] in ("@key", "@sw"):
                continue
            name, p, req, exp = item
            f.write(json.dumps({"name": name, "policy": p, "request": req.hex(), "expected": exp.hex()}) + "\n")


# ---------------- V2 two-squad Lanchester sequences ----------------
# Switch byte: bit0 SW0 policy, bit1 SW1 Lanchester, bit2 SW2 KEY unit, bit3 SW3 cautious, bit4 SW4 reckless.
SW_TUNED, SW_CAUTIOUS, SW_RECKLESS = 0b00010, 0b01010, 0b10010


def _sw_fields(sw: int) -> dict:
    return dict(policy=sw & 1, regroup_en=(sw >> 1) & 1, cautious=(sw >> 3) & 1, reckless=(sw >> 4) & 1)


class V2Seq:
    """Builds a stateful V2 case sequence; every expectation comes from reference.LanchesterState."""
    def __init__(self, prefix: str):
        self.prefix, self.lc, self.out, self.snap = prefix, LanchesterState(), [], 0
        self.pending = None   # (unit, op, count) KEY edits to report in the next OK reply

    def frame(self, name, sw, friends, squads, enemies, reach2=REACH2):
        self.snap = (self.snap + 1) & 0xFF
        snap = Snapshot(self.snap, reach2, friends, enemies, squads=squads)
        f = _sw_fields(sw)
        rep = expected_reply(snap, f["policy"], f["regroup_en"], self.lc, f["cautious"], f["reckless"])
        if rep.status == OK and self.pending:
            rep.ev_unit, rep.ev_op, rep.ev_cnt = self.pending
            self.pending = None
        self.out.append((f"{self.prefix}_{name}", sw, encode_request(snap), encode_reply(rep)))
        return rep

    def raw(self, name, sw, req: bytes, snap_id: int, status: int):
        f = _sw_fields(sw)
        rep = Reply(snap_id, status, f["policy"], [], 0, is_v2=True, regroup_en=f["regroup_en"],
                    cautious=f["cautious"], reckless=f["reckless"] if not f["cautious"] else 0)
        self.out.append((f"{self.prefix}_{name}", sw, req, encode_reply(rep)))

    def keys(self, kk: int, unit: int, presses: int = 1):
        """Tap KEY0 (kk=1, add) or KEY1 (kk=2, remove) `presses` times with SW2 = unit."""
        op = OP_ADD if kk == 1 else OP_REMOVE
        for _ in range(presses):
            if self.pending is None:
                self.pending = (unit, op, 1)
            elif self.pending[:2] == (unit, op) and self.pending[2] < 7:
                self.pending = (unit, op, self.pending[2] + 1)
            self.out.append(("@key", kk, False))

    def hold_reset(self):
        self.out.append(("@key", 3, True))
        self.lc.reset(); self.pending = None


def _squad_at(n, x, y, spread=6):
    return [(x + (k % 3) * spread, y + (k // 3) * spread) for k in range(n)]


def _roaches(n, x, y, hp=145):
    return [(x + 10 * k, y + (k % 2) * 12, hp) for k in range(n)]


def lanchester_directed() -> list:
    out = []
    for sw in (SW_TUNED, SW_TUNED | 1, SW_CAUTIOUS, SW_RECKLESS, 0b00000):
        q = V2Seq(f"lc{sw:02x}")
        def two(na, ax, ay, nb, bx, by, ne, ex=900, ey=520):
            fr = _squad_at(na, ax, ay) + _squad_at(nb, bx, by)
            return fr, [0] * na + [1] * nb, _roaches(ne, ex, ey)
        q.frame("sync_no_enemies", sw, *two(5, 400, 520, 5, 400, 360, 0))
        q.frame("apart_regroup", sw, *two(5, 400, 520, 5, 400, 360, 4))
        q.frame("together_engage", sw, *two(5, 400, 450, 5, 400, 430, 4))
        q.frame("depleted_fallback", sw, *two(3, 400, 450, 4, 400, 430, 4))
        for k in range(FB_TIMEOUT + 2):            # retreat point stays latched, then a last stand
            q.frame(f"fallback_{k}", sw, *two(3, 380 - k, 450, 4, 380 - k, 430, 4))
        q.frame("last_stand_casualty", sw, *two(2, 360, 450, 4, 360, 430, 4))
        q.frame("reinforced_reeval", sw, *two(3, 360, 450, 4, 360, 430, 4))
        q.frame("strong_again", sw, *two(6, 380, 450, 6, 380, 430, 3))
        q.frame("new_wave", sw, *two(6, 380, 450, 6, 380, 430, 5))
        q.frame("squad_b_gone", sw, *two(3, 380, 450, 0, 0, 0, 4))
        q.frame("sync_edge_low", sw, *two(2, 3, 3, 2, 10, 2, 0))
        q.frame("edge_low", sw, *two(2, 3, 3, 2, 10, 2, 6, ex=200, ey=200))
        q.frame("sync_edge_high", sw, *two(2, 2040, 2040, 2, 2035, 2041, 0))
        q.frame("edge_high", sw, *two(2, 2040, 2040, 2, 2035, 2041, 6, ex=1700, ey=1700))
        q.frame("one_vs_many", sw, *two(1, 600, 600, 1, 900, 900, 16, ex=700, ey=700))
        q.frame("full_16", sw, *two(8, 500, 500, 8, 520, 500, 4))
        good = encode_request(Snapshot(0x77, REACH2, [(500, 500)], [(510, 500, 145)], squads=[0]))
        bad = bytearray(good); bad[-1] ^= 0x01
        q.raw("bad_checksum", sw, bytes(bad), 0x77, BAD_CHECKSUM)
        q.raw("bad_squad", sw, encode_request(Snapshot(0x78, REACH2, [(500, 500)], [(510, 500, 145)], squads=[2])), 0x78, BAD_RANGE)
        q.frame("after_errors", sw, *two(5, 400, 450, 5, 400, 430, 4))
        out += q.out
    return out


def lanchester_keys() -> list:
    """Simulation-only: KEY edit reporting and the both-keys reset."""
    q = V2Seq("keys")
    fr = _squad_at(4, 400, 450) + _squad_at(4, 400, 430)
    sq, en = [0] * 4 + [1] * 4, _roaches(4, 900, 520)
    sw_m, sw_r = SW_TUNED, SW_TUNED | 0b100
    q.frame("sync", sw_m, fr, sq, [])
    q.frame("baseline", sw_m, fr, sq, en)
    q.keys(1, UNIT_MARINE, 3)                      # 3x add Marine
    q.frame("add_marine_x3", sw_m, fr, sq, en)
    q.frame("cleared", sw_m, fr, sq, en)
    q.out.append(("@sw", sw_r))
    q.keys(2, UNIT_ROACH, 2)                       # 2x remove Roach
    q.keys(1, UNIT_ROACH, 1)                       # different kind while pending: ignored
    q.frame("remove_roach_x2", sw_r, fr, sq, en)
    q.keys(1, UNIT_ROACH, 9)                       # saturates at 7
    q.frame("add_roach_sat7", sw_r, fr, sq, en)
    q.hold_reset()                                 # both keys: reset, no edit reported
    q.frame("after_reset_sync", sw_m, fr, sq, [])
    q.frame("after_reset", sw_m, fr, sq, en)
    return q.out


def lanchester_random(n_seq: int = 40, length: int = 25, seed: int = 3216) -> list:
    rng = random.Random(seed)
    out = []
    for si in range(n_seq):
        sw = rng.choice([SW_TUNED, SW_TUNED | 1, SW_CAUTIOUS, SW_RECKLESS, SW_CAUTIOUS | 0b10000, 0, 1])
        q = V2Seq(f"lcr{si}")
        q.snap = rng.randint(0, 255)
        q.frame("sync", sw, [(100, 100)], [0], [])
        cx, cy = rng.randint(100, 1900), rng.randint(100, 1900)
        for k in range(length):
            nf, ne = rng.randint(0, MAX_UNITS), rng.randint(0, MAX_UNITS)
            spread = rng.choice([20, 80, 300])
            pt = lambda: (min(COORD_MAX, max(0, cx + rng.randint(-spread, spread))), min(COORD_MAX, max(0, cy + rng.randint(-spread, spread))))
            fr = [pt() for _ in range(nf)]
            sq = [rng.randint(0, 1) for _ in range(nf)]
            en = [(*pt(), rng.randint(0, 255)) for _ in range(ne)]
            if rng.random() < 0.1:
                sw = rng.choice([SW_TUNED, SW_CAUTIOUS, SW_RECKLESS, 0])
            q.frame(f"s{k}", sw, fr, sq, en)
        out += q.out
    return out
