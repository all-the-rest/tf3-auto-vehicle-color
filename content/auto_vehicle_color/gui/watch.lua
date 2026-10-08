-- Auto Vehicle Color: GUI hook decision logic. Pure, no game required.
-- The hook (hook.script.lua) wraps api.cmd factories + sendCommand
-- (technique proven by TPF3MP's guard.lua) and reacts ONLY when a
-- watched command commits successfully. No ticks, no polling.
local M = {}

-- Factory names (api.cmd.make*Cmd) watched by the hook.
M.WATCHED = {
  makeVehicleSetLineCmd = true,
  makeVehicleReplaceCmd = true,
  makeVehicleBuyCmd = true,
  makeLineUpdateCmd = true,
  makeLineCreateCmd = true,
  makeEntitySetColorCmd = true,
}

-- Watched commands the game sends WITHOUT a result callback. The hook
-- therefore attaches its OWN success callback to them, otherwise they
-- would never be observed (verified in the shipped GUI sources, build
-- 40408):
--   makeVehicleReplaceCmd  gui/line_vehicle_mgmt/vehicle_react_util.tl:407
--     ("Replace vehicles" mode of the line manager, manager_window.tl:8549)
-- Deliberately NOT listed: makeEntitySetColorCmd from the single-vehicle
-- paint bucket (gui/entity_window/vehicle/vehicle_eow.script.tl:150). That
-- one stays pass-through so a manual paint is never fought synchronously
-- (AGENTS.md decision).
M.CALLBACKLESS = {
  makeVehicleReplaceCmd = true,
}

--- Extract recolor targets from a committed command.
-- @param kind factory name, e.g. "makeVehicleSetLineCmd"
-- @param args factory args as {n=..., [1]=..., ...} (may be nil)
-- @param result sendCommand callback result table (may be nil)
-- @return list of targets:
--   { vehicle = <entity>, line = <entity|nil> }  single vehicle
--   { lineVehiclesOf = <entity> }                all vehicles of a line
--   { maybeLine = <entity> }                     executor classifies via
--                                                components (LINE vs vehicle)
function M.extractTargets(kind, args, result)
  args = args or {}
  result = result or {}
  if kind == "makeVehicleSetLineCmd" then
    if args[1] ~= nil and args[2] ~= nil then
      return { { vehicle = args[1], line = args[2] } }
    end
    return {}
  end
  if kind == "makeVehicleReplaceCmd" then
    local v = result.vehicleEntity or args[1]
    if v ~= nil then return { { vehicle = v, line = nil } } end
    return {}
  end
  if kind == "makeVehicleBuyCmd" then
    local v = result.resultVehicleEntity
    if v ~= nil then return { { vehicle = v, line = nil } } end
    return {}
  end
  if kind == "makeLineUpdateCmd" then
    if args[1] ~= nil then return { { lineVehiclesOf = args[1] } } end
    return {}
  end
  if kind == "makeLineCreateCmd" then
    return {} -- a new line has no vehicles yet
  end
  if kind == "makeEntitySetColorCmd" then
    -- Manual recolor (vehicle window) or line recolor (line manager):
    -- executor classifies the entity. Never fought synchronously.
    if args[1] ~= nil then return { { maybeLine = args[1] } } end
    return {}
  end
  return {}
end

return M
