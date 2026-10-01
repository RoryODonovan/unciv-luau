--!strict
-- Generated module-only Roblox form. Source: src/simulation/Mechanics.luau
-- Source SHA-256: cc921980ed357288e38778237f2f86616389ce8af02de35309a96362710a2671
-- Reproduce with tools/roblox-export.mjs; preserve MPL notices below.
-- Covered source: https://github.com/RoryODonovan/unciv-luau
-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- Obtain a copy at https://mozilla.org/MPL/2.0/.
--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Derived from Unciv by Yair Morgenstern and contributors.
-- Upstream: core/src/com/unciv/logic/battle/BattleDamage.kt (damageModifier)
-- Upstream: core/src/com/unciv/logic/city/managers/CityPopulationManager.kt (getFoodToNextPopulation)
-- Revision: 42939c6a2cf31aa76f44ffc033015ad12fece9f5
-- Partial pure formulas only; no combat modifiers, difficulty, or game speed.
local Mechanics = {}
function Mechanics.growthFood(population: number): number
    assert(population >= 1 and population % 1 == 0, "positive integer population required")
    return 15 + 8 * (population - 1) + math.floor((population - 1) ^ 1.5)
end
function Mechanics.damage(ratio: number, damageToAttacker: boolean, randomness: number): number
    assert(ratio > 0 and ratio < math.huge, "positive finite strength ratio required")
    assert(randomness >= 0 and randomness <= 1, "randomness must be in [0,1]")
    local stronger = ratio ^ (if ratio < 1 then -1 else 1)
    local modifier = (((stronger + 3) / 4) ^ 4 + 1) / 2
    if (damageToAttacker and ratio > 1) or (not damageToAttacker and ratio < 1) then modifier = modifier ^ -1 end
    return (24 + 12 * randomness) * modifier
end
return table.freeze(Mechanics)
