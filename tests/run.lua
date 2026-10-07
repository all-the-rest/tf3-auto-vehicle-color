-- Headless unit tests for Auto Vehicle Color. No game, no dependencies:
--   lua tests/run.lua
-- Mocks api.engine / api.cmd with plain tables.

local sync = dofile("content/auto_vehicle_color/sync.lua")
local watch = dofile("content/auto_vehicle_color/gui/watch.lua")
local events = dofile("content/auto_vehicle_color/events.lua")

local passed, failed = 0, 0
local function check(name, cond)
  if cond then
    passed = passed + 1
    print("PASS " .. name)
  else
    failed = failed + 1
    print("FAIL " .. name)
  end
end

-- Verified member names: UPPER_SNAKE (api/tealdef/api/engine.d.tl).
local CT = { COLOR = 1, TRANSPORT_VEHICLE = 2, LINE = 3 }

local function C(x, y, z) return { x = x, y = y, z = z } end

-- Builds a mock context. Records every setColor command in ctx.sent.
local function mock(opts)
  opts = opts or {}
  local sent = {}
  local api = {
    engine = {
      system = {
        transportVehicleSystem = {
          getLineVehicles = function(line)
            return (opts.lineVehicles or {})[line] or {}
          end,
        },
      },
      getComponent = function(entity, ct)
        if opts.throwGet then error("boom") end
        if ct == CT.COLOR then
          local c = (opts.lineColor or {})[entity] or (opts.vehColor or {})[entity]
          if c then return { color = c } end
          return nil
        end
        if ct == CT.TRANSPORT_VEHICLE then
          return (opts.tv or {})[entity]
        end
        return nil
      end,
    },
    cmd = {
      makeEntitySetColorCmd = function(entity, color)
        return { entity = entity, color = color }
      end,
      sendCommand = function(cmd) sent[#sent + 1] = cmd end,
    },
  }
  return { api = api, componentType = CT, sent = sent }
end

-- 1: mismatched active vehicle is recolored to the line color
do
  local red, blue = C(1, 0, 0), C(0, 0, 1)
  local ctx = mock({
    lineColor = { [10] = red },
    tv = { [100] = { line = 10, depot = nil } },
    vehColor = { [100] = blue },
  })
  local n = sync.syncOne(ctx, 100, 10)
  check("syncOne recolors mismatch", n == 1 and #ctx.sent == 1
    and ctx.sent[1].entity == 100 and ctx.sent[1].color == red)
end

-- 2: already matching vehicle sends nothing
do
  local red = C(1, 0, 0)
  local ctx = mock({
    lineColor = { [10] = red },
    tv = { [100] = { line = 10 } },
    vehColor = { [100] = C(1, 0, 0) },
  })
  check("syncOne skips match", sync.syncOne(ctx, 100, 10) == 0 and #ctx.sent == 0)
end

-- 3: depot vehicles are recolored too (user decision 2026-10-07):
-- the color has to be right right after buy+assign, and the depot list
-- reads the same color component.
do
  local red = C(1, 0, 0)
  local ctx = mock({
    lineColor = { [10] = red },
    tv = { [100] = { line = 10, depot = 55 } },
    vehColor = { [100] = C(0, 0, 1) },
  })
  local n = sync.syncOne(ctx, 100, 10)
  check("syncOne recolors depot vehicle", n == 1 and #ctx.sent == 1
    and ctx.sent[1].entity == 100 and ctx.sent[1].color == red)
end

-- 4: vehicle mapped to a different line is skipped
do
  local ctx = mock({
    lineColor = { [10] = C(1, 0, 0) },
    tv = { [100] = { line = 11 } },
    vehColor = { [100] = C(0, 0, 1) },
  })
  check("syncOne skips foreign line", sync.syncOne(ctx, 100, 10) == 0 and #ctx.sent == 0)
end

-- 5: nil-safe
do
  local ctx = mock({})
  check("syncOne nil-safe", sync.syncOne(ctx, nil, nil) == 0
    and sync.syncOne({}, 1, 2) == 0 and sync.syncOne(ctx, 1, nil) == 0)
end

-- 6: broken engine API degrades to 0, never throws
do
  local ctx = mock({ throwGet = true })
  local ok, n = pcall(sync.syncOne, ctx, 100, 10)
  check("syncOne survives engine errors", ok and n == 0 and #ctx.sent == 0)
end

-- 6b: every no-op reports WHY (silence hid two real bugs)
do
  local red = C(1, 0, 0)
  local function reasonOf(opts, vehicle, line)
    local ctx = mock(opts)
    local n, reason = sync.syncOne(ctx, vehicle, line)
    return n, reason
  end
  local n1, r1 = reasonOf({}, nil, nil)
  check("reason: missing arguments", n1 == 0 and r1 == "missing-arguments")

  local n2, r2 = reasonOf({ tv = { [100] = { line = 10 } } }, 100, 10)
  check("reason: line has no color", n2 == 0 and r2 == "line-has-no-color")

  local n3, r3 = reasonOf({ lineColor = { [10] = red } }, 100, 10)
  check("reason: vehicle unreadable", n3 == 0 and r3 == "vehicle-read-failed")

  local n4, r4 = reasonOf({ lineColor = { [10] = red }, tv = { [100] = { line = 11 } } }, 100, 10)
  check("reason: foreign line", n4 == 0 and r4 == "not-on-this-line")

  local n5, r5 = reasonOf({ lineColor = { [10] = red }, tv = { [100] = { line = 10 } } }, 100, 10)
  check("reason: vehicle has no color component", n5 == 0 and r5 == "vehicle-has-no-color")

  local n6, r6 = reasonOf({
    lineColor = { [10] = red }, tv = { [100] = { line = 10 } }, vehColor = { [100] = red },
  }, 100, 10)
  check("reason: already line color", n6 == 0 and r6 == "already-line-color")

  local ok = sync.syncOne(mock({ throwGet = true }), 100, 10)
  local n7, r7 = sync.syncOne(mock({ throwGet = true }), 100, 10)
  check("reason: engine read failed", ok == 0 and n7 == 0 and r7 == "line-read-failed")

  local ctx8 = mock({ lineColor = { [10] = red }, tv = { [100] = { line = 10 } }, vehColor = { [100] = C(0,0,1) } })
  ctx8.api.cmd.sendCommand = function() error("nope") end
  local n8, r8 = sync.syncOne(ctx8, 100, 10)
  check("reason: command failed", n8 == 0 and r8 == "command-failed")

  check("reason: success", (select(2, sync.syncOne(mock({
    lineColor = { [10] = red }, tv = { [100] = { line = 10 } }, vehColor = { [100] = C(0,0,1) },
  }), 100, 10))) == "recolored")
end

-- 6c: line/entity summaries (a silent 0/7 was invisible before)
do
  local red, blue = C(1, 0, 0), C(0, 0, 1)
  local ctx = mock({
    lineColor = { [10] = red },
    tv = { [100] = { line = 10 }, [101] = { line = 10 }, [102] = { line = 11 } },
    vehColor = { [100] = blue, [101] = red, [102] = blue },
    lineVehicles = { [10] = { 100, 101, 102 } },
  })
  local sent, summary, total = sync.syncLine(ctx, 10)
  check("syncLine reports sent/summary/total", sent == 1 and total == 3
    and summary == "already-line-color=1 not-on-this-line=1 recolored=1")
  check("syncLine nil-safe", (select(2, sync.syncLine(ctx, nil))) == "missing-arguments")

  local s2, sum2, t2 = sync.syncLine(mock({}), 10)
  check("syncLine without vehicles reports no-vehicles", s2 == 0 and t2 == 0 and sum2 == "no-vehicles")

  check("summarize is deterministic", sync.summarize({ b = 2, a = 1 }) == "a=1 b=2"
    and sync.summarize({}) == "")

  local s3, sum3, t3 = sync.syncEntity(mock({}), 999)
  check("syncEntity reports unknown entity", s3 == 0 and t3 == 0 and sum3 == "not-a-line-or-line-vehicle")
end

-- 7: event gate matches base-game pattern, rejects the rest
do
  check("shouldHandleEvent gates", sync.shouldHandleEvent("TransportVehicleSystem", "OnArriveAtStop") == true
    and sync.shouldHandleEvent("TransportVehicleSystem", "OnCargoLoaded") == true
    and sync.shouldHandleEvent("TransportVehicleSystem", "OnCargoUnloaded") == true
    and sync.shouldHandleEvent("SimPersonSystem", "OnStartedLineUsage") == false
    and sync.shouldHandleEvent("TransportVehicleSystem", "line.changed") == false
    and sync.shouldHandleEvent("TransportVehicleSystem", "api.cmd.SetLine") == false
    and sync.shouldHandleEvent(nil, nil) == false)
end

-- 8: event param duck-typing (ArriveAtStop shape included)
do
  local v, l = sync.extractVehicleLine({ vehicleEntity = 5, lineEntity = 6, stopIndex = 2, lastStopIndex = 1 })
  local v2, l2 = sync.extractVehicleLine({ vehicle = 7, line = 8 })
  local v3, l3 = sync.extractVehicleLine({ stopIndex = 2 })
  local v4, l4 = sync.extractVehicleLine("nope")
  check("extractVehicleLine duck-types", v == 5 and l == 6 and v2 == 7 and l2 == 8
    and v3 == nil and v4 == nil)
end

-- 9: helpers
do
  check("isInDepot", sync.isInDepot(nil) == false and sync.isInDepot({ depot = 3 }) == true
    and sync.isInDepot({ depot = -1 }) == false and sync.isInDepot({}) == false)
  check("sameColor epsilon + index access",
    sync.sameColor(C(1, 0, 0), C(1 + 1e-3, 0, 0)) == true
    and sync.sameColor(C(1, 0, 0), { 1, 0, 0 }) == true
    and sync.sameColor({ 1, 0, 0 }, C(0, 0, 1)) == false
    and sync.sameColor(nil, C(0, 0, 0)) == false)
end

-- watch.lua: command -> recolor targets (GUI hook decision logic)
do
  local t = watch.extractTargets("makeVehicleSetLineCmd", { [1] = 100, [2] = 10, [3] = 0, n = 3 }, {})
  check("watch setLine", #t == 1 and t[1].vehicle == 100 and t[1].line == 10)

  t = watch.extractTargets("makeVehicleReplaceCmd", { [1] = 100, n = 2 }, { vehicleEntity = 200 })
  check("watch replace prefers result", #t == 1 and t[1].vehicle == 200 and t[1].line == nil)
  t = watch.extractTargets("makeVehicleReplaceCmd", { [1] = 100, n = 2 }, {})
  check("watch replace falls back to args", #t == 1 and t[1].vehicle == 100)

  t = watch.extractTargets("makeVehicleBuyCmd", { n = 3 }, { resultVehicleEntity = 300 })
  check("watch buy", #t == 1 and t[1].vehicle == 300 and t[1].line == nil)
  t = watch.extractTargets("makeVehicleBuyCmd", { n = 3 }, {})
  check("watch buy without result", #watch.extractTargets("makeVehicleBuyCmd", { n = 3 }, {}) == 0)

  t = watch.extractTargets("makeLineUpdateCmd", { [1] = 10, n = 2 }, {})
  check("watch lineUpdate", #t == 1 and t[1].lineVehiclesOf == 10)

  check("watch lineCreate is no-op", #watch.extractTargets("makeLineCreateCmd", { n = 4 }, {}) == 0)

  t = watch.extractTargets("makeEntitySetColorCmd", { [1] = 10, n = 2 }, {})
  check("watch setColor defers to executor", #t == 1 and t[1].maybeLine == 10)

  check("watch unknown kind", #watch.extractTargets("makeTownCreateCmd", { n = 1 }, {}) == 0)
  check("watch nil-safe", #watch.extractTargets(nil, nil, nil) == 0)

  check("watch WATCHED set", watch.WATCHED.makeVehicleSetLineCmd == true
    and watch.WATCHED.makeLineUpdateCmd == true
    and watch.WATCHED.makeEntitySetColorCmd == true
    and (watch.WATCHED.makeTownCreateCmd or false) == false)
end

-- sync.lua: line-wide + entity-classified recolor (engine side)
do
  local red, blue = C(1, 0, 0), C(0, 0, 1)
  local ctx = mock({
    lineColor = { [10] = red },
    tv = { [100] = { line = 10 }, [101] = { line = 10 } },
    vehColor = { [100] = blue, [101] = red },
    lineVehicles = { [10] = { 100, 101 } },
  })
  check("syncLine recolors line fleet", sync.syncLine(ctx, 10) == 1
    and #ctx.sent == 1 and ctx.sent[1].entity == 100)
  check("syncLine nil-safe", sync.syncLine(ctx, nil) == 0 and sync.syncLine({}, 10) == 0)

  -- syncEntity: LINE component -> whole line
  local ctx2 = mock({
    lineColor = { [10] = red },
    tv = { [100] = { line = 10 } },
    vehColor = { [100] = blue },
    lineVehicles = { [10] = { 100 } },
  })
  ctx2.api.engine.getComponent = function(entity, ct)
    if ct == CT.COLOR then
      if entity == 10 then return { color = red } end
      if entity == 100 then return { color = blue } end
      return nil
    end
    if ct == 99 then -- LINE probe: only entity 10 is a line
      if entity == 10 then return { stops = {} } end
      return nil
    end
    if ct == CT.TRANSPORT_VEHICLE then
      if entity == 100 then return { line = 10 } end
      return nil
    end
    return nil
  end
  local CTLINE = { COLOR = CT.COLOR, TRANSPORT_VEHICLE = CT.TRANSPORT_VEHICLE, LINE = 99 }
  ctx2.componentType = CTLINE
  check("syncEntity classifies line", sync.syncEntity(ctx2, 10) == 1)
  check("syncEntity classifies vehicle", sync.syncEntity(ctx2, 100) == 1)
  check("syncEntity ignores unknown", sync.syncEntity(ctx2, 999) == 0)
  check("syncEntity nil-safe", sync.syncEntity(ctx2, nil) == 0)
end

-- sync.lua: ComponentType member resolution (the camelCase bug).
-- `api.type.ComponentType.Color` is nil -> getComponent(entity, nil) fails
-- with "Error decoding argument #3" and every read silently returns 0.
do
  local ok, missing = sync.resolveComponentTypes({ Color = 1, TransportVehicle = 2 })
  check("resolveComponentTypes rejects camelCase keys", ok == nil and missing == "COLOR")

  local CTok = sync.resolveComponentTypes({
    COLOR = 10, TRANSPORT_VEHICLE = 11, LINE = 12, TOWN = 13,
  })
  check("resolveComponentTypes resolves UPPER_SNAKE keys",
    type(CTok) == "table" and CTok.COLOR == 10 and CTok.TRANSPORT_VEHICLE == 11 and CTok.LINE == 12)

  local userdataLike = setmetatable({}, { __index = function(_, k)
    return ({ COLOR = 10, TRANSPORT_VEHICLE = 11, LINE = 12 })[k]
  end })
  check("resolveComponentTypes works through an __index proxy",
    type(sync.resolveComponentTypes(userdataLike)) == "table")

  check("resolveComponentTypes nil-safe",
    sync.resolveComponentTypes(nil) == nil)
  check("componentKeys are the verified member names",
    table.concat(sync.componentKeys(), ",") == "COLOR,TRANSPORT_VEHICLE,LINE")
end

-- events.lua: the GUI <-> engine contract must not drift.
-- A game script only receives scripting events it has subscribed to, so the
-- hook's event name MUST be in the engine's subscription list. Both sides
-- read events.lua; this guards the invariant itself.
do
  local subscribed = {}
  for _, name in ipairs(events.SUBSCRIBE_EVENTS) do subscribed[name] = true end
  check("events: recolor is subscribed", subscribed[events.EVENT_RECOLOR] == true)
  check("events: arrival/cargo fallback subscribed",
    subscribed.OnArriveAtStop and subscribed.OnCargoLoaded and subscribed.OnCargoUnloaded)
  check("events: id and name are non-empty strings",
    type(events.EVENT_ID) == "string" and #events.EVENT_ID > 0
    and type(events.EVENT_RECOLOR) == "string" and #events.EVENT_RECOLOR > 0)
  check("events: subscribe list has no duplicates",
    (function()
      local seen, n = {}, 0
      for _, name in ipairs(events.SUBSCRIBE_EVENTS) do
        if seen[name] then return false end
        seen[name] = true
        n = n + 1
      end
      return n == #events.SUBSCRIBE_EVENTS
    end)())

  -- The engine script and the GUI hook must both take the constants from
  -- events.lua instead of hardcoding them again.
  local function reads(path, needles)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    for _, needle in ipairs(needles) do
      if not text:find(needle, 1, true) then return false, needle end
    end
    return true
  end
  check("engine script uses events.lua constants",
    reads("content/auto_vehicle_color/auto_vehicle_color.script.lua",
      { "events.SUBSCRIBE_EVENTS", "events.EVENT_ID", "events.EVENT_RECOLOR" }))
  check("gui hook uses events.lua constants",
    reads("content/auto_vehicle_color/gui/hook.script.lua",
      { "events.EVENT_ID", "events.EVENT_RECOLOR" }))
end

print(string.format("--- %d passed, %d failed ---", passed, failed))
os.exit(failed == 0 and 0 or 1)
