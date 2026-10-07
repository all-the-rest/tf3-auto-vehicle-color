-- Auto Vehicle Color: GUI hook (runs inside Transport Fever 3 GUI state).
-- Installed ONCE via prepare() (react-replacement-config, replaces no
-- recipe): wraps api.cmd factories + sendCommand (technique proven by
-- TPF3MP's guard.lua) and notifies the engine script after watched
-- commands commit successfully. No ticks, no polling, commands are never
-- blocked or altered, only observed.
--
-- The GUI recipe state cannot read components (lazy enum proxies), so
-- the hook performs ZERO engine reads: it forwards { vehicle, line } /
-- { line } / { entity } via makeScriptingSendEventCmd, and the engine
-- game script (where reads work) does the recoloring.
--
-- Diagnostics: watch the ingame console (key below ESC) or stdout.txt.

function data()
  local MOD = "alltherest_auto_vehicle_color"

  -- DIAGNOSTIC: plain print too, so the line is unambiguous in stdout.txt.
  local function log(...)
    local parts = { "[AVC]" }
    for i = 1, select("#", ...) do
      parts[#parts + 1] = tostring((select(i, ...)))
    end
    local msg = table.concat(parts, " ")
    if print then pcall(print, msg) end
    if debugPrint then pcall(debugPrint, msg) end
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

  -- Forward targets to the engine script; it reads + recolors there.
  local function notify(targets)
    for _, t in ipairs(targets) do
      local param = nil
      if t.vehicle ~= nil and t.line ~= nil then
        param = { vehicle = t.vehicle, line = t.line }
      elseif t.vehicle ~= nil then
        param = { entity = t.vehicle }
      elseif t.lineVehiclesOf ~= nil then
        param = { line = t.lineVehiclesOf }
      elseif t.maybeLine ~= nil then
        param = { entity = t.maybeLine }
      end
      if param ~= nil then
        local ok, cmd = pcall(api.cmd.makeScriptingSendEventCmd, "", MOD, "recolor", param)
        if ok and cmd ~= nil then
          pcall(api.cmd.sendCommand, cmd)
          log("notified engine")
        else
          log("notify failed")
        end
      end
    end
  end

  local function install(cmd)
    local watch = loadModule("gui/watch.lua")
    if not watch then return false end
    local kinds = {} -- command object -> factory name
    local calls = {} -- command object -> factory args {n=...}

    -- Wrap factories to record kind + args per command object.
    local wrapped = 0
    for name, factory in pairs(cmd) do
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
      -- Pass through untouched: unknown, unwatched, or callback-less.
      -- Our notify events carry no callback and pass through as well,
      -- so they can never re-enter notify: loop-safe by construction.
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
            local okN, err = pcall(notify, targets)
            if not okN then
              log("notify error: ", tostring(err))
            end
          end
        else
          log("failed (ignored): ", kind)
        end
        return inner(result, success, ...)
      end
      return origSend(command, callback, ...)
    end

    log("hook installed (", wrapped, " factories wrapped)")
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
      -- DIAGNOSTIC: does a game script entity for our descriptor exist in
      -- THIS session? GameScript entities are created only for mods that
      -- are part of the running session's mod set.
      local SCRIPT_URI = MOD .. "::/auto_vehicle_color/auto_vehicle_color.gs"
      local okS, sys = pcall(function() return api.engine.system.gameScriptSystem end)
      log("probe: gameScriptSystem=", okS and type(sys) or ("ERR " .. tostring(sys)),
        " engineSystem=", api.engine and type(api.engine.system))
      local okE, ent = pcall(function()
        return api.engine.system.gameScriptSystem.getEntityForGameScript(SCRIPT_URI)
      end)
      log("probe: getEntityForGameScript(", SCRIPT_URI, ") ok=", okE,
        " entity=", okE and tostring(ent) or tostring(ent))
    end,
  }
end
