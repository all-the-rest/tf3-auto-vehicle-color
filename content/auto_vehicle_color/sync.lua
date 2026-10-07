-- Auto Vehicle Color: pure sync logic, no game required.
-- Works against a minimal interface so tests can inject mocks:
--   context.api.engine.system.lineSystem.getLines()
--   context.api.engine.system.transportVehicleSystem.getLineVehicles(line)
--   context.api.engine.getComponent(entity, componentType)
--   context.api.engine.getRevision(entity)            (optional, for cache)
--   context.api.cmd.makeEntitySetColorCmd(entity, color)
--   context.api.cmd.sendCommand(cmd)
--   context.componentType.Color / .TransportVehicle
--
-- Design: there is no documented engine event for "vehicle assigned to
-- line" or "line color changed", so a throttled sweep (syncAll) is the
-- fallback. Wherever an engine event carrying vehicleEntity + lineEntity
-- arrives (e.g. OnArriveAtStop), syncOne recolors that one vehicle
-- immediately -- the event fast path.
local M = {}

local EPS = 1e-4

local function sameColor(a, b)
  if not a or not b then return false end
  local function comp(c, k)
    if type(c) == "table" then return c[k] or c[({ x = 1, y = 2, z = 3 })[k]] or 0 end
    return 0
  end
  return math.abs(comp(a, "x") - comp(b, "x")) < EPS
    and math.abs(comp(a, "y") - comp(b, "y")) < EPS
    and math.abs(comp(a, "z") - comp(b, "z")) < EPS
end

-- A vehicle counts as "active" when it is not sitting in a depot.
-- TF3 TransportVehicle.depot holds the depot entity while parked
-- (nil / -1 when on the road). Decision: skip depot vehicles.
local function isActive(transportVehicle)
  if transportVehicle == nil then return false end
  local depot = transportVehicle.depot
  return depot == nil or depot == -1
end

local function readColor(api, CT, entity)
  local ok, comp = pcall(api.engine.getComponent, entity, CT.Color)
  if ok and comp and comp.color then return comp.color end
  return nil
end

local function sendColor(api, entity, color)
  local ok = pcall(function()
    api.cmd.sendCommand(api.cmd.makeEntitySetColorCmd(entity, color))
  end)
  return ok
end

--- Recolor one vehicle to its line color if needed.
-- @return 1 if a setColor command was sent, 0 otherwise
function M.syncOne(context, vehicleEntity, lineEntity)
  local api, CT = context.api, context.componentType
  if not api or not CT or not vehicleEntity or not lineEntity then return 0 end
  local lineColor = readColor(api, CT, lineEntity)
  if not lineColor then return 0 end
  local okTv, tv = pcall(api.engine.getComponent, vehicleEntity, CT.TransportVehicle)
  if not (okTv and tv and tv.line == lineEntity and isActive(tv)) then return 0 end
  local vehColor = readColor(api, CT, vehicleEntity)
  if vehColor and not sameColor(vehColor, lineColor) then
    if sendColor(api, vehicleEntity, lineColor) then return 1 end
  end
  return 0
end

local function revisionKey(api, entity)
  if not api.engine.getRevision then return nil end
  local ok, rev = pcall(api.engine.getRevision, entity)
  if ok and rev and rev.num then return table.concat(rev.num, ".") end
  return nil
end

--- Sync all vehicles of all lines to their line color.
-- @param cache optional table { lineColors = {}, revs = {} }, mutated in
--   place. Steady-state sweeps skip entities whose revision and line color
--   are unchanged, so cost drops to ~1 cheap call per vehicle.
-- @return number of setColor commands sent
function M.syncAll(context, cache)
  local sent = 0
  local api = context.api
  local CT = context.componentType
  if not api or not api.engine or not CT then return 0 end
  cache = cache or {}
  cache.lineColors = cache.lineColors or {}
  cache.revs = cache.revs or {}

  local okLines, lines = pcall(function()
    return api.engine.system.lineSystem.getLines()
  end)
  if not okLines or type(lines) ~= "table" then return 0 end

  for _, line in ipairs(lines) do
    local lineColor = readColor(api, CT, line)
    if lineColor then
      local lineChanged = not sameColor(cache.lineColors[line], lineColor)
      local okVeh, vehicles = pcall(function()
        return api.engine.system.transportVehicleSystem.getLineVehicles(line)
      end)
      if okVeh and type(vehicles) == "table" then
        for _, vehicle in ipairs(vehicles) do
          local rev = revisionKey(api, vehicle)
          if lineChanged or rev == nil or cache.revs[vehicle] ~= rev then
            sent = sent + M.syncOne(context, vehicle, line)
            if rev ~= nil then cache.revs[vehicle] = rev end
          end
        end
      end
      cache.lineColors[line] = { x = lineColor.x or lineColor[1], y = lineColor.y or lineColor[2], z = lineColor.z or lineColor[3] }
    end
  end
  return sent
end

--- Duck-type an engine event param into (vehicleEntity, lineEntity).
-- Returns nil, nil unless both fields are present. Lets handleEvent react
-- to any present or future event carrying them, without depending on the
-- exact src/name strings (unverified against the live game).
function M.extractVehicleLine(param)
  if type(param) ~= "table" then return nil, nil end
  local v = param.vehicleEntity or param.vehicle
  local l = param.lineEntity or param.line
  if v ~= nil and l ~= nil then return v, l end
  return nil, nil
end

M.sameColor = sameColor
M.isActive = isActive

return M
