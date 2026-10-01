--!strict
-- Generated module-only Roblox form. Source: src/map/MapSizes.luau
-- Source SHA-256: 81a56f325100709fef5b9e3250b8425f2c2d26e1e629ca55745cf84285f40236
-- Reproduce with tools/roblox-export.mjs; preserve MPL notices below.
-- Covered source: https://github.com/RoryODonovan/unciv-luau
-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- Obtain a copy at https://mozilla.org/MPL/2.0/.
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
