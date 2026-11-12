"""Test-case generation shared by the HDL testbench and the on-board check.

Every case is (name, policy, request_bytes, expected_reply_bytes). Expected replies come
only from reference.py / the protocol definition, never from running the HDL.
"""
from __future__ import annotations
import json, random
from pathlib import Path
from .protocol import (Snapshot, Reply, encode_request, encode_reply, checksum, REQ_SYNC,
                       OK, BAD_CHECKSUM, BAD_COUNT, TIMEOUT, BAD_RANGE, COORD_MAX, MAX_UNITS)
from .reference import expected_reply

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
    4pp = set SW0 to pp, 1bb = request byte, 2bb = expected reply byte, 300 = run case, FFF = end."""
    with open(path, "w") as f:
        for name, p, req, exp in cases:
            f.write(f"// {name}\n4{p:02x}\n")
            f.writelines(f"1{b:02x}\n" for b in req)
            f.writelines(f"2{b:02x}\n" for b in exp)
            f.write("300\n")
        f.write("fff\n")


def write_json(cases, path: Path):
    with open(path, "w") as f:
        for name, p, req, exp in cases:
            f.write(json.dumps({"name": name, "policy": p, "request": req.hex(), "expected": exp.hex()}) + "\n")
