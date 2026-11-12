import sys, time, json
from sc2 import maps
from sc2.bot_ai import BotAI
from sc2.data import Race
from sc2.main import run_game
from sc2.player import Bot

MAP = sys.argv[1]; LOOPS = int(sys.argv[2]) if len(sys.argv) > 2 else 1500
class Probe(BotAI):
    def __init__(s): s.t=None; s.steps=0; s.dts=[]; s.log=[]
    async def on_start(s):
        s.client.game_step = 8
        print("MAP", s.game_info.map_name, s.game_info.map_size, "playable", s.game_info.playable_area)
    async def on_step(s, it):
        now=time.perf_counter()
        if s.t: s.dts.append(now-s.t)
        s.t=now
        if it % 25 == 0 or it < 2:
            own=[(u.type_id.name,round(u.position.x,1),round(u.position.y,1),u.health,u.weapon_cooldown) for u in s.units]
            en=[(u.type_id.name,round(u.position.x,1),round(u.position.y,1),u.health) for u in s.enemy_units]
            print(f"loop={s.state.game_loop} own={len(own)} enemy={len(en)} score={s.state.score.score}")
            if it < 2:
                print(" own", own); print(" enemy", en)
                for u in list(s.units)[:1]+list(s.enemy_units)[:1]:
                    print(" STATS", u.type_id.name, "hp",u.health_max,"radius",u.radius,"range",u.ground_range,"dps",round(u.ground_dps,2),"speed",u.movement_speed)
        # simple attack-closest baseline
        for m in s.units:
            if s.enemy_units and m.is_idle:
                m.attack(s.enemy_units.closest_to(m))
        if s.state.game_loop > LOOPS:
            dts=sorted(s.dts); print("STEP ms median", round(1000*dts[len(dts)//2],2), "p95", round(1000*dts[int(.95*len(dts))],2), "n", len(dts))
            await s.client.leave()
t0=time.time()
run_game(maps.get(MAP), [Bot(Race.Terran, Probe())], realtime=False)
print("wall s", round(time.time()-t0,1))
