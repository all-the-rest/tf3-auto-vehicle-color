-- Auto Vehicle Color GUI hook descriptor.
-- react-replacement-config: the game runs prepare() once in the Lua state
-- that renders recipes (line manager, depot and vehicle windows live
-- there), replacing no recipe. Proven by TPF3MP's gui_state.res.lua.
function data()
  return {
    type = "react-replacement-config",
    data = {
      filePath = "alltherest_auto_vehicle_color::/auto_vehicle_color/gui/hook.script",
      doReplaceFn = "prepare",
    },
  }
end
