-- Headless unit tests for Auto Vehicle Color. No game, no dependencies:
--   lua tests/run.lua
-- Mocks api.engine / api.cmd with plain tables.

local sync = dofile("content/auto_vehicle_color/sync.lua")

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

-- Builds a mock context. opts: lines, lineColor{}, tv{} (line, depot),
-- vehColor{}, rev{}; records every setColor command in ctx.sent.
local function mock(opts)
  opts = opts or {}
  local sent = {}
  local api = {
    engine = {
      system = {
        lineSystem = {
          getLines = function() return opts.lines or {} end,
        },
        transportVehicleSystem = {
          getLineVehicles = function(line)
            return (opts.vehicles and opts.vehicles[line]) or {}
          end,
        },
      },
      getComponent = function(entity, ct)
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
      getRevision = function(entity)
        local r = (opts.rev or {})[entity]
        if r then return { num = r } end
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
    vehicles = { [10] = { 100 } },
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

-- 6: syncAll recolors, then steady-state sweep sends nothing (cache hit)
do
  local ctx = mock({
    lines = { 10 },
    lineColor = { [10] = C(1, 0, 0) },
    vehicles = { [10] = { 100, 101 } },
    tv = { [100] = { line = 10 }, [101] = { line = 10 } },
    vehColor = { [100] = C(0, 0, 1), [101] = C(1, 0, 0) },
    rev = { [100] = { 1, 0, 0 }, [101] = { 1, 0, 0 } },
  })
  local cache = {}
  local n1 = sync.syncAll(ctx, cache)
  for i = #ctx.sent, 1, -1 do ctx.sent[i] = nil end
  -- simulate the game having applied the color + revision bump
  ctx.api.engine.getComponent = function(entity, ct)
    if ct == CT.Color then
      if entity == 10 then return { color = C(1, 0, 0) } end
      return { color = C(1, 0, 0) }
    end
    if ct == CT.TransportVehicle then return { line = 10 } end
    return nil
  end
  local n2 = sync.syncAll(ctx, cache)
  check("syncAll recolors then steady-state silent", n1 == 1 and n2 == 0 and #ctx.sent == 0)
end

-- 7: line color change is picked up on the next sweep
do
  local colors = { [10] = C(1, 0, 0) }
  local ctx = mock({
    lines = { 10 },
    vehicles = { [10] = { 100 } },
    tv = { [100] = { line = 10 } },
    rev = { [100] = { 1, 0, 0 } },
  })
  ctx.api.engine.getComponent = function(entity, ct)
    if ct == CT.Color then
      if entity == 10 then return { color = colors[10] } end
      return { color = C(1, 0, 0) } -- vehicle still old red
    end
    if ct == CT.TransportVehicle then return { line = 10 } end
    return nil
  end
  local cache = {}
  sync.syncAll(ctx, cache)
  colors[10] = C(0, 1, 0) -- user changed line color to green
  for i = #ctx.sent, 1, -1 do ctx.sent[i] = nil end
  local n = sync.syncAll(ctx, cache)
  check("syncAll follows line color change",
    n == 1 and ctx.sent[1].color.x == 0 and ctx.sent[1].color.y == 1)
end

-- 8: newly assigned vehicle (revision unseen) is caught even if line color cached
do
  local ctx = mock({
    lines = { 10 },
    lineColor = { [10] = C(1, 0, 0) },
    vehicles = { [10] = { 100, 200 } },
    tv = { [100] = { line = 10 }, [200] = { line = 10 } },
    vehColor = { [100] = C(1, 0, 0), [200] = C(0, 0, 1) },
    rev = { [100] = { 1, 0, 0 }, [200] = { 2, 0, 0 } },
  })
  local cache = { lineColors = { [10] = C(1, 0, 0) }, revs = { [100] = "1.0.0" } }
  local n = sync.syncAll(ctx, cache)
  check("syncAll catches newly assigned vehicle", n == 1 and ctx.sent[1].entity == 200)
end

-- 9: broken engine API degrades to 0, never throws
do
  local ctx = mock({})
  ctx.api.engine.system.lineSystem.getLines = function() error("boom") end
  local ok, n = pcall(sync.syncAll, ctx, {})
  check("syncAll survives engine errors", ok and n == 0)
end

-- 10: event param duck-typing
do
  local v, l = sync.extractVehicleLine({ vehicleEntity = 5, lineEntity = 6, stopIndex = 2 })
  local v2, l2 = sync.extractVehicleLine({ vehicle = 7, line = 8 })
  local v3, l3 = sync.extractVehicleLine({ stopIndex = 2 })
  local v4, l4 = sync.extractVehicleLine("nope")
  check("extractVehicleLine duck-types", v == 5 and l == 6 and v2 == 7 and l2 == 8
    and v3 == nil and v4 == nil)
end

-- 11: helpers
do
  check("isActive", sync.isActive(nil) == false and sync.isActive({ depot = 3 }) == false
    and sync.isActive({ depot = -1 }) == true and sync.isActive({}) == true)
  check("sameColor epsilon", sync.sameColor(C(1, 0, 0), C(1 + 1e-5, 0, 0)) == true
    and sync.sameColor(C(1, 0, 0), C(0, 0, 1)) == false
    and sync.sameColor(nil, C(0, 0, 0)) == false)
end

print(string.format("--- %d passed, %d failed ---", passed, failed))
os.exit(failed == 0 and 0 or 1)
