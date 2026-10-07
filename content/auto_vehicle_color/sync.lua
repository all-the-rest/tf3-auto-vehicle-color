-- Auto Vehicle Color: pure sync logic, no game required.
-- STRICTLY EVENT-DRIVEN (see AGENTS.md Rule 0): no sweeps, no timers,
-- no caches. Single-vehicle recolor, invoked from handleEvent.
--
-- Works against a minimal interface so tests can inject mocks:
--   context.api.engine.getComponent(entity, componentType)
--   context.api.cmd.makeEntitySetColorCmd(entity, color)
--   context.api.cmd.sendCommand(cmd)
--   context.componentType.COLOR / .TRANSPORT_VEHICLE / .LINE
--
-- ComponentType member names are UPPER_SNAKE (verified in
-- api/tealdef/api/engine.d.tl, `enum ComponentType`). A camelCase key
-- (`.Color`) yields nil, makes getComponent fail with "Error decoding
-- argument #3" and silently turns every read into a no-op — that was a
-- real bug, so the keys live in COMPONENT_KEYS and are resolved via
-- resolveComponentTypes() instead of being indexed ad hoc.
--
-- Every function that does nothing says WHY: a no-op returns
-- (0, reason). Silence is what made the previous bugs invisible.
local M = {}

local EPS = 1e-2 -- same tolerance class as vanilla UI color handling

local COMPONENT_KEYS = { "COLOR", "TRANSPORT_VEHICLE", "LINE" }

--- Resolve the ComponentType members this mod needs.
-- @param componentTypeEnum api.type.ComponentType (or a mock)
-- @return CT table, or nil plus the name of the first missing member
function M.resolveComponentTypes(componentTypeEnum)
  local kind = type(componentTypeEnum)
  if kind ~= "table" and kind ~= "userdata" then
    return nil, "api.type.ComponentType is a " .. kind
  end
  local CT = {}
  for i = 1, #COMPONENT_KEYS do
    local key = COMPONENT_KEYS[i]
    local value = componentTypeEnum[key]
    if value == nil then return nil, key end
    CT[key] = value
  end
  return CT
end

function M.componentKeys()
  return COMPONENT_KEYS
end

local function channel(c, k)
  if type(c) == "table" then return c[k] or c[({ x = 1, y = 2, z = 3 })[k]] or 0 end
  return 0
end

local function sameColor(a, b)
  if not a or not b then return false end
  return math.abs(channel(a, "x") - channel(b, "x")) < EPS
    and math.abs(channel(a, "y") - channel(b, "y")) < EPS
    and math.abs(channel(a, "z") - channel(b, "z")) < EPS
end

--- Whether a TransportVehicle is parked in a depot.
-- `depot` holds the depot entity while parked (nil / -1 on the road).
-- Decision (user, 2026-10-07): depot vehicles ARE recolored too — the
-- correct color has to be visible right after buy+assign, and the depot
-- list / vehicle window read the same color component. This helper is
-- kept for diagnostics only; it no longer gates the recolor.
function M.isInDepot(transportVehicle)
  if transportVehicle == nil then return false end
  local depot = transportVehicle.depot
  return depot ~= nil and depot ~= -1
end

--- Whether an engine event (by system id + event name) carries a
-- vehicle+line pair worth recoloring. Exact-match gate; unknown events
-- fall through to extractVehicleLine duck-typing in handleEvent.
function M.shouldHandleEvent(id, name)
  if id == "TransportVehicleSystem"
    and (name == "OnArriveAtStop" or name == "OnCargoLoaded" or name == "OnCargoUnloaded") then
    return true
  end
  return false
end

--- Duck-type an engine event param into (vehicleEntity, lineEntity).
-- Returns nil, nil unless both fields are present.
function M.extractVehicleLine(param)
  if type(param) ~= "table" then return nil, nil end
  local v = param.vehicleEntity or param.vehicle
  local l = param.lineEntity or param.line
  if v ~= nil and l ~= nil then return v, l end
  return nil, nil
end

--- Recolor one vehicle to its line color if needed.
-- @return 1, "recolored" if a setColor command was sent, else 0, reason
function M.syncOne(context, vehicleEntity, lineEntity)
  local api, CT = context.api, context.componentType
  if not api or not CT or not vehicleEntity or not lineEntity then
    return 0, "missing-arguments"
  end

  local okLine, lineComp = pcall(api.engine.getComponent, lineEntity, CT.COLOR)
  local lineColor = okLine and lineComp and lineComp.color or nil
  if not lineColor then
    return 0, okLine and "line-has-no-color" or "line-read-failed"
  end

  local okTv, tv = pcall(api.engine.getComponent, vehicleEntity, CT.TRANSPORT_VEHICLE)
  if not (okTv and tv) then return 0, "vehicle-read-failed" end
  if tv.line ~= lineEntity then return 0, "not-on-this-line" end
  -- No depot gate here on purpose: depot vehicles take the line color too.

  local okVeh, vehComp = pcall(api.engine.getComponent, vehicleEntity, CT.COLOR)
  if not okVeh then return 0, "vehicle-color-read-failed" end
  local vehColor = okVeh and vehComp and vehComp.color or nil
  if not vehColor then return 0, "vehicle-has-no-color" end
  if sameColor(vehColor, lineColor) then return 0, "already-line-color" end

  local okCmd = pcall(function()
    api.cmd.sendCommand(api.cmd.makeEntitySetColorCmd(vehicleEntity, lineColor))
  end)
  if not okCmd then return 0, "command-failed" end
  return 1, "recolored"
end

--- Compact "reason=count" summary, deterministic order.
function M.summarize(reasons)
  local parts = {}
  for reason, count in pairs(reasons) do
    parts[#parts + 1] = reason .. "=" .. count
  end
  table.sort(parts)
  return table.concat(parts, " ")
end

--- Recolor every vehicle of one line to the line color.
-- @return number of setColor commands sent, reason summary, vehicles seen
function M.syncLine(context, lineEntity)
  local api = context.api
  if not api or not lineEntity then return 0, "missing-arguments", 0 end
  local ok, vehicles = pcall(function()
    return api.engine.system.transportVehicleSystem.getLineVehicles(lineEntity)
  end)
  if not ok then return 0, "line-vehicles-read-failed", 0 end
  if type(vehicles) ~= "table" then return 0, "no-vehicles", 0 end
  local sent, total, reasons = 0, 0, {}
  for _, vehicle in ipairs(vehicles) do
    total = total + 1
    local n, reason = M.syncOne(context, vehicle, lineEntity)
    sent = sent + n
    reasons[reason] = (reasons[reason] or 0) + 1
  end
  if total == 0 then return 0, "no-vehicles", 0 end
  return sent, M.summarize(reasons), total
end

--- Classify any entity and recolor accordingly (engine side, where
-- component reads work). Lines -> whole line; vehicles -> single.
-- @return number of setColor commands sent, reason summary, vehicles seen
function M.syncEntity(context, entity)
  local api, CT = context.api, context.componentType
  if not api or not CT or not entity then return 0, "missing-arguments", 0 end
  local okLine, lineComp = pcall(api.engine.getComponent, entity, CT.LINE)
  if okLine and lineComp then
    return M.syncLine(context, entity)
  end
  local okTv, tv = pcall(api.engine.getComponent, entity, CT.TRANSPORT_VEHICLE)
  if okTv and tv and tv.line then
    local n, reason = M.syncOne(context, entity, tv.line)
    return n, reason, 1
  end
  return 0, "not-a-line-or-line-vehicle", 0
end

M.sameColor = sameColor

return M
