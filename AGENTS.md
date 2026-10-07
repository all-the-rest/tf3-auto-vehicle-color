# AGENTS.md — tf3-auto-vehicle-color

## Goal

Vehicles automatically take the color of their line. If a vehicle is
assigned to a line or a line color changes, active vehicles are recolored
without manual repainting.

## Rule 0 — strictly event-driven, NO tick-based polling (user rule)

- `update()` in the game script exists for ONE purpose only: the
  `state:hasEventSubscriptions()` guard + `state:subscribeToEvent(...)`
  calls (base-game pattern, e.g. `arrivaltracker.script.tl`,
  `achievements.script.tl`). It must NEVER contain game logic, sweeps,
  timers, counters, or throttles.
- All sync logic runs in `handleEvent`, triggered ONLY by engine events:
  `TransportVehicleSystem` / `OnArriveAtStop` (param carries
  `vehicleEntity` + `lineEntity`), plus duck-typed params of other
  vehicle events (`OnCargoLoaded`, `OnCargoUnloaded`) via
  `extractVehicleLine`.
- Rationale: there is NO engine event for "vehicle assigned" or
  "line color changed" (verified: 0 hits in 1443 base-game script files),
  so convergence happens at the next arrival event per vehicle. This is
  accepted behavior, not a gap to be patched with polling.
- Rejected approaches (do NOT reintroduce): per-tick/per-N-tick sweeps,
  `os.clock` throttles, revision caches for sweeps, `guiUpdate` polling.

## GUI hook rules (assignment-time trigger, still zero ticks)

- The engine has no assign/buy/color-change event, so assignment-time
  reaction lives in the GUI state: `gui/hook.script.lua` wraps
  `api.cmd` factories (`^make.+Cmd$`, records kind+args per command
  object) and `sendCommand` — technique copied from TPF3MP `guard.lua`.
- Commands are NEVER blocked/altered, only observed. Follow-ups fire
  ONLY from a success callback; callback-less commands pass through
  (arrival fallback covers them).
- Loop safety by construction: follow-ups are sent WITHOUT callback and
  callback-less commands pass through, so they can never re-enter.
- Install once (module-load/first-recipe guard); recipe renders nothing.
- Pure decision logic lives in `gui/watch.lua` (`extractTargets`) and
  MUST stay headless-testable like `sync.lua`.

## API ground truth (verified against the installed game, build ~40408)
- Game script wiring: `content/*/*.gs.lua` descriptor with
  `updateScript` / `handleEventScript` pointing at
  `<name>.script@<fn>`; signatures `update(userParams, state, dt)` and
  `handleEvent(userParams, state, src, id, name, param)`.
- Engine reads: `api.engine.system.lineSystem.getLines()`,
  `api.engine.system.transportVehicleSystem.getLineVehicles(line)`,
  `api.engine.getComponent(entity, api.type.ComponentType.COLOR |
  TRANSPORT_VEHICLE)`. (`COLOR : ComponentType` confirmed in
  `api/tealdef`.)
- Recolor: `api.cmd.sendCommand(api.cmd.makeEntitySetColorCmd(entity,
  color))` — same call the vanilla vehicle window uses
  (`vehicle_eow.script.tl`). No callback needed.
- TPF2 APIs do NOT exist in TF3: `game.interface.*` (0 hits),
  `api.cmd.make.*` factory namespace (TF3 uses `make*Cmd`), bare
  `handleEvent(src, id, name, param)` in `data()`.
- Invented, non-existent event names (0 hits): `line.changed`,
  `api.cmd.LineModify`, `vehicle.changed`, `api.cmd.SetLine`.

## Decisions (user, 2026-10-07)

- Scope: only ACTIVE vehicles (`TransportVehicle.depot` nil/-1); depot
  vehicles are skipped.
- Manual vehicle colors are overwritten: line color always wins
  (enforced at the next event, manual `setColor` commands are never
  fought synchronously).
- Trigger must be assignment/purchase-time, NOT arrival: the correct
  color has to be visible immediately after buy+assign (also the only
  way to test it). Arrival recolor stays as fallback for script-driven
  and multiplayer-propagated changes.
- Tests: plain `lua tests/run.lua`, mocked `api`, zero dependencies.
- modId: `alltherest_auto_vehicle_color`.

## Workflow

- Pure logic lives in `content/auto_vehicle_color/sync.lua` and MUST stay
  headless-testable (no globals, context-injected `api`).
- `lua tests/run.lua` must be all-green before every commit.
- `luac -p` on all Lua files before every commit.
- Unverified-in-game items are listed in README.md and must stay marked
  until measured in the live game.
