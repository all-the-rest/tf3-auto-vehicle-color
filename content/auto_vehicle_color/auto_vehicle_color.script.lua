-- Auto Vehicle Color: engine entry point (runs inside Transport Fever 3).
-- STRICTLY EVENT-DRIVEN (AGENTS.md Rule 0): update() only subscribes,
-- all logic runs in handleEvent. The pure logic lives in sync.lua so it
-- can be unit tested headless.
--
-- WHERE COMMANDS MAY BE SENT (verified in-game, build 40408):
-- Sending a command while an ENGINE event is being dispatched is illegal:
-- api.cmd.sendCommand raises
--   Engine.cpp:545 BeginModification: Assertion '!m_betweenChanges' failed
-- -> a fatal error per call, each one writing a stack trace to the log.
-- With 1277 vehicles arriving constantly this alone made the game stutter.
-- Vanilla only ever sends commands from update() or from SCRIPTING events
-- (game_mechanics/finance/loan.script.tl sends inside handleEvent only for
-- id == "Loan"; celebrations.script.tl likewise). Our GUI hook's "recolor"
-- event IS a scripting event, so that branch may send.
-- Therefore: recoloring happens in the scripting-event branch; engine
-- events (OnArriveAtStop/OnCargoLoaded/OnCargoUnloaded) are observed only.
-- The arrival fallback needs a legal carrier first (see AGENTS.md todo).
local events = ug_require("alltherest_auto_vehicle_color::/auto_vehicle_color/events.lua")

function data()
  local observedEvents = 0

  local function log(...)
    if debugPrint then
      pcall(debugPrint, "[AVC] ", ...)
    end
  end

  -- sync.lua is required once per simulation VM and then cached: handleEvent
  -- runs for every cargo/arrival event, so the require must not be repeated.
  local syncModule = nil
  local function sync()
    if syncModule == nil then
      local ok, mod = pcall(ug_require, "alltherest_auto_vehicle_color::/auto_vehicle_color/sync.lua")
      if ok and mod then
        syncModule = mod
      else
        syncModule = false
        log("sync.lua load failed: ", tostring(mod))
      end
    end
    return syncModule or nil
  end

  local componentTypesCache = nil
  local function componentTypes(s)
    if componentTypesCache then return componentTypesCache end
    local CT, missing = s.resolveComponentTypes(api and api.type and api.type.ComponentType)
    if not CT then
      log("ComponentType member missing: ", tostring(missing))
      return nil
    end
    componentTypesCache = CT
    return CT
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
      -- Scripting event from our GUI hook: { vehicle=, line= } or { line= }
      -- or { entity= }. Reads AND the setColor command happen here; a
      -- scripting event is dispatched between engine changes, so commands
      -- are allowed (proven: recoloring works from this branch).
      -- Received only because "recolor" is subscribed (events.lua).
      if id == events.EVENT_ID and name == events.EVENT_RECOLOR and type(param) == "table" then
        local s = sync()
        if not s then return end
        local CT = componentTypes(s)
        if not CT then return end
        local ctx = { api = api, componentType = CT }
        if param.vehicle ~= nil and param.line ~= nil then
          local ok, n, reason = pcall(s.syncOne, ctx, param.vehicle, param.line)
          if not ok then
            log("syncOne error: ", tostring(n))
          elseif n == 1 then
            log("recolored vehicle ", param.vehicle, " to line ", param.line, " (", reason, ")")
          else
            log("syncOne -> 0 (", reason, ") for vehicle ", param.vehicle)
          end
        elseif param.line ~= nil then
          local ok, n, summary, total = pcall(s.syncLine, ctx, param.line)
          if not ok then
            log("syncLine error: ", tostring(n))
          elseif n > 0 then
            log("recolored ", n, "/", total, " vehicles of line ", param.line, " (", summary, ")")
          else
            log("syncLine -> 0/", total, " (", summary, ")")
          end
        elseif param.entity ~= nil then
          local ok, n, summary, total = pcall(s.syncEntity, ctx, param.entity)
          if not ok then
            log("syncEntity error: ", tostring(n))
          elseif n > 0 then
            log("recolored ", n, "/", total, " via entity ", param.entity, " (", summary, ")")
          else
            log("syncEntity -> 0/", total, " (", summary, ")")
          end
        end
        return
      end

      -- Engine events: observed, never acted on (see header). Capped log so
      -- a missing recolor stays diagnosable without flooding the log.
      if observedEvents < 5 then
        local s = sync()
        if s and s.shouldHandleEvent(id, name) then
          observedEvents = observedEvents + 1
          log("engine event ", name, ": observed, not acted on (no commands during engine events)")
        end
      end
    end,
  }
end
