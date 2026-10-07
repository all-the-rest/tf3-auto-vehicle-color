-- GUI <-> engine contract, kept in ONE place.
--
-- A game script only receives the scripting events it has subscribed to:
-- makeScriptingSendEventCmd(src, id, name, param) delivers under `name`
-- (the 3rd argument), and handleEvent filters on `id` (the sender tag).
-- Base-game proof: game_mechanics/game_time/game_time.script.tl does
-- state:subscribeToEvent("SetMode") and then checks
-- `if id == "GameTime" and name == "SetMode"`.
--
-- Subscribing in the hook's own event name is what the previous version
-- was missing: the hook notified, the engine never heard it.

local M = {}

-- Sender tag (makeScriptingSendEventCmd argument 2).
M.EVENT_ID = "alltherest_auto_vehicle_color"

-- Our own event name (argument 3). MUST appear in SUBSCRIBE_EVENTS.
M.EVENT_RECOLOR = "recolor"

-- Engine events used as the fallback path (fire even without the GUI).
M.SUBSCRIBE_EVENTS = {
	"OnArriveAtStop",
	"OnCargoLoaded",
	"OnCargoUnloaded",
	M.EVENT_RECOLOR,
}

return M
