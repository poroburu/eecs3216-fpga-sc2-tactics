"""Run Icarus tests in a temporary directory; never generate expected bytes from RTL."""
import json
import os
from pathlib import Path
import random
import shlex
import subprocess
import tempfile
from make_fixtures import envelope, record, snapshot

ROOT = Path(__file__).resolve().parents[1]


def main():
    cases = json.loads((ROOT / "sim/fixtures/protocol.json").read_text())
    rng = random.Random(3216)
    for n in range(1000):
        nf, ne = rng.randrange(17), rng.randrange(17)
        def side(count, enemy):
            result = []
            for index in sorted(rng.sample(range(16), count)):
                hp = rng.randrange(1,65536)
                result.append(record(index, 0 if enemy else rng.randrange(2),
                                     rng.randrange(65536),rng.randrange(65536), hp,
                                     rng.randrange(hp,65536),rng.randrange(1,65536),rng.randrange(65536)))
            return result
        payload = snapshot(side(nf,False), side(ne,True), 16*65535)
        raw = envelope(2,1,n+1,payload)
        good = n % 4 != 0
        if not good:
            bad = bytearray(raw); bad[rng.randrange(14,len(raw))] ^= 1; raw = bytes(bad)
        cases.append(dict(name=f"random_{n}",hex=raw.hex(),request_ok=good,envelope_ok=good))
    with tempfile.TemporaryDirectory(prefix="fpga-sim-") as work:
        work = Path(work)
        lines = []
        for case in cases:
            data = bytes.fromhex(case["hex"])
            name = case["name"] + ".mem"
            (work / name).write_text("\n".join(f"{v:02x}" for v in data)+"\n")
            lines.append(f"{name} {len(data)} {int(case['request_ok'])} {int(case['envelope_ok'])}\n")
        (work / "manifest.txt").write_text("".join(lines))
        compiler = shlex.split(os.environ.get("IVERILOG", "iverilog"))
        runner = shlex.split(os.environ.get("VVP", "vvp"))
        for bench in ("tb_packet", "tb_uart"):
            output = work / bench
            sources = [ROOT / "sim" / (bench+".sv"), *sorted((ROOT/"rtl").glob("*.sv"))]
            subprocess.run([*compiler,"-g2012","-Wall","-s",bench,"-o",str(output),*map(str,sources)],check=True)
            subprocess.run([*runner,str(output)],cwd=work,check=True,timeout=60)


if __name__ == "__main__":
    main()
