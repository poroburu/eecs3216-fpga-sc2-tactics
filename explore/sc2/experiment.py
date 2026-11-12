"""Run SC2 mini-game episodes with a fixed-point, FPGA-shaped target-allocation function.
usage: experiment.py MAP POLICY SEED GAME_STEP OUT.jsonl [TRACE.jsonl]"""
import sys, time, json
from sc2 import maps
from sc2.bot_ai import BotAI
from sc2.data import Race
from sc2.main import run_game
from sc2.player import Bot

MAP, POLICY, SEED, STEP, OUT = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
TRACE = sys.argv[6] if len(sys.argv) > 6 else None
Q = 16  # positions in 1/16 map unit (Q.4); 64-unit map -> 10 bits

def decide(friend, enemy, policy):
    """Pure function: lists of dicts with integer fields -> list of target indices (or -1).
    friend: x,y,cd(weapon ready=0),reach2 ; enemy: x,y,hp ; dmg fixed per scenario."""
    out, reserved = [], [0]*len(enemy)
    for f in friend:
        best, key = -1, None
        for j, e in enumerate(enemy):
            dx, dy = f["x"]-e["x"], f["y"]-e["y"]; d2 = dx*dx+dy*dy
            if policy == "closest":
                k = (d2, j)
            else:  # focus: in-range first, then lowest remaining hp after reservations, then distance, then index
                inr = d2 <= f["reach2"]
                rem = e["hp"] - reserved[j]
                if policy == "focus_nooverkill" and inr and rem <= 0:
                    continue
                k = (0 if inr else 1, rem if inr else 0, d2, j)
            if key is None or k < key: best, key = j, k
        if best >= 0 and policy != "closest":
            dx, dy = f["x"]-enemy[best]["x"], f["y"]-enemy[best]["y"]
            if dx*dx+dy*dy <= f["reach2"] and f["cd"] == 0: reserved[best] += f["dmg"]
        out.append(best)
    return out

class Exp(BotAI):
    def __init__(s):
        s.dts=[]; s.decisions=0; s.orders=0; s.prev={}; s.trace=open(TRACE,"w") if TRACE else None; s.maxF=s.maxE=0
    async def on_start(s): s.client.game_step = STEP
    def snap(s):
        F=sorted(s.units, key=lambda u:u.tag); E=sorted(s.enemy_units, key=lambda u:u.tag)
        fr=[]; en=[{"x":round(e.position.x*Q),"y":round(e.position.y*Q),"hp":int(e.health+e.shield)} for e in E]
        for u in F:
            reach = u.ground_range + u.radius + (E[0].radius if E else 0)
            dmg = int(u.calculate_damage_vs_target(E[0])[0]) if E else 0
            fr.append({"x":round(u.position.x*Q),"y":round(u.position.y*Q),"cd":0 if u.weapon_cooldown==0 else 1,
                       "reach2":int((reach*Q)**2),"dmg":dmg,"hp":int(u.health)})
        return F,E,fr,en
    async def on_step(s, it):
        F,E,fr,en=s.snap()
        if not F or not E: return
        s.maxF=max(s.maxF,len(F)); s.maxE=max(s.maxE,len(E))
        t=time.perf_counter(); tg=decide(fr,en,POLICY); s.dts.append(time.perf_counter()-t)
        s.decisions+=1
        if s.trace: s.trace.write(json.dumps({"loop":s.state.game_loop,"friend":fr,"enemy":en,"policy":POLICY,"targets":tg})+"\n")
        for u,j in zip(F,tg):
            if j<0: continue
            if s.prev.get(u.tag)!=E[j].tag or u.is_idle:
                u.attack(E[j]); s.orders+=1; s.prev[u.tag]=E[j].tag
t0=time.time(); bot=Exp()
res=run_game(maps.get(MAP),[Bot(Race.Terran,bot)],realtime=False,random_seed=SEED,game_time_limit=None)
rec={"map":MAP,"policy":POLICY,"seed":SEED,"step":STEP,"result":str(res),"score":bot.state.score.score,
     "final_loop":bot.state.game_loop,"decisions":bot.decisions,"orders":bot.orders,"maxF":bot.maxF,"maxE":bot.maxE,
     "py_decide_us":round(1e6*sum(bot.dts)/max(1,len(bot.dts)),1),"wall_s":round(time.time()-t0,1)}
open(OUT,"a").write(json.dumps(rec)+"\n"); print(rec)
