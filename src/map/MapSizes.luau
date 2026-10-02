--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Adapted preset names/radii from core/src/com/unciv/logic/map/MapSize.kt
-- Upstream: yairm210/Unciv, revision 42939c6a2cf31aa76f44ffc033015ad12fece9f5
-- Hex presets adapted; additional synthetic sphere frequencies are original (provenance/sphere-original.json).
-- Custom/auto sizes, rectangular dimensions and cost modifiers are omitted.
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
export type SpherePreset = {read name: string, read frequency: number, read tileCount: number}
local spherePresets: {SpherePreset} = {
    {name="Duel",frequency=2,tileCount=42},
    {name="Tiny",frequency=6,tileCount=362},
    {name="Small",frequency=8,tileCount=642},
    {name="Medium",frequency=12,tileCount=1442},
    {name="Large",frequency=16,tileCount=2562},
    {name="Huge",frequency=22,tileCount=4842},
}
local sphereByName: {[string]: SpherePreset}={}
for _,preset in spherePresets do table.freeze(preset); sphereByName[preset.name]=preset end
table.freeze(sphereByName)
MapSizes.spherePresets=table.freeze(spherePresets)
function MapSizes.getSphere(name: string): SpherePreset? return sphereByName[name] end
return table.freeze(MapSizes)
