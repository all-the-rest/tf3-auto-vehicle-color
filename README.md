# Auto Vehicle Color (Transport Fever 3)

Vehicles automatically take the color of their line. When a vehicle is
assigned to a line or a line color changes, active vehicles are recolored
at their next arrival event — no manual repainting, no polling.

- Scope: only **active** vehicles (parked/depot vehicles are skipped).
- Manual vehicle colors are **overwritten** — the line color wins at the
  next event.
- Mod ID: `alltherest_auto_vehicle_color`

## How it works (strictly event-driven, see AGENTS.md Rule 0)

Two triggers, zero polling:

1. **Assignment-time (GUI hook)** — `gui/hook.script.lua` wraps
   `api.cmd` factories + `sendCommand` (technique copied from TPF3MP's
   `guard.lua`). When `makeVehicleSetLineCmd`, `makeVehicleReplaceCmd`,
   `makeVehicleBuyCmd`, `makeLineUpdateCmd` or a line-targeted
   `makeEntitySetColorCmd` commits successfully, the affected
   vehicle(s) are recolored immediately — visible right after buy+assign.
   Commands are never blocked, only observed; without a success callback
   nothing happens (arrival fallback covers it).
2. **Arrival fallback (engine script)** — `TransportVehicleSystem` /
   `OnArriveAtStop` (+ cargo events) recolor one vehicle via `syncOne`.
   Covers script-driven and multiplayer-propagated changes.

`update()` only subscribes to engine events (base-game pattern). All
follow-ups read current engine state and act only on color mismatch.

Why this shape: there is NO engine event for "vehicle assigned" or
"line color changed" (verified: 0 hits in 1443 base-game script files).

## Layout (TF3 mod format)

```
AGENTS.md                                           rules + verified API ground truth
mod.json                                            modId, revision, scripts
_metadata/modinfo.json                              browser name/description
content/auto_vehicle_color/sync.lua                 pure logic (testable)
content/auto_vehicle_color/auto_vehicle_color.gs.lua      game script wiring
content/auto_vehicle_color/auto_vehicle_color.script.lua engine entry point
content/auto_vehicle_color/gui/hook.res.lua             react-plugin descriptor
content/auto_vehicle_color/gui/hook.script.lua          sendCommand wrapper (observe-only)
content/auto_vehicle_color/gui/watch.lua                command -> targets (testable)
tests/run.lua                                       headless unit tests
```

## Tests (no game needed)

```sh
lua tests/run.lua
```

Pure logic + mocked `api.engine` / `api.cmd`. 21 cases: recolor,
match-skip, depot-skip, foreign-line-skip, nil-safety, error survival,
event gating (incl. rejecting invented `line.changed` /
`api.cmd.SetLine` names), event duck-typing, command→target mapping,
helpers.

## In-game verification (still needed)

Install (symlinked, no copy step — repo edits apply after game restart):

```sh
ln -s ~/dev/tf3-auto-vehicle-color "/Users/florianreisinger/Library/Application Support/Steam/steamapps/common/Transport Fever 3/mods/alltherest_auto_vehicle_color"
```

Then: enable debug mode (`debugMode = true` in
`Steam/userdata/84701780/3493540/local/settings.lua`, or game settings →
advanced), activate the mod for a save, open the console with `^`/`§`/`
(below ESC) — it mirrors `stdout.txt` and runs Lua one-liners.

Unverified in the live game and marked as such:

1. Install the mod folder as a TF3 mod, start a save.
2. Buy + assign a vehicle → correct line color immediately.
3. Change the line color → vehicles follow immediately.
4. Arrival fallback: script-driven changes converge at next stop.
5. Open the console (`debugPrint`) if behavior differs; likely suspects:
   `TransportVehicle.depot` convention, factory-wrap visibility of
   command objects, plugin load order vs. other GUI mods.

## Sources

- Installed game files (`steamapps/common/Transport Fever 3/base`):
  `arrivaltracker.script.tl`, `achievements.script.tl`, `loan.script.tl`,
  `vehicle_eow.script.tl`, `api/tealdef` — read-only, never modified.
- https://wiki.transportfever3.com/script-doc/ (`api/cmd`, `api/engine`,
  `api/engine/system`, `content/scripts/gamescript`)
- TPF3MP investigation docs (game-script signatures, command capture)
