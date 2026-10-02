--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Derived from Unciv core/src/com/unciv/models/stats/Stat.kt
-- Upstream revision: 42939c6a2cf31aa76f44ffc033015ad12fece9f5
-- Upstream file has no individual copyright notice.
local Stat = {}

export type Id = "Production" | "Food" | "Gold" | "Science" | "Culture" | "Happiness" | "Faith"

Stat.Production = "Production" :: Id
Stat.Food = "Food" :: Id
Stat.Gold = "Gold" :: Id
Stat.Science = "Science" :: Id
Stat.Culture = "Culture" :: Id
Stat.Happiness = "Happiness" :: Id
Stat.Faith = "Faith" :: Id

Stat.entries = table.freeze({
    Stat.Production, Stat.Food, Stat.Gold, Stat.Science,
    Stat.Culture, Stat.Happiness, Stat.Faith,
})

local byName: {[string]: Id} = {}
for _, stat in Stat.entries do byName[stat] = stat end
table.freeze(byName)

Stat.statsUsableToBuy = table.freeze({
    Gold = true, Food = true, Science = true, Culture = true, Faith = true,
})
Stat.statsWithCivWideField = table.freeze({
    Gold = true, Science = true, Culture = true, Faith = true, Happiness = true,
})

function Stat.safeValueOf(name: string): Id?
    return byName[name]
end

function Stat.isStat(name: string): boolean
    return byName[name] ~= nil
end

function Stat.names(): {Id}
    return table.clone(Stat.entries)
end

function Stat.isCityWide(stat: Id): boolean
    return not (Stat.statsWithCivWideField :: {[string]: boolean})[stat]
end

return table.freeze(Stat)
