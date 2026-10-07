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

local CT = { Color = 1, TransportVehicle = 2 }

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
        if ct == CT.Color then
          local c = (opts.lineColor or {})[entity] or (opts.vehColor or {})[entity]
          if c then return { color = c } end
          return nil
        end
        if ct == CT.TransportVehicle then
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

-- 3: depot vehicles are skipped (decision: active only)
do
  local ctx = mock({
    lineColor = { [10] = C(1, 0, 0) },
    tv = { [100] = { line = 10, depot = 55 } },
    vehColor = { [100] = C(0, 0, 1) },
  })
  check("syncOne skips depot vehicle", sync.syncOne(ctx, 100, 10) == 0 and #ctx.sent == 0)
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
  check("isActive", sync.isActive(nil) == false and sync.isActive({ depot = 3 }) == false
    and sync.isActive({ depot = -1 }) == true and sync.isActive({}) == true)
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
    if ct == CT.Color then
      if entity == 10 then return { color = red } end
      if entity == 100 then return { color = blue } end
      return nil
    end
    if ct == 99 then -- LINE probe: only entity 10 is a line
      if entity == 10 then return { stops = {} } end
      return nil
    end
    if ct == CT.TransportVehicle then
      if entity == 100 then return { line = 10 } end
      return nil
    end
    return nil
  end
  local CTLINE = { Color = CT.Color, TransportVehicle = CT.TransportVehicle, LINE = 99 }
  ctx2.componentType = CTLINE
  check("syncEntity classifies line", sync.syncEntity(ctx2, 10) == 1)
  check("syncEntity classifies vehicle", sync.syncEntity(ctx2, 100) == 1)
  check("syncEntity ignores unknown", sync.syncEntity(ctx2, 999) == 0)
  check("syncEntity nil-safe", sync.syncEntity(ctx2, nil) == 0)
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
