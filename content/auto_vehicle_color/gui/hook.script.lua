-- Auto Vehicle Color: GUI hook (runs inside Transport Fever 3 GUI state).
-- Installs ONCE per GUI lifetime: wraps api.cmd factories + sendCommand
-- (technique proven by TPF3MP's guard.lua) and issues setColor follow-ups
-- ONLY after watched commands commit successfully. No ticks, no polling,
-- commands are never blocked or altered, only observed.
--
-- Loaded via gui/hook.res.lua (react-plugin). The recipe installs the
-- wrapper on first run and renders nothing.

function data()
  local MOD = "alltherest_auto_vehicle_color"
  local installed = false
  local kinds = {} -- command object -> factory name
  local calls = {} -- command object -> factory args {n=...}
  -- Loop safety by construction: our follow-ups are always sent WITHOUT
  -- a callback, and callback-less commands pass through untouched (see
  -- below), so they can never re-enter executeTargets.

  local function loadModule(path)
    local ok, mod = pcall(ug_require, MOD .. "::/auto_vehicle_color/" .. path)
    if ok and mod then return mod end
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
    local watch = loadModule("gui/watch.lua")
    local sync = loadModule("sync.lua")
    local ctx = context()
    if not sync or not ctx then return end
    local lineVehiclesOf = {}
    for _, t in ipairs(targets) do
      if t.vehicle ~= nil then
        local line = t.line
        if line == nil then
          local ok, tv = pcall(api.engine.getComponent, t.vehicle, ctx.componentType.TransportVehicle)
          if ok and tv then line = tv.line end
        end
        if line ~= nil then
          pcall(sync.syncOne, ctx, t.vehicle, line)
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
            pcall(sync.syncOne, ctx, t.maybeLine, tv.line)
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
          pcall(sync.syncOne, ctx, vehicle, line)
        end
      end
    end
  end

  local function install()
    if installed or not api or not api.cmd then return false end
    if api.cmd.sendCommand == nil then return false end
    local watch = loadModule("gui/watch.lua")
    if not watch then return false end

    -- Wrap factories to record kind + args per command object.
    for name, factory in pairs(api.cmd) do
      if type(name) == "string" and name:match("^make.+Cmd$") and type(factory) == "function" then
        local orig = factory
        api.cmd[name] = function(...)
          local cmd = orig(...)
          if cmd ~= nil and (type(cmd) == "table" or type(cmd) == "userdata") then
            kinds[cmd] = name
            if watch.WATCHED[name] then calls[cmd] = packArgs(...) end
          end
          return cmd
        end
      end
    end

    local origSend = api.cmd.sendCommand
    api.cmd.sendCommand = function(command, callback, ...)
      local kind = kinds[command]
      -- Pass through untouched: unknown, unwatched, or callback-less
      -- (incl. our own follow-ups, which never carry a callback).
      if kind == nil or not watch.WATCHED[kind] or type(callback) ~= "function" then
        return origSend(command, callback, ...)
      end
      local args = calls[command]
      local inner = callback
      callback = function(result, success, ...)
        if success then
          local targets = watch.extractTargets(kind, args, result)
          if #targets > 0 then
            -- Follow-ups read CURRENT engine state and act only on
            -- mismatch (syncOne), so a failed premise self-corrects.
            pcall(executeTargets, targets)
          end
        end
        return inner(result, success, ...)
      end
      return origSend(command, callback, ...)
    end

    installed = true
    return true
  end

  return {
    -- Recipe body: install once, render nothing. One boolean check per
    -- frame afterwards; no game logic, no polling (Rule 0).
    installHook = function()
      pcall(install)
      return nil
    end,
  }
end
