#!/usr/bin/env python3
"""On-board check: send test vectors to the FPGA over UART and compare every reply byte-for-byte
with the independent reference. Works with either SW0 position: the expected reply is computed
for the policy the board reports, and the run fails if the board reports anything else mid-run.

usage: python3 host/hw_check.py [--port win:COM5] [--set directed sc2_trace random] [--limit N]
"""
import argparse, json, sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from sc2fpga.protocol import decode_request, decode_reply, encode_reply, Reply, STATUS, OK
from sc2fpga.reference import expected_reply
from sc2fpga.transport import open_transport, LinkError

ap = argparse.ArgumentParser()
ap.add_argument("--port", default="win:COM5")
ap.add_argument("--set", nargs="+", default=["directed", "sc2_trace", "random"])
ap.add_argument("--limit", type=int, default=0)
a = ap.parse_args()

link = open_transport(a.port)
total = bad = 0; policy_seen = None; lat = []; cyc = []
try:
    for name in a.set:
        cases = [json.loads(l) for l in open(Path(__file__).parent / "vectors" / f"{name}.jsonl")]
        if a.limit: cases = cases[:a.limit]
        npass = 0
        for c in cases:
            req, stored = bytes.fromhex(c["request"]), decode_reply(bytes.fromhex(c["expected"]))
            t = time.perf_counter()
            try:
                raw = link.transact(req)
            except LinkError as e:
                bad += 1; total += 1; print(f"  {c['name']}: LINK ERROR {e}"); link.flush(); continue
            lat.append(time.perf_counter() - t)
            got = decode_reply(raw)
            policy_seen = got.policy if policy_seen is None else policy_seen
            if stored.status == OK:
                exp = expected_reply(decode_request(req), policy_seen)
                cyc.append(got.cycles)
            else:   # error cases: same reply apart from the policy echo
                exp = Reply(stored.snap, stored.status, policy_seen, [], 0)
            total += 1
            if raw == encode_reply(exp) and got.policy == policy_seen:
                npass += 1
            else:
                bad += 1
                print(f"  {c['name']}: MISMATCH\n    expected {encode_reply(exp).hex()}\n    got      {raw.hex()}")
            if got.status != OK:
                link.flush()    # discard bytes the parser rejected after an error
        print(f"{name}: {npass}/{len(cases)} pass")
finally:
    link.close()
lat.sort()
print(f"policy reported by board (SW0): {policy_seen} ({'FOCUS' if policy_seen else 'CLOSEST'})")
if lat:
    print(f"round trip ms: median {1000*lat[len(lat)//2]:.1f}, p95 {1000*lat[int(.95*len(lat))]:.1f}, max {1000*lat[-1]:.1f}")
if cyc:
    print(f"compute cycles: max {max(cyc)} ({max(cyc)/50:.2f} us at 50 MHz)")
print("RESULT", "PASS" if bad == 0 else "FAIL", f"{total - bad}/{total}")
sys.exit(1 if bad else 0)
