-- Auto Vehicle Color GUI hook descriptor.
-- react-plugin resource: loads hook.script.lua into the GUI state once.
function data()
  return {
    type = "react-plugin ::GameBarInfoDisplayExtension",
    data = {
      filePath = "alltherest_auto_vehicle_color::/auto_vehicle_color/gui/hook.script@installHook",
      priority = 5,
    },
  }
end
