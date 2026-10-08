# AGENTS.md — tf3-auto-vehicle-color

## Goal

Vehicles automatically take the color of their line. If a vehicle is
assigned to a line or a line color changes, its vehicles are recolored
without manual repainting.

## Rule 0 — strictly event-driven, NO tick-based polling (user rule)

- `update()` in the game script contains ONLY two things: (a) the
  `state:hasEventSubscriptions()` guard + `state:subscribeToEvent(...)`
  calls (base-game pattern, e.g. `arrivaltracker.script.tl`,
  `achievements.script.tl`) and (b) the ONE-TIME initial correction on the
  first call (user decision, 2026-10-07). Nothing else — no repeated
  sweeps, no timers, no counters, no throttles, no polling.
- The initial correction runs ONCE PER SAVE: it claims a marker in the
  shared script state (`state:get()`/`state:set()`, shared across the
  simulation VMs and saved with the game), then recolors every vehicle of
  every line (`sync.syncAllLines`). Own lines first
  (`lineSystem.getLinesForPlayer(api.engine.util.getPlayer())`, verified in
  vanilla `loan.script.tl`), `lineSystem.getLines()` as fallback (used by
  engine scripts `achievements.script.tl`, `subvention_util.tl`). It
  covers the vehicles that already exist when a save is loaded.
- All sync logic runs in `handleEvent`, triggered ONLY by engine events:
  `TransportVehicleSystem` / `OnArriveAtStop` (param carries
  `vehicleEntity` + `lineEntity`), plus duck-typed params of other
  vehicle events (`OnCargoLoaded`, `OnCargoUnloaded`) via
  `extractVehicleLine`.
- Rationale: there is NO engine event for "vehicle assigned" or
  "line color changed" (verified: 0 hits in 1443 base-game script files),
  so the GUI hook is the trigger; arrival events cannot act (see below).
- COMMANDS ARE FORBIDDEN DURING ENGINE EVENTS (verified in-game, build
  40408): `api.cmd.sendCommand` from the `OnArriveAtStop` /
  `OnCargoLoaded` / `OnCargoUnloaded` branch raises
  `Engine.cpp:545 BeginModification: Assertion '!m_betweenChanges'
  failed` — a fatal error per call, each writing a stack trace to the log.
  With 1277 vehicles this made the game stutter badly. Vanilla only sends
  commands from `update()` or from SCRIPTING events
  (`finance/loan.script.tl` sends inside `handleEvent` only for
  `id == "Loan"`; `celebrations.script.tl` likewise). Scripting events are
  dispatched BETWEEN engine changes, so our own `recolor` event may send —
  and does (color verified working from that branch).
- Therefore engine events are OBSERVED, not acted on (capped log line).
  There is NO arrival fallback (user decision, 2026-10-07): after the
  one-time initial correction, only GUI-observed actions recolor.
- Rejected approaches (do NOT reintroduce): per-tick/per-N-tick sweeps,
  `os.clock` throttles, revision caches for sweeps, `guiUpdate` polling.

## GUI hook rules (assignment-time trigger, still zero ticks)

- The engine has no assign/buy/color-change event, so assignment-time
  reaction lives in the GUI state: `gui/hook.script.lua` wraps
  `api.cmd` factories (`^make.+Cmd$`, records kind+args per command
  object) and `sendCommand` — technique copied from TPF3MP `guard.lua`.
- Commands are NEVER blocked/altered, only observed. Follow-ups fire
  ONLY from a success callback. Commands the game sends callback-less
  pass through UNCHANGED — with ONE exception: the names listed in
  `gui/watch.lua` `CALLBACKLESS` get the hook's own success callback
  attached, because the game sends them fire-and-forget and they would
  otherwise never be observed (user decision, 2026-10-08: only
  `makeVehicleReplaceCmd`).
- Loop safety by construction: follow-ups are sent WITHOUT callback and
  are NOT watched commands, so they always pass through untouched and can
  never re-enter.
- Install once (module-load/first-recipe guard); recipe renders nothing.
- Pure decision logic lives in `gui/watch.lua` (`extractTargets`) and
  MUST stay headless-testable like `sync.lua`.
- The hook performs ZERO engine reads and forwards targets to the engine
  script. (Earlier "the GUI state cannot read components" was WRONG: that
  failure was the camelCase ComponentType key, not the GUI state. Not
  re-verified since the bridge works — do not "fix" it from that claim.)
- GUI -> engine happens ONLY through `api.cmd.makeScriptingSendEventCmd`.
  Event id and event name live in `content/auto_vehicle_color/events.lua`
  and are imported by BOTH sides — never hardcoded. Rationale: the
  engine subscribes to the event NAME (see API ground truth); a literal
  in one file only is exactly the bug that cost a debugging session.

## API ground truth (verified against the installed game, build ~40408)
- Game script wiring: `content/*/*.gs.lua` descriptor with
  `updateScript` / `handleEventScript` pointing at
  `<name>.script@<fn>`; signatures `update(userParams, state, dt)` and
  `handleEvent(userParams, state, src, id, name, param)`.
  (`fileName` resolves relative to the descriptor's own directory, like
  `just_more_weather_1::/rct/service.gs` -> `service.script@update`.)
