#!/usr/bin/env python3
"""SC2 <-> FPGA demo loop on the DefeatRoaches mini-game (9 Marines vs waves of 4 Roaches).

Every `--step` game loops the host:
  1. reads the visible Marines and Roaches from SC2,
  2. converts them to fixed-point records and sends one request frame over UART,
  3. waits for the FPGA's reply and checks it (snapshot id, status, unit count),
  4. turns each target index back into an SC2 unit and issues Attack only when the target changed.
The FPGA's SW0 decides the policy; the host never chooses targets itself. If a reply is
missing or invalid, the Marines simply get no new orders that step and the error is counted.

usage:
  python3 host/sc2_demo.py --port win:COM5                   # headless Linux SC2, FPGA in the loop
  python3 host/sc2_demo.py --port win:COM5 --window          # visible Windows SC2 client
  python3 host/sc2_demo.py --port model --policy 1           # no board: Python reference stands in
"""
from __future__ import annotations
import argparse, json, os, sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from sc2fpga.protocol import Snapshot, MAX_UNITS, COORD_MAX, NO_TARGET, STATUS, OK
from sc2fpga.transport import open_transport, LinkError

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--port", default="win:COM5", help="win:COM5 | /dev/ttyUSB0 | model")
ap.add_argument("--policy", type=int, default=1, help="only for --port model (the board uses SW0)")
ap.add_argument("--map", default="DefeatRoaches")
ap.add_argument("--seed", type=int, default=1)
ap.add_argument("--episodes", type=int, default=1)
ap.add_argument("--step", type=int, default=8, help="game loops per decision (8 = 0.36 s game time)")
ap.add_argument("--window", action="store_true", help="use the visible Windows SC2 client (WSL only)")
ap.add_argument("--realtime", action="store_true", help="play at normal game speed")
ap.add_argument("--quiet", action="store_true")
ap.add_argument("--log", default="host/logs/sc2_demo.jsonl")
args = ap.parse_args()

if args.window:
    os.environ.pop("SC2_WSL_DETECT", None)                     # let burnysc2 launch the Windows client
    os.environ.setdefault("SC2CLIENTHOST", "127.0.0.1"); os.environ.setdefault("SC2SERVERHOST", "127.0.0.1")
    os.environ.pop("SC2PATH", None)
else:
    os.environ["SC2_WSL_DETECT"] = "0"                          # headless Linux client
    os.environ.setdefault("SC2PATH", str(Path.home() / "StarCraftII"))

from sc2 import maps                                           # noqa: E402  (env must be set first)
from sc2.bot_ai import BotAI                                   # noqa: E402
from sc2.data import Race                                      # noqa: E402
from sc2.main import run_game                                  # noqa: E402
from sc2.player import Bot                                     # noqa: E402
if args.window:
    from sc2fpga import winclient
    winclient.install()

Q = 16                                                         # 1/16 map unit per LSB
POLICY_NAME = {0: "CLOSEST", 1: "FOCUS"}


def q(v: float) -> int:
    return max(0, min(COORD_MAX, round(v * Q)))


