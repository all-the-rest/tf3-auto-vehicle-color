# AGENTS.md — tf3-auto-vehicle-color

**Rules only, no decisions:** This file contains rules only — directives
that apply to any work in this repo. Lasting decisions, rationales,
measurements and history do not belong here but in `docs/`/`features/` or
the project documentation; open items go to `AGENTS.todo.md`; completed
work goes to the Git history.

Context (product description, install, terms): `README.md`.

## Rule 0 — event-driven, no polling

- `update()` in the game script contains only (a) the
  `state:hasEventSubscriptions()` guard plus the `state:subscribeToEvent(...)`
  calls and (b) the one-time initial correction on the first call. Nothing
  else — no repeated sweeps, no timers, no counters, no throttles, no polling.
- The initial correction runs once per save: claim a marker in the shared
  script state (`state:get()`/`state:set()`), then recolor every vehicle of
  every line (`sync.syncAllLines`). Own lines first
  (`lineSystem.getLinesForPlayer(api.engine.util.getPlayer())`),
  `lineSystem.getLines()` as fallback.
- All sync logic runs in `handleEvent`, triggered only by engine events:
  `TransportVehicleSystem` / `OnArriveAtStop` (param carries `vehicleEntity`
  + `lineEntity`), plus the duck-typed params of `OnCargoLoaded` /
  `OnCargoUnloaded` via `extractVehicleLine`.
- Engine events are observed, not acted on (capped log line). There is no
  arrival fallback.
- Send commands only from `update()` or from scripting events (our own
  `recolor` event); never from engine events.
- Do not reintroduce: per-tick/per-N-tick sweeps, `os.clock` throttles,
  revision caches for sweeps, `guiUpdate` polling.

## GUI hook rules

- The engine has no assign/buy/color-change event, so assignment-time
  reaction lives in the GUI state: `gui/hook.script.lua` wraps the `api.cmd`
  factories (`^make.+Cmd$`, records kind+args per command object) and
  `sendCommand`.
- Commands are never blocked or altered, only observed. Follow-ups fire
  only from a success callback. Callback-less commands pass through
  unchanged, except the names listed in `gui/watch.lua` `CALLBACKLESS`,
  which get the hook's own success callback (currently only
  `makeVehicleReplaceCmd`).
- Loop safety by construction: follow-ups are sent without a callback and
  are not watched commands, so they always pass through untouched and can
  never re-enter.
- Install once (module-load/first-recipe guard); the recipe renders nothing.
- Pure decision logic lives in `gui/watch.lua` (`extractTargets`) and must
  stay headless-testable like `sync.lua`.
- The hook performs zero engine reads and forwards targets to the engine
  script.
- GUI -> engine happens only through `api.cmd.makeScriptingSendEventCmd`.
  Event id and event name live in `content/auto_vehicle_color/events.lua`
  and are imported by both sides — never hardcoded.

## API rules

- Game script wiring: a `content/*/*.gs.lua` descriptor with
  `updateScript` / `handleEventScript` pointing at `<name>.script@<fn>`;
  signatures `update(userParams, state, dt)` and
  `handleEvent(userParams, state, src, id, name, param)`. `fileName`
  resolves relative to the descriptor's own directory.
- Scripting events GUI -> engine: `api.cmd.makeScriptingSendEventCmd(src,
  id, name, param)`. The recipient receives it only if it called
  `state:subscribeToEvent(name)` — the 3rd argument, not `id`.
- `ComponentType` members are UPPER_SNAKE (`COLOR`, `TRANSPORT_VEHICLE`,
  `LINE`, `TOWN`, …). A camelCase key evaluates to nil, so
  `getComponent(entity, nil)` throws and every read silently becomes a
  no-op. Guard reads with `sync.resolveComponentTypes()`.
- Recolor with `api.cmd.sendCommand(api.cmd.makeEntitySetColorCmd(entity,
  color))`.
- Paint first, then compare: a vehicle may have no `COLOR` component until
  it has been painted once; never require a pre-existing vehicle color
  before painting. Line entities always carry a `COLOR` component.
- Unpaintable models exist (`vehicle.tv.noCblendMask == false`);
  `makeEntitySetColorCmd` may be a no-op for them.
- `api.type.LayerConfig.ColorPassFn.LineVehicleColor` is a display-time
  color pass, not persistent vehicle paint — do not use it for recoloring.
- Observed as-is (they carry a callback): `makeVehicleBuyCmd`,
  `makeVehicleSetLineCmd`, `makeLineCreateCmd` / `makeLineUpdateCmd`, the
  manager's multi-vehicle paint, and everything sent through
  `engine_react_util.useStepState` / `useStepStateMulti`. Callback-less, so
  the hook attaches its own callback: `makeVehicleReplaceCmd` and the
  single-vehicle paint bucket `makeEntitySetColorCmd`.
- Do not use TPF2 APIs in TF3: `game.interface.*`, the `api.cmd.make.*`
  factory namespace (TF3 uses `make*Cmd`), or a bare
  `handleEvent(src, id, name, param)`. These event names do not exist —
  do not use them: `line.changed`, `api.cmd.LineModify`, `vehicle.changed`,
  `api.cmd.SetLine`.
- Engine reads: `api.engine.system.lineSystem.getLines()`,
  `api.engine.system.transportVehicleSystem.getLineVehicles(line)`,
  `api.engine.getComponent(entity, api.type.ComponentType.*)`.
- GameScript entities are created only for mods in the running session's
  mod set. Diagnostics:
  `api.engine.system.gameScriptSystem.getEntityForGameScript("<modId>::/<path>.gs")`
  returns the game script entity; both `print` and `debugPrint` from
  engine-side scripts reach `crash_dump/stdout.txt`.
- The real mod version is `mod.json` `revision`. The mod.io modfile version
  stays "1.0" because the in-game Mod Hub upload sends no version — leave
  it.

## Behaviour rules

- Scope: recolor all vehicles of a line, depot vehicles included. Do not
  gate on active/on-road status (`sync.isInDepot` is diagnostics only).
- The line color always wins: manual vehicle colors are overwritten at the
  next event, but manual `setColor` commands are never fought
  synchronously.
- The line manager's "Replace vehicles" mode must recolor too.
- The trigger is assignment/purchase-time (GUI hook -> scripting event),
  not arrival: the correct color must be visible immediately after
  buy+assign.
- No silent no-ops: every path that does nothing returns a reason
  (`syncOne` -> `0, "already-line-color" | "not-on-this-line" |
  "line-read-failed" …`, `1, "recolored-first-time"` for a first paint,
  `syncLine` -> `0, "reason=count …", total`) and the engine script logs it.
- Do not reintroduce rejected approaches; the "Verworfen" list in
  `AGENTS.todo.md` is binding.

## Workflow

- Pure logic lives in `content/auto_vehicle_color/sync.lua` and must stay
  headless-testable (no globals, context-injected `api`).
- `lua tests/run.lua` must be all-green before every commit (plain lua,
  mocked `api`, zero dependencies).
- `luac -p` on all Lua files before every commit.
- Unverified-in-game items are listed in `README.md` and must stay marked
  until measured in the live game.