- Scripting events GUI -> engine: `api.cmd.makeScriptingSendEventCmd(
  src, id, name, param)`. The recipient receives it as `handleEvent(...,
  id, name, param)` ONLY IF it called `state:subscribeToEvent(name)` —
  the 3rd argument, NOT `id`. Base-game proof:
  `game_time.script.tl` subscribes `"SetMode"`/`"SkipPhase"` and then
  filters `if id == "GameTime" and name == "SetMode"`. Third-party
  proof: `just_more_weather_1::/rct/service.script.lua` subscribes its
  `EV_*` names (id `"RealClockService"`).
- GameScript entities are created ONLY for mods in the running session's
  mod set (`crash_dump` log: `Creating entity for GameScript <mod>::/…`).
- Diagnostics from the GUI state: `api.engine.system.gameScriptSystem
  .getEntityForGameScript("<modId>::/<path>.gs")` returns the game
  script entity (proven: 342266) — usable to check wiring at runtime.
- Both `print` and `debugPrint` from engine-side mod game scripts reach
  `crash_dump/stdout.txt`; `print` writes a bare line, `debugPrint` a
  timestamped `MESSAGE` line.
- Engine reads: `api.engine.system.lineSystem.getLines()`,
  `api.engine.system.transportVehicleSystem.getLineVehicles(line)`,
  `api.engine.getComponent(entity, api.type.ComponentType.COLOR |
  TRANSPORT_VEHICLE)`.
- `ComponentType` members are UPPER_SNAKE (`COLOR`, `TRANSPORT_VEHICLE`,
  `LINE`, `TOWN`, …; `enum ComponentType` in
  `api/tealdef/api/engine.d.tl`). A camelCase key (`.Color`) evaluates to
  nil, so `getComponent(entity, nil)` throws "Error decoding argument #3"
  and EVERY read silently becomes a no-op — no recolor, no error, no
  log. Guarded by `sync.resolveComponentTypes()`, which returns the
  missing member name instead of nil values.
- Recolor: `api.cmd.sendCommand(api.cmd.makeEntitySetColorCmd(entity,
  color))` — same call the vanilla vehicle window uses
  (`gui/entity_window/vehicle/vehicle_eow.script.tl`). No callback needed.
- A VEHICLE ENTITY OFTEN HAS NO `COLOR` COMPONENT YET:
  `getComponent(vehicle, COLOR)` returns nil (no error) until the vehicle
  has been painted once; that command is what creates the component.
  Requiring a pre-existing vehicle color before painting was the third
  silent bug (`vehicle-has-no-color` for all 27 vehicles of a line).
  Paint first, then compare. Line entities, by contrast, always carry a
  `COLOR` component.
- Vanilla disables the paint bucket when the model has no color mask
  (`vehicle.tv.noCblendMask == false`): unpaintable models exist, and
  `makeEntitySetColorCmd` may be a no-op for them.
- The game has a render-time line-color pass for vehicles
  (`api.type.LayerConfig.ColorPassFn.LineVehicleColor`, used by HUD,
  statistics and highlight layers). It is a *display* color pass, not a
  persistent vehicle paint — do not mistake it for the recolor API.
- TPF2 APIs do NOT exist in TF3: `game.interface.*` (0 hits),
  `api.cmd.make.*` factory namespace (TF3 uses `make*Cmd`), bare
  `handleEvent(src, id, name, param)` in `data()`.
- Invented, non-existent event names (0 hits): `line.changed`,
  `api.cmd.LineModify`, `vehicle.changed`, `api.cmd.SetLine`.
- WHICH GUI COMMANDS CARRY A CALLBACK (read from the shipped `gui.zip`,
  build 40408) decides what the hook can observe:
  - callback-LESS (fire-and-forget), so the hook must attach its own:
    `makeVehicleReplaceCmd` (`gui/line_vehicle_mgmt/vehicle_react_util.tl:407`,
    the line manager's "Replace vehicles" mode via `HandleVehicleChanges`,
    called at `manager_window.tl:8549`) and the single-vehicle paint bucket
    `makeEntitySetColorCmd` (`gui/entity_window/vehicle/vehicle_eow.script.tl:150`).
  - WITH callback (observed as-is): `makeVehicleBuyCmd` +
    `makeVehicleSetLineCmd` (`vehicle_react_util.tl:350`/`:376`),
    `makeVehicleSetLineCmd` in the manager (`manager_window.tl:4752`),
    `makeLineCreateCmd`/`makeLineUpdateCmd` (`manager_window.tl:6537`/`:6558`),
    the manager's multi-vehicle paint (`manager_window.tl:5072`).
  - Also with callback: everything sent through
    `engine_react_util.useStepState`/`useStepStateMulti`, because those
    ALWAYS pass a wrapper function (`gui/main/engine_react_util.tl:37-54`) —
    that is why the line colour pickers (`line.tl:84`,
    `line_react_util.tl:597`) are observed even though their own
    result handler is nil.
