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

-- Builds a mock context. Records every setColor command in ctx.sent.
local function mock(opts)
  opts = opts or {}
  local sent = {}
  local api = {
    engine = {
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

print(string.format("--- %d passed, %d failed ---", passed, failed))
os.exit(failed == 0 and 0 or 1)
