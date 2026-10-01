--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Adapted preset names/radii from core/src/com/unciv/logic/map/MapSize.kt
-- Upstream: yairm210/Unciv, revision 42939c6a2cf31aa76f44ffc033015ad12fece9f5
-- Hexagonal presets only; custom/auto sizes, rectangular dimensions and cost modifiers are omitted.
export type Preset = {read name: string, read radius: number, read tileCount: number}
local presets: {Preset} = {
    {name="Tiny",radius=10,tileCount=331},
    {name="Small",radius=15,tileCount=721},
    {name="Medium",radius=20,tileCount=1261},
    {name="Large",radius=30,tileCount=2791},
    {name="Huge",radius=40,tileCount=4921},
}
local byName: {[string]: Preset} = {}
for _, preset in presets do table.freeze(preset); byName[preset.name]=preset end
table.freeze(byName)
local MapSizes = {presets=table.freeze(presets)}
function MapSizes.get(name: string): Preset? return byName[name] end
return table.freeze(MapSizes)
