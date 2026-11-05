# Scenario and benchmark setup

Status: planned; no downloaded map or scenario has been qualified.

Start with [AI Arena micro maps](https://aiarena.net/wiki/maps/) and inspect the
[editable source](https://github.com/aiarena/micro-ladder-maps) if a minimal
adaptation is necessary. Existing default rounds are not assumed to fit our model.

## Required initial scope

- 4–8 friendly Marines against 4–8 Zerglings.
- Open terrain, no upgrades or abilities, and authored objective/safety waypoints.
- Hardware capacity is 16 records per side; reject unsupported/oversized input.
- SC2 single-step mode with a recorded fixed decision interval.

## Intended cases

1. **Approach/engagement:** begin outside attack range; show advance to attack.
2. **Allocation:** choose a qualified arrangement with unequal enemy health;
   inspect deterministic ranking and reservations before resuming combat.
3. **Retreat:** use a force/health disadvantage that crosses the defined threshold;
   show movement to safety and holding on arrival.

Vary starting positions, health, and force balance within the supported model.
Actual positions, seeds, unit properties, and map settings are selected only after
the map/client smoke test; do not invent them from a diagram.

## Qualification record to add

- Map path, upstream source/version, file hash, and modifications.
- SC2 client/build/data version, API revision, host/policy revisions.
- Actual spawned units, ownership, positions, health, upgrades, abilities, and visibility.
- Round start/end/reset rules and index/tag remapping behavior.
- Objective/safety waypoint coordinates and walkability.
- Step interval, seed where supported, stop conditions, and outcome rules.

## Comparisons

Run the FPGA policy, Attack-Closest, and a qualified MarineMicroBot policy on
matched starts with the same opponent. Preserve the Marine-versus-Zergling roles
when swapping layouts. Comparing differently configured armies against each
other is not an isolated controller comparison.

Record all runs and validity failures, not only wins. A new map/client/policy
revision needs renewed relevant checks before results are compared.