- Mod Hub -> mod.io (measured 2026-10-08, mod 6434391): the in-game upload
  sends NO version string — the uploaded metadata is only `buildVersion`,
  `level`, `modType`, `uploadedFromPlatform`. So mod.io keeps its default
  modfile `version = "1.0"`, and EVERY TF3 mod in the local mod.io cache
  shows 1.0, official Urban Games mods included. That field is therefore
  NOT the mod's version: the real version is `mod.json` `revision` (logged
  as `runtimeRevision`, used by the game for update detection). A new
  upload creates a new modfile (new `id`, new `date_added`, `changelog`)
  and the page's "Last updated" changes; the 1.0 stays. Decision (user,
  2026-10-08): leave it — changing the modfile version needs the mod.io
  REST API (`edit-modfile`), not the in-game Mod Hub.

## Decisions (user, 2026-10-07)

- Scope: ALL vehicles of the line, depot vehicles included
  (`TransportVehicle.depot` holds the depot entity while parked, nil/-1
  on the road). The depot gate was dropped (user, 2026-10-07, confirmed
  in-game): right after buy+assign the vehicle is still parked
  (`depot=147161`), so an active-only rule can never make the color
  visible immediately, and the depot list/vehicle window read the same
  color component. `sync.isInDepot` is kept for diagnostics only.
- Manual vehicle colors are overwritten: line color always wins
  (enforced at the next event, manual `setColor` commands are never
  fought synchronously).
- Replace (user decision, 2026-10-08): the line manager's "Replace
  vehicles" mode must recolor too. Measured gap: the game sends
  `makeVehicleReplaceCmd` WITHOUT a callback, so the hook never saw it
  (log: `hook installed`, replace performed, zero `committed:` lines).
  Fix: `watch.CALLBACKLESS = { makeVehicleReplaceCmd = true }` — only this
  one command gets the hook's own success callback. The single-vehicle
  paint bucket stays callback-less/pass-through on purpose (see above).
- Trigger is assignment/purchase-time (GUI hook -> scripting event),
  NOT arrival: the correct color has to be visible immediately after
  buy+assign. Verified working 2026-10-07: the tram takes the line color
  right after buy+assign, and a line color change recolors the fleet.
- Arrival fallback: DROPPED (user decision, 2026-10-07). Instead a
  ONE-TIME initial correction at session start repaints the existing
  vehicles; after that only GUI-observed actions recolor. Reason: commands
  are illegal during engine events (fatal assertion + stutter).
- Reverse rule (vehicles -> line): REJECTED (user, 2026-10-07). See the
  "Verworfen" section — it cannot be triggered while the forward rule
  holds.
- Tests: plain `lua tests/run.lua`, mocked `api`, zero dependencies.
- NO SILENT NO-OPS: every path that does nothing returns a reason
  (`syncOne` -> `0, "already-line-color" | "not-on-this-line" |
  "line-read-failed" …`, `1, "recolored-first-time"` for a first paint,
  `syncLine` -> `0, "reason=count …", total`) and the engine script logs
  it. Two real
  bugs (missing event subscription, camelCase ComponentType keys) stayed
  invisible for hours precisely because a no-op looked like success.
- modId: `alltherest_auto_vehicle_color`.

## Verworfen — nicht wieder einführen

- **Umgekehrte Regel** (alle Fahrzeuge einer Linie haben eine Farbe →
  Linienfarbe übernehmen), user-Entscheid 2026-10-07. Begründung: sie
  widerspricht der geltenden Regel „Linienfarbe gewinnt immer" — manuell
  gefärbte Fahrzeuge werden sofort überschrieben, Unanimität ist vom
  Spieler also nie herstellbar und die Regel hätte keinen Auslöser.
- **Ankunfts-Fallback** (recolor aus `OnArriveAtStop`/Cargo-Events):
  Commands sind während Engine-Events verboten (Fatal-Assertion +
  Stutter). Ersetzt durch die Einmal-Korrektur beim Session-Start.
- **Polling-Ansätze**: Tick-/N-Tick-Sweeps, `os.clock`-Throttles,
  Revision-Caches für Sweeps, `guiUpdate`-Polling (Rule 0).
- **Engine-Reads im GUI-Hook**: Der frühere Fehlschlag war der
  camelCase-Key, nicht der GUI-State. Die Bridge über Scripting-Events ist
  bewiesen — nicht ohne gemessenen Grund umbauen.
- **Erfundene APIs**: `game.interface.*`, `api.cmd.make.*`, Event-Namen
  `line.changed` / `api.cmd.SetLine` (in TF3 nicht vorhanden, 0 Treffer in
  1443 Basis-Script-Dateien).

## Workflow

- Pure logic lives in `content/auto_vehicle_color/sync.lua` and MUST stay
  headless-testable (no globals, context-injected `api`).
- `lua tests/run.lua` must be all-green before every commit.
- `luac -p` on all Lua files before every commit.
- Unverified-in-game items are listed in README.md and must stay marked
  until measured in the live game.
