-- Auto Vehicle Color game script descriptor.
-- Any *.gs.lua under content/ is picked up by the game; it points at the
-- update implementation in auto_vehicle_color.script.lua.

-- DIAGNOSTIC (remove after the wiring question is settled): proves whether
-- the descriptor file is mounted/loaded at all. Plain print (not
-- debugPrint) because print is proven to reach stdout.txt from engine-side
-- mod scripts (cf. just_more_weather_1::/rct/service.script.lua).
print("[AVC] probe: gs.lua chunk loaded")

function data()
  print("[AVC] probe: gs data() called")
  return {
    updateScript = {
      fileName = "auto_vehicle_color.script@update",
    },
    handleEventScript = {
      fileName = "auto_vehicle_color.script@handleEvent",
    },
  }
end
