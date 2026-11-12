#!/usr/bin/env python3
"""Generate test vectors for the ModelSim/Questa testbench and the on-board UART check.

usage: python3 host/gen_vectors.py [--random N]
writes sim/vectors/{directed,sc2_trace,random}.mem and host/vectors/*.jsonl
"""
import argparse, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from sc2fpga.vectors import directed, random_cases, trace_cases, write_mem, write_json

root = Path(__file__).resolve().parent.parent
ap = argparse.ArgumentParser(); ap.add_argument("--random", type=int, default=1000); a = ap.parse_args()
(root / "sim/vectors").mkdir(parents=True, exist_ok=True); (root / "host/vectors").mkdir(parents=True, exist_ok=True)
sets = {"directed": directed(),
        "sc2_trace": trace_cases(root / "explore/results/trace_focus_seed3.jsonl"),
        "random": random_cases(a.random)}
for name, cs in sets.items():
    write_mem(cs, root / f"sim/vectors/{name}.mem"); write_json(cs, root / f"host/vectors/{name}.jsonl")
    print(f"{name}: {len(cs)} cases")
