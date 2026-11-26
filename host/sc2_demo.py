#!/usr/bin/env python3
"""SC2 <-> FPGA demo loop on DefeatRoaches (V1 single-squad or V2 two-squad Lanchester).

usage:
  python host/sc2_demo.py --port /dev/ttyUSB0 --episodes 1 --realtime
  python host/sc2_demo.py --port /dev/ttyUSB0 --two-squads --split-demo --realtime
  python host/sc2_demo.py --port model --two-squads --split-demo --policy 1 --regroup 1

Board controls (V2 / --two-squads):
  SW0 FOCUS/CLOSEST   SW1 Lanchester guard   SW2 KEY unit (0 Marine, 1 Roach)
  SW3 cautious (2x)   SW4 reckless (0.5x)    SW8 pause    SW9 HEX view
  KEY0 add one unit   KEY1 remove one unit   KEY0+KEY1 held ~1 s: reset
"""
from __future__ import annotations
import argparse, json, os, sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from sc2fpga.protocol import (
    Snapshot, MAX_UNITS, COORD_MAX, NO_TARGET, STATUS, OK,
    SQ_ATTACK, SQ_REGROUP, SQ_FALLBACK, STATE_NAME, UNIT_ROACH, OP_ADD,
)
from sc2fpga.transport import open_transport, LinkError

ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
ap.add_argument("--port", default="/dev/ttyUSB0", help="/dev/ttyUSB0 | win:COM5 | model")
ap.add_argument("--policy", type=int, default=1, help="SW0 stand-in for --port model (0=CLOSEST, 1=FOCUS)")
ap.add_argument("--regroup", type=int, default=1, help="SW1 stand-in for --port model (0=OFF, 1=ON)")
ap.add_argument("--cautious", type=int, default=0, help="SW3 stand-in for --port model (2x threshold)")
ap.add_argument("--reckless", type=int, default=0, help="SW4 stand-in for --port model (0.5x threshold)")
ap.add_argument("--two-squads", action="store_true", help="use V2 protocol with Lanchester squad FSM")
ap.add_argument("--split-demo", action="store_true", help="briefly separate Squad A/B at wave start on DefeatRoaches")
ap.add_argument("--map", default="DefeatRoaches")
ap.add_argument("--seed", type=int, default=1)
ap.add_argument("--episodes", type=int, default=1)
ap.add_argument("--step", type=int, default=8, help="game loops per decision (8 = 0.36 s game time)")
ap.add_argument("--timeout", type=float, default=5.0, help="UART read timeout in seconds (allows KEY1 pause)")
ap.add_argument("--window", action="store_true", help="use the visible Windows SC2 client (WSL only)")
ap.add_argument("--realtime", action="store_true", help="play at normal game speed")
ap.add_argument("--quiet", action="store_true")
ap.add_argument("--log", default="host/logs/sc2_demo.jsonl")
args = ap.parse_args()

if args.window:
    os.environ.pop("SC2_WSL_DETECT", None)
    os.environ.setdefault("SC2CLIENTHOST", "127.0.0.1"); os.environ.setdefault("SC2SERVERHOST", "127.0.0.1")
    os.environ.pop("SC2PATH", None)
else:
    os.environ["SC2_WSL_DETECT"] = "0"
    os.environ.setdefault("SC2PATH", str(Path.home() / "StarCraftII"))

from sc2 import maps                                           # noqa: E402
from sc2.bot_ai import BotAI                                   # noqa: E402
from sc2.data import Race                                      # noqa: E402
from sc2.ids.unit_typeid import UnitTypeId                     # noqa: E402
from sc2.main import run_game                                  # noqa: E402
from sc2.player import Bot                                     # noqa: E402
from sc2.position import Point2                                # noqa: E402
if args.window:
    from sc2fpga import winclient
    winclient.install()

Q = 16
POLICY_NAME = {0: "CLOSEST", 1: "FOCUS"}


def mode_name(r) -> str:
    return "CAUTIOUS" if r.cautious else "RECKLESS" if r.reckless else "TUNED"