class FpgaBot(BotAI):
    def __init__(self, link, log):
        super().__init__()
        self.link, self.log = link, log
        self.snap_id = 0
        self.prev: dict[int, int] = {}                          # marine tag -> enemy tag last ordered
        self.stats = dict(decisions=0, orders=0, errors=0, policy=None, rtt=[], cycles=0, truncated=0)

    async def on_start(self):
        self.client.game_step = args.step

    async def on_step(self, iteration: int):
        marines = sorted(self.units, key=lambda u: u.tag)
        enemies = sorted(self.enemy_units, key=lambda u: u.tag)
        if not marines or not enemies:
            return
        if len(marines) > MAX_UNITS or len(enemies) > MAX_UNITS:
            self.stats["truncated"] += 1                         # hardware limit; reported, not hidden
            marines, enemies = marines[:MAX_UNITS], enemies[:MAX_UNITS]
        reach = marines[0].ground_range + marines[0].radius + enemies[0].radius
        self.snap_id = (self.snap_id + 1) & 0xFF
        snap = Snapshot(self.snap_id, min(65535, int((reach * Q) ** 2)),
                        [(q(m.position.x), q(m.position.y)) for m in marines],
                        [(q(e.position.x), q(e.position.y), min(255, int(e.health + e.shield))) for e in enemies])
        try:
            reply, rtt = self.link.query(snap)
            if reply.snap != snap.snap or reply.status != OK or len(reply.targets) != len(marines):
                raise LinkError(f"bad reply: snap {reply.snap}/{snap.snap} status {STATUS.get(reply.status)} n {len(reply.targets)}")
            if any(t != NO_TARGET and t >= len(enemies) for t in reply.targets):
                raise LinkError(f"target index out of range: {reply.targets}")
        except (LinkError, ValueError) as e:
            self.stats["errors"] += 1
            print(f"loop {self.state.game_loop:5d}  LINK ERROR: {e} (no orders this step)")
            self.link.flush()
            return
        st = self.stats
        st["decisions"] += 1; st["rtt"].append(rtt); st["cycles"] = max(st["cycles"], reply.cycles)
        st["policy"] = reply.policy
        orders = 0
        for m, t in zip(marines, reply.targets):
            if t == NO_TARGET:
                continue
            e = enemies[t]
            if self.prev.get(m.tag) != e.tag or m.is_idle:
                m.attack(e); self.prev[m.tag] = e.tag; orders += 1
        st["orders"] += orders
        if not args.quiet:
            tg = " ".join("-" if t == NO_TARGET else str(t) for t in reply.targets)
            hp = " ".join(str(e[2]) for e in snap.enemies)
            print(f"loop {self.state.game_loop:5d} snap {snap.snap:3d} {POLICY_NAME[reply.policy]:7s} "
                  f"marines {len(marines):2d} roach hp [{hp}] -> targets [{tg}]  "
                  f"rtt {1000*rtt:5.1f} ms  fpga {reply.cycles} cyc  orders {orders}")
        self.log.write(json.dumps({"loop": self.state.game_loop, "snap": snap.snap, "policy": reply.policy,
                                   "friends": snap.friends, "enemies": snap.enemies, "targets": reply.targets,
                                   "cycles": reply.cycles, "rtt_ms": round(1000 * rtt, 2)}) + "\n")


def main():
    Path(args.log).parent.mkdir(parents=True, exist_ok=True)
    link = open_transport(args.port, args.policy)
    results = []
    try:
        with open(args.log, "a") as log:
            for ep in range(args.episodes):
                seed = args.seed + ep
                bot = FpgaBot(link, log)
                t0 = time.time()
                res = run_game(maps.get(args.map), [Bot(Race.Terran, bot)], realtime=args.realtime, random_seed=seed)
                s = bot.stats; rtt = sorted(s["rtt"]) or [0]
                r = dict(episode=ep, seed=seed, port=args.port, policy=POLICY_NAME.get(s["policy"]),
                         score=bot.state.score.score, game_loops=bot.state.game_loop, decisions=s["decisions"],
                         orders=s["orders"], link_errors=s["errors"], truncated_steps=s["truncated"],
                         rtt_ms_median=round(1000 * rtt[len(rtt) // 2], 1), fpga_cycles_max=s["cycles"],
                         wall_s=round(time.time() - t0, 1), result=str(res))
                results.append(r)
                log.write(json.dumps({"summary": r}) + "\n")
                print("EPISODE", json.dumps(r))
    finally:
        link.close()
    if len(results) > 1:
        sc = [r["score"] for r in results]
        print(f"MEAN SCORE {sum(sc)/len(sc):.1f} over {len(sc)} episodes (policy {results[0]['policy']})")


if __name__ == "__main__":
    main()
