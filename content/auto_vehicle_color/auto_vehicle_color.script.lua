-- Auto Vehicle Color: engine entry point (runs inside Transport Fever 3).
-- The pure logic lives in sync.lua so it can be unit tested headless.
--
-- Event fast path: handleEvent recolors a single vehicle the moment an
-- engine event carrying vehicleEntity + lineEntity arrives (O(1)).
-- Fallback: update runs a full sweep, throttled to SWEEP_INTERVAL_SEC and
-- revision-cached, covering assignment + line color change (no documented
-- engine event exists for either).
local SWEEP_INTERVAL_SEC = 3.0
-- Best-effort subscription; exact event name strings are unverified
-- against the live game, everything is pcall-guarded and handleEvent
-- additionally duck-types the param table.
local SUBSCRIBE_EVENTS = { "OnArriveAtStop" }

function data()
  local function componentTypes()
    if api and api.type and api.type.ComponentType then
      return api.type.ComponentType
    end
    if api and api.engine and api.engine.ComponentType then
      return api.engine.ComponentType
    end
    if Engine and Engine.ComponentType then
      return Engine.ComponentType
    end
    return nil
  end

  local function loadSync()
    local ok, mod = pcall(ug_require, "alltherest_auto_vehicle_color::/auto_vehicle_color/sync.lua")
    if ok and mod then return mod end
    return nil
  end

  local function context()
    return { api = api, componentType = componentTypes() }
  end

  local function readState(state)
    local ok, s = pcall(function() return state:get() end)
    if ok and type(s) == "table" then return s end
    return {}
  end

  local function writeState(state, s)
    pcall(function() state:set(s) end)
  end

  return {
    update = function(_params, state, _dt)
      local sync = loadSync()
      if not sync then return end
      local s = readState(state)
      -- Best-effort event subscription, once per state.
      if not s.subscribed and state.subscribeToEvent then
        for _, name in ipairs(SUBSCRIBE_EVENTS) do
          pcall(function() state:subscribeToEvent(name) end)
        end
        s.subscribed = true
      end
      -- Throttled sweep. os.clock is available in game scripts and keeps
      -- working while the game is paused (line colors can change then).
      local now = (os and os.clock and os.clock()) or 0
      s.cache = s.cache or {}
      if s.lastSweep and (now - s.lastSweep) < SWEEP_INTERVAL_SEC then
        writeState(state, s)
        return
      end
      s.lastSweep = now
      local ctx = context()
      if ctx.componentType then
        pcall(sync.syncAll, ctx, s.cache)
      end
      writeState(state, s)
    end,

    handleEvent = function(_params, _state, _src, _id, _name, param)
      local sync = loadSync()
      if not sync then return end
      local vehicle, line = sync.extractVehicleLine(param)
      if vehicle and line then
        local ctx = context()
        if ctx.componentType then
          pcall(sync.syncOne, ctx, vehicle, line)
        end
      end
    end,
  }
end
