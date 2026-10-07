-- Auto Vehicle Color game script descriptor.
-- Any *.gs.lua under content/ is picked up by the game; it points at the
-- update implementation in auto_vehicle_color.script.lua.
function data()
  return {
    updateScript = {
      fileName = "auto_vehicle_color.script@update",
    },
    handleEventScript = {
      fileName = "auto_vehicle_color.script@handleEvent",
    },
  }
end
