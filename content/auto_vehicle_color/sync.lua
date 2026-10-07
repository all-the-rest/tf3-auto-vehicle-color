-- Auto Vehicle Color: pure sync logic, no game required.
-- STRICTLY EVENT-DRIVEN (see AGENTS.md Rule 0): no sweeps, no timers,
-- no caches. Single-vehicle recolor, invoked from handleEvent.
--
-- Works against a minimal interface so tests can inject mocks:
--   context.api.engine.getComponent(entity, componentType)
--   context.api.cmd.makeEntitySetColorCmd(entity, color)
--   context.api.cmd.sendCommand(cmd)
--   context.componentType.Color / .TransportVehicle
local M = {}

local EPS = 1e-2 -- same tolerance class as vanilla UI color handling

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

-- A vehicle counts as "active" when it is not sitting in a depot.
-- TransportVehicle.depot holds the depot entity while parked
-- (nil / -1 when on the road). Decision: skip depot vehicles.
local function isActive(transportVehicle)
  if transportVehicle == nil then return false end
  local depot = transportVehicle.depot
  return depot == nil or depot == -1
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
-- @return 1 if a setColor command was sent, 0 otherwise
function M.syncOne(context, vehicleEntity, lineEntity)
  local api, CT = context.api, context.componentType
  if not api or not CT or not vehicleEntity or not lineEntity then return 0 end

  local okLine, lineComp = pcall(api.engine.getComponent, lineEntity, CT.Color)
  local lineColor = okLine and lineComp and lineComp.color or nil
  if not lineColor then return 0 end

  local okTv, tv = pcall(api.engine.getComponent, vehicleEntity, CT.TransportVehicle)
  if not (okTv and tv and tv.line == lineEntity and isActive(tv)) then return 0 end

  local okVeh, vehComp = pcall(api.engine.getComponent, vehicleEntity, CT.Color)
  local vehColor = okVeh and vehComp and vehComp.color or nil
  if vehColor and not sameColor(vehColor, lineColor) then
    local okCmd = pcall(function()
      api.cmd.sendCommand(api.cmd.makeEntitySetColorCmd(vehicleEntity, lineColor))
    end)
    if okCmd then return 1 end
  end
  return 0
end

M.sameColor = sameColor
M.isActive = isActive

--- Recolor every vehicle of one line to the line color.
-- @return number of setColor commands sent
function M.syncLine(context, lineEntity)
  local api = context.api
  if not api or not lineEntity then return 0 end
  local ok, vehicles = pcall(function()
    return api.engine.system.transportVehicleSystem.getLineVehicles(lineEntity)
  end)
  if not ok or type(vehicles) ~= "table" then return 0 end
  local sent = 0
  for _, vehicle in ipairs(vehicles) do
    sent = sent + M.syncOne(context, vehicle, lineEntity)
  end
  return sent
end

--- Classify any entity and recolor accordingly (engine side, where
-- component reads work). Lines -> whole line; vehicles -> single.
-- @return number of setColor commands sent
function M.syncEntity(context, entity)
  local api, CT = context.api, context.componentType
  if not api or not CT or not entity then return 0 end
  local okLine, lineComp = pcall(api.engine.getComponent, entity, CT.LINE)
  if okLine and lineComp then
    return M.syncLine(context, entity)
  end
  local okTv, tv = pcall(api.engine.getComponent, entity, CT.TransportVehicle)
  if okTv and tv and tv.line then
    return M.syncOne(context, entity, tv.line)
  end
  return 0
end

return M
