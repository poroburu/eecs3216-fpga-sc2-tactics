# Linux headless SC2 and pinned C++ API

## Upstream sources

The repository includes [Blizzard/s2client-api](https://github.com/Blizzard/s2client-api)
as a Git submodule at `third_party/s2client-api`, pinned to
`614acc00abb5355e4c94a1b0279b46e9d845b7ce` (2019-08-22, latest protocol).
Its nested protocol and dependency revisions are pinned by that commit; keep
them at those revisions rather than updating each dependency to its latest tip.
Upstream source and license notices remain in the submodule.

The API README links to the official protocol repository's
[Linux headless downloads](https://github.com/Blizzard/s2client-proto#linux-packages)
and [Linux installation/launch instructions](https://github.com/Blizzard/s2client-proto/blob/master/docs/linux.md).
Follow the upstream license/download process on a new machine. The game data
and executable are external assets and must not be committed to this repository.

## Existing WSL installation

`~/StarCraftII` resolves to `/home/poroburu/dev/sc2/StarCraftII` on the verified
machine. `.build.info` identifies **4.10.0.75689**; the executable is
`Versions/Base75689/SC2_x64`, an x86-64 Linux ELF binary. All its dynamic libraries
resolve on this WSL installation. This is separate from Windows SC2 Base97563.
Use an explicit executable and map path to avoid selecting the Windows build.

The installation contains melee and minigame maps, including
`Maps/BelShirVestigeLE.SC2Map`. Linux paths are case-sensitive: use the actual
`Maps`/`maps` spelling in your installation. The melee map below is an API smoke
test, not the project's qualified Marine-versus-Zergling scenario.

## Initialize and build

From the repository root (CMake, a C/C++ compiler, make, and Git required):

```bash
git submodule update --init --recursive
cmake -S host/sc2 -B build/sc2 -DCMAKE_BUILD_TYPE=Release
cmake --build build/sc2 --target sc2_smoke -j 4
```

For a fresh checkout, `git clone --recurse-submodules <repository-url>` also
initializes the SDK and its nested dependencies. `host/sc2/CMakeLists.txt`
builds only the required SDK libraries and our smoke executable; upstream
examples/tests and renderer are excluded from that target. SDL feature checks
still run during upstream configuration. Generated files stay under ignored
`build/`; no installed SDK or upstream source patch is required.

## Run a bounded headless single-step check

Set the root to the existing installation; this does not download or modify it:

```bash
sc2_root="$HOME/StarCraftII"
timeout --kill-after=5s 90s build/sc2/bin/sc2_smoke \
  "$sc2_root/Versions/Base75689/SC2_x64" \
  "$sc2_root/Maps/BelShirVestigeLE.SC2Map"
```

The optional third argument is the SDK's port base (default 8168). This pinned
SDK launches its first client on base minus one, so the default binds 127.0.0.1:8167.
The SDK launches a headless client, pings it, creates/joins a non-realtime game,
observes the starting army, verifies eight one-loop steps, leaves the game and
terminates its own child process. Successful output includes `SC2_SMOKE_OK`,
the reported base build/data version, observed unit count and loop boundaries.
The check permits up to 64 startup loops if needed before its eight verified
steps, and records that startup count. It validates nonzero unique native tags
and positive health for visible self units in the SDK's raw observations.
Client/protocol errors or wrong loop increments fail the check. No unit orders,
FPGA requests or tactical decisions are issued. The outer timeout bounds startup
as well as play; the SDK also has a 20-second API timeout.

## Legacy SDK unit-conversion limitation

The installed client returns neutral snapshot units with cloak state zero
(`CloakedUnknown`). The pinned SDK's
[`sc2_proto_to_pods.cc`](https://github.com/Blizzard/s2client-api/blob/614acc00abb5355e4c94a1b0279b46e9d845b7ce/src/sc2api/sc2_proto_to_pods.cc)
does not handle that value, and its higher-level unit conversion stops at the
first such unit. In the verified run, the raw observation contained 13 valid
visible self units while `Observation()->GetUnits(Self)` returned zero.
This is not an empty squad. The smoke executable therefore reads
`Observation()->GetRawObservation()` and reports both counts. The future tactical
adapter must use validated raw facts or separately fix/qualify the converter;
it must not treat the converted empty list as a genuine game observation.
The submodule is unchanged; this limitation is recorded rather than hidden by
a local vendor modification.

See [verification](verification.md) for actual results. This establishes Linux
API launch/observe/step compatibility on one map; the micro scenario, native
action mapping and successful FPGA decision integration remain work for #4.
Windows COM5 still owns the UART adapter; running SC2 under WSL does not by itself
make that serial device a Linux tty. No USB forwarding or driver configuration
is changed by these instructions.
