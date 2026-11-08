# Simulation

`tb_sc2fpga.sv` drives the **top level through its UART pin**, the way the PC does. For
each vector it sets `SW0`, transmits the request serially, captures the reply from
`GPIO[1]`, and compares every byte with the reply computed by the independent Python
reference.

```bash
python3 host/gen_vectors.py        # regenerate sim/vectors/*.mem and host/vectors/*.jsonl
sim/run_verilator.sh               # all sets: directed (34), sc2_trace (182), random (1000)
```

Verilator 5 is required. One user-space install that works:

```bash
curl -sL https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xj bin/micromamba
./bin/micromamba create -y -p ~/.local/sc2fpga-sim -c conda-forge verilator gxx_linux-64 make
export PATH=~/.local/sc2fpga-sim/bin:$PATH
```

`run_sim.sh` runs the same testbench in Questa FSE on Windows. All three sets pass there too.
It needs the Questa Starter licence listed in the Windows user variable `SALT_LICENSE_SERVER`
(see [results](../docs/results.md)).

`tb_vga_frame.sv` captures one 640×480 frame from `VGA_R/G/B` into a PPM, and
`ppm2png.py` converts it to PNG. That is how `docs/img/vga_sim_p*.png` were made.

The vector format is one 12-bit hex word per line: `4pp` sets `SW0`, `1bb` is a request
byte, `2bb` is an expected reply byte, `300` runs the case, and `fff` ends the file.
