# Auto Vehicle Color (Transport Fever 3)

Vehicles automatically take the color of their line. When a vehicle is
assigned to a line or a line color changes, active vehicles are recolored
without manual repainting.

- Scope: only **active** vehicles (parked/depot vehicles are skipped).
- Manual vehicle colors are **overwritten** — the line color always wins.
- Mod ID: `alltherest_auto_vehicle_color`

## How it works

No documented engine event exists for "vehicle assigned" or "line color
changed" ([script-doc](https://wiki.transportfever3.com/script-doc/),
verified Oct 2026), so the mod is a hybrid:

1. **Event fast path** — `handleEvent` recolors a single vehicle (O(1))
   the moment an engine event carrying `vehicleEntity + lineEntity`
   arrives (e.g. `OnArriveAtStop`). Param duck-typing keeps it robust
   against exact src/name strings.
2. **Throttled sweep fallback** — `update` runs `syncAll` at most every
   3 s (real time via `os.clock`, so it also works while paused) with a
   line-color + entity-revision cache. Steady state costs ~1 cheap call
   per vehicle and sends commands only on actual mismatch.

Recoloring uses the documented `api.cmd.makeEntitySetColorCmd`, reading
via `api.engine.getComponent` (`Color`, `TransportVehicle`) and
`transportVehicleSystem.getLineVehicles` / `lineSystem.getLines`.

## Layout (TF3 mod format)

```
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

Pure logic + mocked `api.engine` / `api.cmd`. 12 cases: recolor,
match-skip, depot-skip, foreign-line-skip, line-change follow-up,
new-assignment catch, cache silence, error survival, event duck-typing.

## In-game verification (still needed)

`os.clock` throttle, `subscribeToEvent("OnArriveAtStop")` string, and
`TransportVehicle.depot` nil/-1 convention are best-effort from docs +
third-party mods and **not yet measured in the live game**. To verify:

1. Install the mod folder as a TF3 mod, start a save.
2. Assign a bus to a colored line → recolored within ~3 s.
3. Change the line color → vehicles follow within ~3 s / at next stop.
4. Open the console (`debugPrint`) if behavior differs; likely suspects
   are the event name string and the depot-field convention.

## Sources

- https://wiki.transportfever3.com/doku.php?id=modding:start&redirect=1
- https://wiki.transportfever3.com/script-doc/ (`api/cmd`, `api/engine`,
  `api/engine/system`, `content/scripts/gamescript`)
- TPF3MP investigation docs (game-script signatures, command capture)
