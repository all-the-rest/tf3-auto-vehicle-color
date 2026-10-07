# Auto Vehicle Color (Transport Fever 3)

![Tram in line color](https://github.com/all-the-rest/tf3-auto-vehicle-color/blob/main/_metadata/0.png)

Vehicles automatically take the color of their line — no manual repainting.

## What it does

- **Buy or assign a vehicle** → it takes the line color immediately, depot vehicles included.
- **Change a line's color** → the whole fleet follows at once.
- **Load a save** → all vehicles of all lines are corrected once.

Manual vehicle colors are **overwritten**: the line color always wins. The mod is flagged `cosmetic`, so achievements stay earnable with only this mod active.

## Install

Subscribe in-game via the Mod Hub, or get it here: https://mod.io/g/transportfever3/m/auto-vehicle-color1

Then activate it for your save like any other mod. No configuration, no settings.

## Good to know

- Works for all vehicle types on all lines (bus, tram, truck, train, ship, plane).
- Changes made by other mods, or propagated in multiplayer, are picked up at the next session start.
- Mod ID: `alltherest_auto_vehicle_color`

## For developers

Strictly event-driven, zero polling: a GUI hook observes assignments, purchases and line-color changes and recolors immediately; a one-time pass corrects existing vehicles when a save is loaded. There is no arrival fallback — sending commands during engine events is illegal in TF3.

- Rules and verified API ground truth: [AGENTS.md](AGENTS.md)
- Decision protocol: [AGENTS.todo.md](AGENTS.todo.md)
- Headless unit tests, no game needed: `lua tests/run.lua` (60 cases, zero dependencies)
- Mod layout follows the official format (`mod.json`, `_metadata/modinfo.json`, `content/`, see the [modding manual](https://wiki.transportfever3.com/doku.php?id=modding:general:moddefinition))
