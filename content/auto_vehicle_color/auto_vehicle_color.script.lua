-- Auto Vehicle Color: engine entry point (runs inside Transport Fever 3).
-- STRICTLY EVENT-DRIVEN (AGENTS.md Rule 0): update() only subscribes,
-- all logic runs in handleEvent. The pure logic lives in sync.lua so it
-- can be unit tested headless.
local events = ug_require("alltherest_auto_vehicle_color::/auto_vehicle_color/events.lua")

function data()
  local fallbackNotes = 0

  local function log(...)
    if debugPrint then
      pcall(debugPrint, "[AVC] ", ...)
    end
  end

  local function componentTypes(sync)
    local enum = api and api.type and api.type.ComponentType
    local CT, missing = sync.resolveComponentTypes(enum)
    if not CT then
      log("ComponentType member missing: ", tostring(missing))
      return nil
    end
    return CT
  end

  local function loadSync()
    local ok, mod = pcall(ug_require, "alltherest_auto_vehicle_color::/auto_vehicle_color/sync.lua")
    if ok and mod then return mod end
    log("sync.lua load failed: ", tostring(mod))
    return nil
  end

  return {
    -- Subscription only. No game logic, no sweep, no throttle, ever.
    -- (Base-game pattern, e.g. arrivaltracker.script.tl.)
    update = function(_params, state, _dt)
      local ok, subscribed = pcall(function() return state:hasEventSubscriptions() end)
      if ok and not subscribed then
        for _, name in ipairs(events.SUBSCRIBE_EVENTS) do
          pcall(function() state:subscribeToEvent(name) end)
        end
        log("engine script subscribed")
      end
    end,

    handleEvent = function(_params, _state, _src, id, name, param)
      local sync = loadSync()
      if not sync then return end
      local CT = componentTypes(sync)
      if not CT then return end
      local ctx = { api = api, componentType = CT }
      -- Our GUI hook's scripting event: { vehicle=, line= } or { line= }
      -- or { entity= }. Reads happen HERE (engine state), never in GUI.
      -- Received only because "recolor" is subscribed (events.lua).
      if id == events.EVENT_ID and name == events.EVENT_RECOLOR and type(param) == "table" then
        if param.vehicle ~= nil and param.line ~= nil then
          local okTv, tv = pcall(api.engine.getComponent, param.vehicle, CT.TRANSPORT_VEHICLE)
          log("decision: vehicle=", param.vehicle, " targetLine=", param.line,
            " tvLine=", okTv and tv and tv.line or "n/a",
            " depot=", okTv and tv and tostring(tv.depot) or "n/a",
            " tvErr=", (not okTv) and tostring(tv) or "-")
          local ok, n = pcall(sync.syncOne, ctx, param.vehicle, param.line)
          log("syncOne -> ", ok and n or ("ERR " .. tostring(n)))
          if ok and n == 1 then
            log("recolored vehicle ", param.vehicle, " to line ", param.line, " (hook)")
          end
        elseif param.line ~= nil then
          local ok, n = pcall(sync.syncLine, ctx, param.line)
          if ok and n > 0 then
            log("recolored ", n, " vehicles to line ", param.line, " (hook)")
          elseif not ok then
            log("syncLine error: ", tostring(n))
          end
        elseif param.entity ~= nil then
          local ok, n = pcall(sync.syncEntity, ctx, param.entity)
          if ok and n > 0 then
            log("recolored ", n, " via entity ", param.entity, " (hook)")
          elseif not ok then
            log("syncEntity error: ", tostring(n))
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
        elseif not ok then
          log("event ", name, ": syncOne error ", tostring(n))
        elseif fallbackNotes < 5 then
          -- DIAGNOSTIC: why the arrival fallback did nothing (depot gate,
          -- colors already equal, unreadable components).
          fallbackNotes = fallbackNotes + 1
          log("event ", name, ": nothing to do (vehicle=", vehicle, " line=", line, ")")
        end
      end
    end,
  }
end
