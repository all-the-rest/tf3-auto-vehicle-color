-- Auto Vehicle Color: GUI hook (runs inside Transport Fever 3 GUI state).
-- Installed ONCE via prepare() (react-replacement-config, replaces no
-- recipe): wraps api.cmd factories + sendCommand (technique proven by
-- TPF3MP's guard.lua) and issues setColor follow-ups ONLY after watched
-- commands commit successfully. No ticks, no polling, commands are never
-- blocked or altered, only observed.
--
-- Diagnostics: watch the ingame console (key below ESC) or stdout.txt.

function data()
  local MOD = "alltherest_auto_vehicle_color"

  local function log(...)
    if debugPrint then
      pcall(debugPrint, "[AVC] ", ...)
    end
  end

  local function loadModule(path)
    local ok, mod = pcall(ug_require, MOD .. "::/auto_vehicle_color/" .. path)
    if ok and mod then return mod end
    log("load failed: " .. path)
    return nil
  end

  local function packArgs(...)
    return { n = select("#", ...), ... }
  end

  local function context()
    if api and api.type and api.type.ComponentType then
      return { api = api, componentType = api.type.ComponentType }
    end
    return nil
  end

  local function executeTargets(targets)
    local sync = loadModule("sync.lua")
    local ctx = context()
    if not sync or not ctx then
      log("executeTargets: missing sync or component types")
      return 0
    end
    local recolored = 0
    local function recolor(vehicle, line)
      local ok, n = pcall(sync.syncOne, ctx, vehicle, line)
      if ok and n == 1 then
        recolored = recolored + 1
        log("recolored vehicle ", vehicle, " to line ", line)
      end
    end
    local lineVehiclesOf = {}
    for _, t in ipairs(targets) do
      if t.vehicle ~= nil then
        local line = t.line
        if line == nil then
          local ok, tv = pcall(api.engine.getComponent, t.vehicle, ctx.componentType.TransportVehicle)
          if ok and tv then line = tv.line end
        end
        if line ~= nil then
          recolor(t.vehicle, line)
        else
          log("no line for vehicle ", t.vehicle, " (depot/unassigned?)")
        end
      elseif t.lineVehiclesOf ~= nil then
        lineVehiclesOf[#lineVehiclesOf + 1] = t.lineVehiclesOf
      elseif t.maybeLine ~= nil then
        local ok, lineComp = pcall(api.engine.getComponent, t.maybeLine, ctx.componentType.LINE)
        if ok and lineComp then
          lineVehiclesOf[#lineVehiclesOf + 1] = t.maybeLine
        else
          local okTv, tv = pcall(api.engine.getComponent, t.maybeLine, ctx.componentType.TransportVehicle)
          if okTv and tv and tv.line then
            recolor(t.maybeLine, tv.line)
          end
        end
      end
    end
    for _, line in ipairs(lineVehiclesOf) do
      local ok, vehicles = pcall(function()
        return api.engine.system.transportVehicleSystem.getLineVehicles(line)
      end)
      if ok and type(vehicles) == "table" then
        for _, vehicle in ipairs(vehicles) do
          recolor(vehicle, line)
        end
      end
    end
    return recolored
  end

  local function install(cmd)
    local watch = loadModule("gui/watch.lua")
    if not watch then return false end
    local kinds = {} -- command object -> factory name
    local calls = {} -- command object -> factory args {n=...}

    -- Wrap factories to record kind + args per command object.
    local wrapped, total, samples = 0, 0, {}
    for name, factory in pairs(cmd) do
      total = total + 1
      if #samples < 12 then
        samples[#samples + 1] = tostring(name) .. ":" .. type(factory)
      end
      if type(name) == "string" and name:match("^make.+Cmd$") then
        local orig = factory
        cmd[name] = function(...)
          local made = orig(...)
          if made ~= nil and (type(made) == "table" or type(made) == "userdata") then
            kinds[made] = name
            if watch.WATCHED[name] then calls[made] = packArgs(...) end
          end
          return made
        end
        wrapped = wrapped + 1
      end
    end

    local origSend = cmd.sendCommand
    cmd.sendCommand = function(command, callback, ...)
      local kind = kinds[command]
      -- Pass through untouched: unknown, unwatched, or callback-less
      -- (incl. our own follow-ups, which never carry a callback, so they
      -- can never re-enter executeTargets: loop-safe by construction).
      if kind == nil or not watch.WATCHED[kind] or type(callback) ~= "function" then
        return origSend(command, callback, ...)
      end
      local args = calls[command]
      local inner = callback
      callback = function(result, success, ...)
        if success then
          log("committed: ", kind)
          local okT, targets = pcall(watch.extractTargets, kind, args, result)
          if not okT then
            log("extractTargets error: ", tostring(targets))
          elseif #targets == 0 then
            log("no targets for ", kind)
          else
            local okE, err = pcall(executeTargets, targets)
            if not okE then
              log("executeTargets error: ", tostring(err))
            end
          end
        else
          log("failed (ignored): ", kind)
        end
        return inner(result, success, ...)
      end
      return origSend(command, callback, ...)
    end

    log("hook installed (", wrapped, " factories wrapped, ", total, " api.cmd entries)")
    if total > 0 then
      log("api.cmd sample: ", table.concat(samples, ", "))
    end
    return true
  end

  return {
    prepare = function(_replacementApi)
      if not api or not api.cmd or api.cmd.sendCommand == nil then
        log("prepare: no api.cmd, hook NOT installed")
        return
      end
      local ok, done = pcall(install, api.cmd)
      if not (ok and done) then
        log("prepare: install failed")
      end
    end,
  }
end
