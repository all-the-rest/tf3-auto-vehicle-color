# Auto Vehicle Color (Transport Fever 3)

Vehicles automatically take the color of their line. When a vehicle is
assigned to a line or a line color changes, active vehicles are recolored
at their next arrival event — no manual repainting, no polling.

- Scope: only **active** vehicles (parked/depot vehicles are skipped).
- Manual vehicle colors are **overwritten** — the line color wins at the
  next event.
- Mod ID: `alltherest_auto_vehicle_color`

## How it works (strictly event-driven, see AGENTS.md Rule 0)

`update()` only subscribes to engine events (base-game pattern). All
logic runs in `handleEvent`:

- `TransportVehicleSystem` / `OnArriveAtStop` — param carries
  `vehicleEntity` + `lineEntity` (same shape the vanilla achievements
  script consumes). The vehicle is recolored to its line color via
  `api.cmd.makeEntitySetColorCmd` — the exact call the vanilla vehicle
  window uses. Sending commands from `handleEvent` is vanilla-sanctioned
  (cf. `loan.script.tl`: `Obtain`/`Repay` → `sendCommand` with callback).
- `OnCargoLoaded` / `OnCargoUnloaded` — same single-vehicle path,
  duck-typed.

Why this converges without polling: an assigned vehicle drives to its
first stop → event → recolor. A line color change reaches every active
vehicle at its next stop. There is NO engine event for "vehicle
assigned" or "line color changed" (verified: 0 hits in 1443 base-game
script files), so arrival events are the canonical trigger.

## Layout (TF3 mod format)

```
AGENTS.md                                           rules + verified API ground truth
mod.json                                            modId, revision, scripts
_metadata/modinfo.json                              browser name/description
content/auto_vehicle_color/sync.lua                 pure logic (testable)
content/auto_vehicle_color/auto_vehicle_color.gs.lua      game script wiring
content/auto_vehicle_color/auto_vehicle_color.script.lua engine entry point
tests/run.lua                                       headless unit tests
```

## Tests (no game needed)

```sh
lua tests/run.lua
```

Pure logic + mocked `api.engine` / `api.cmd`. 10 cases: recolor,
match-skip, depot-skip, foreign-line-skip, nil-safety, error survival,
event gating (incl. rejecting invented `line.changed` /
`api.cmd.SetLine` names), event duck-typing, helpers.

## In-game verification (still needed)

`TransportVehicle.depot` nil/-1 convention and the arrival-event flow
are best-effort from docs + third-party mods and **not yet measured in
the live game**. To verify:

1. Install the mod folder as a TF3 mod, start a save.
2. Assign a bus to a colored line → recolored at its first stop.
3. Change the line color → vehicles follow at their next stops.
4. Open the console (`debugPrint`) if behavior differs.

## Sources

- Installed game files (`steamapps/common/Transport Fever 3/base`):
  `arrivaltracker.script.tl`, `achievements.script.tl`, `loan.script.tl`,
  `vehicle_eow.script.tl`, `api/tealdef` — read-only, never modified.
- https://wiki.transportfever3.com/script-doc/ (`api/cmd`, `api/engine`,
  `api/engine/system`, `content/scripts/gamescript`)
- TPF3MP investigation docs (game-script signatures, command capture)