def state_label(state: int, last: bool) -> str:
    return "LAST-STAND" if last else STATE_NAME[state]


def q(v: float) -> int:
    return max(0, min(COORD_MAX, round(v * Q)))


class FpgaBot(BotAI):
    def __init__(self, link, log):
        super().__init__()
        self.link, self.log = link, log
        self.snap_id = 0
        self.prev: dict[int, tuple] = {}
        self.squad_of: dict[int, int] = {}
        self.split_until_loop = -1
        self.stats = dict(decisions=0, orders=0, errors=0, policy=None, rtt=[], cycles=0, truncated=0, edits=0)

    async def on_start(self):
        self.client.game_step = args.step

    def _assign_squads(self, marines):
        alive = {m.tag for m in marines}
        self.squad_of = {tag: sq for tag, sq in self.squad_of.items() if tag in alive}
        unassigned = [m for m in marines if m.tag not in self.squad_of]
        if unassigned and len(unassigned) < 4 and self.squad_of:
            # Reinforcements (KEY0): top up the smaller squad
            for m in unassigned:
                sizes = [sum(1 for sq in self.squad_of.values() if sq == i) for i in (0, 1)]
                self.squad_of[m.tag] = 0 if sizes[0] <= sizes[1] else 1
        elif unassigned:
            # Split newly spawned Marines into Squad A (upper Y) and Squad B (lower Y)
            by_y = sorted(unassigned, key=lambda u: (-u.position.y, u.tag))
            half = len(by_y) // 2
            for idx, m in enumerate(by_y):
                self.squad_of[m.tag] = 0 if idx < half else 1
            if args.split_demo and len(unassigned) >= 4:
                self.split_until_loop = self.state.game_loop + 32
        return [self.squad_of[m.tag] for m in marines]

    async def _apply_edit(self, reply, marines, enemies):
        """Apply KEY0/KEY1 unit edits reported by the board using SC2 debug commands."""
        roach = reply.ev_unit == UNIT_ROACH
        n = reply.ev_cnt
        if reply.ev_op == OP_ADD:
            group = enemies if roach else marines
            room = MAX_UNITS - len(group)
            n = min(n, room)
            if n > 0:
                anchor = Point2((sum(u.position.x for u in group) / len(group),
                                 sum(u.position.y for u in group) / len(group)))
                await self.client.debug_create_unit(
                    [[UnitTypeId.ROACH if roach else UnitTypeId.MARINE, n, anchor, 2 if roach else 1]])
        else:
            group = sorted(enemies if roach else marines, key=lambda u: (-u.health, u.tag))
            n = min(n, len(group) - 1)            # never remove the last unit (that ends the round)
            if n > 0:
                await self.client.debug_kill_unit([u.tag for u in group[:n]])
        self.stats["edits"] += max(n, 0)
        print(f"loop {self.state.game_loop:5d}  KEY{reply.ev_op}: {'add' if reply.ev_op == OP_ADD else 'remove'} "
              f"{max(n, 0)} {'Roach' if roach else 'Marine'}{'es' if roach and n != 1 else 's' if n != 1 else ''}")

    async def on_step(self, iteration: int):
        marines = sorted(self.units, key=lambda u: u.tag)
        enemies = sorted(self.enemy_units, key=lambda u: u.tag)
        if not marines or not enemies:
            return
        if len(marines) > MAX_UNITS or len(enemies) > MAX_UNITS:
            self.stats["truncated"] += 1
            marines, enemies = marines[:MAX_UNITS], enemies[:MAX_UNITS]

        squads = self._assign_squads(marines) if args.two_squads else None

        # Optional wave-start separation so DefeatRoaches starts with two split squads
        if args.two_squads and args.split_demo and self.state.game_loop < self.split_until_loop:
            assert squads is not None
            for m, sq in zip(marines, squads):
                pt = Point2((max(24.0, m.position.x - 1.5), 32.5 if sq == 0 else 23.0))
                m.move(pt)
            return

        reach = marines[0].ground_range + marines[0].radius + enemies[0].radius
        self.snap_id = (self.snap_id + 1) & 0xFF
        snap = Snapshot(
            self.snap_id, min(65535, int((reach * Q) ** 2)),
            [(q(m.position.x), q(m.position.y)) for m in marines],
            [(q(e.position.x), q(e.position.y), min(255, int(e.health + e.shield))) for e in enemies],
            squads=squads,
        )
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

        for idx, (m, t) in enumerate(zip(marines, reply.targets)):
            if reply.is_v2:
                assert squads is not None
                sq = squads[idx]
                sq_state = reply.state_a if sq == 0 else reply.state_b
                if sq_state == SQ_REGROUP:
                    rx, ry = reply.rally_a if sq == 0 else reply.rally_b
                    pt = Point2((rx / Q, ry / Q))
                    key = ("REGROUP", rx >> 3, ry >> 3)
                    if self.prev.get(m.tag) != key or m.is_idle:
                        m.move(pt); self.prev[m.tag] = key; orders += 1
                    continue
                if sq_state == SQ_FALLBACK:
                    rx, ry = reply.rally_a if sq == 0 else reply.rally_b
                    key = ("FALLBACK", rx, ry)
                    if self.prev.get(m.tag) != key:
                        m.move(Point2((rx / Q, ry / Q))); self.prev[m.tag] = key; orders += 1
                    continue
            if t == NO_TARGET:
                continue
            e = enemies[t]
            key = ("ATK", e.tag)
            if self.prev.get(m.tag) != key or m.is_idle:
                m.attack(e); self.prev[m.tag] = key; orders += 1

        st["orders"] += orders
        if reply.is_v2 and reply.ev_cnt:
            await self._apply_edit(reply, marines, enemies)
        if not args.quiet:
            tg = " ".join("-" if t == NO_TARGET else str(t) for t in reply.targets)
            hp = " ".join(str(e[2]) for e in snap.enemies)
            extra = ""
            if reply.is_v2:
                sa, sb = state_label(reply.state_a, reply.last_a), state_label(reply.state_b, reply.last_b)
                extra = (f"  SW1={reply.regroup_en} {mode_name(reply):8s} A:{sa:10s}({reply.p_a:3d}) "
                         f"B:{sb:10s}({reply.p_b:3d}) AB:{reply.p_ab:3d} vs E:{reply.p_e:4d} tog={int(reply.together)}")
            print(f"loop {self.state.game_loop:5d} snap {snap.snap:3d} {POLICY_NAME[reply.policy]:7s} "
                  f"marines {len(marines):2d} roach hp [{hp}] -> [{tg}]{extra}  "
                  f"rtt {1000*rtt:5.1f} ms  fpga {reply.cycles} cyc  orders {orders}")
        self.log.write(json.dumps({
            "loop": self.state.game_loop, "snap": snap.snap, "policy": reply.policy,
            "v2": reply.is_v2, "regroup_en": reply.regroup_en,
            "state_a": reply.state_a, "state_b": reply.state_b, "together": reply.together,
            "last_a": reply.last_a, "last_b": reply.last_b, "mode": mode_name(reply) if reply.is_v2 else None,
            "rally_a": reply.rally_a, "rally_b": reply.rally_b,
            "edit": [reply.ev_unit, reply.ev_op, reply.ev_cnt] if reply.is_v2 and reply.ev_cnt else None,
            "p_a": reply.p_a, "p_b": reply.p_b, "p_ab": reply.p_ab, "p_e": reply.p_e,
            "friends": snap.friends, "squads": snap.squads, "enemies": snap.enemies,
            "targets": reply.targets, "cycles": reply.cycles, "rtt_ms": round(1000 * rtt, 2),
        }) + "\n")


def main():
    Path(args.log).parent.mkdir(parents=True, exist_ok=True)
    link = open_transport(args.port, args.policy, args.regroup, timeout=args.timeout,
                          cautious=args.cautious, reckless=args.reckless)
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
                         orders=s["orders"], link_errors=s["errors"], truncated_steps=s["truncated"], unit_edits=s["edits"],
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
