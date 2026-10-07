-- Auto Vehicle Color: engine entry point (runs inside Transport Fever 3).
-- STRICTLY EVENT-DRIVEN (AGENTS.md Rule 0): update() only subscribes,
-- all logic runs in handleEvent. The pure logic lives in sync.lua so it
-- can be unit tested headless.
function data()
  local SUBSCRIBE_EVENTS = { "OnArriveAtStop", "OnCargoLoaded", "OnCargoUnloaded" }

  local function log(...)
    if debugPrint then
      pcall(debugPrint, "[AVC] ", ...)
    end
  end

  local function componentTypes()
    if api and api.type and api.type.ComponentType then
      return api.type.ComponentType
    end
    return nil
  end

  local function loadSync()
    local ok, mod = pcall(ug_require, "alltherest_auto_vehicle_color::/auto_vehicle_color/sync.lua")
    if ok and mod then return mod end
    return nil
  end

  return {
    -- Subscription only. No game logic, no sweep, no throttle, ever.
    -- (Base-game pattern, e.g. arrivaltracker.script.tl.)
    update = function(_params, state, _dt)
      local ok, subscribed = pcall(function() return state:hasEventSubscriptions() end)
      if ok and not subscribed then
        for _, name in ipairs(SUBSCRIBE_EVENTS) do
          pcall(function() state:subscribeToEvent(name) end)
        end
        log("engine script subscribed")
      end
    end,

    handleEvent = function(_params, _state, _src, id, name, param)
      local sync = loadSync()
      if not sync then return end
      local CT = componentTypes()
      if not CT then return end
      local ctx = { api = api, componentType = CT }
      -- Our GUI hook's scripting event: { vehicle=, line= } or { line= }
      -- or { entity= }. Reads happen HERE (engine state), never in GUI.
      if id == "alltherest_auto_vehicle_color" and type(param) == "table" then
        if param.vehicle ~= nil and param.line ~= nil then
          local ok, n = pcall(sync.syncOne, ctx, param.vehicle, param.line)
          if ok and n == 1 then
            log("recolored vehicle ", param.vehicle, " to line ", param.line, " (hook)")
          end
        elseif param.line ~= nil then
          local ok, n = pcall(sync.syncLine, ctx, param.line)
          if ok and n > 0 then
            log("recolored ", n, " vehicles to line ", param.line, " (hook)")
          end
        elseif param.entity ~= nil then
          local ok, n = pcall(sync.syncEntity, ctx, param.entity)
          if ok and n > 0 then
            log("recolored ", n, " via entity ", param.entity, " (hook)")
          end
        end
        return
      end
      if not sync.shouldHandleEvent(id, name) then
        -- Unknown event: still try duck-typing, harmless if it yields nil.
        local v, l = sync.extractVehicleLine(param)
        if not (v and l) then return end
      end
      local vehicle, line = sync.extractVehicleLine(param)
      if vehicle and line then
        local ok, n = pcall(sync.syncOne, ctx, vehicle, line)
        if ok and n == 1 then
          log("recolored vehicle ", vehicle, " to line ", line, " (event ", name, ")")
        end
      end
    end,
  }
end
