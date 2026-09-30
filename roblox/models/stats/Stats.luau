-- Generated module-only Roblox form. Source: src/models/stats/Stats.luau
-- Source SHA-256: ea9b52ab13111266781ea37f08e9d0f417a6afebab1b4b3625a8b5d98832694f
-- Reproduce with tools/roblox-export.mjs; preserve MPL notices below.
--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Derived from Unciv core/src/com/unciv/models/stats/Stats.kt
-- Upstream revision: 42939c6a2cf31aa76f44ffc033015ad12fece9f5
-- Upstream file has no individual copyright notice.
local Stat = require(script.Parent.Stat)

local Stats = {}
export type Value = {
    production: number, food: number, gold: number, science: number,
    culture: number, happiness: number, faith: number,
}
export type StatValuePair = {key: Stat.Id, value: number}

function Stats.new(production: number?, food: number?, gold: number?, science: number?,
    culture: number?, happiness: number?, faith: number?): Value
    return {
        production = production or 0, food = food or 0, gold = gold or 0,
        science = science or 0, culture = culture or 0,
        happiness = happiness or 0, faith = faith or 0,
    }
end

function Stats.get(self: Value, stat: Stat.Id): number
    if stat == "Production" then return self.production end
    if stat == "Food" then return self.food end
    if stat == "Gold" then return self.gold end
    if stat == "Science" then return self.science end
    if stat == "Culture" then return self.culture end
    if stat == "Happiness" then return self.happiness end
    if stat == "Faith" then return self.faith end
    error("Unknown stat: " .. tostring(stat))
end

function Stats.set(self: Value, stat: Stat.Id, value: number)
    if stat == "Production" then self.production = value
    elseif stat == "Food" then self.food = value
    elseif stat == "Gold" then self.gold = value
    elseif stat == "Science" then self.science = value
    elseif stat == "Culture" then self.culture = value
    elseif stat == "Happiness" then self.happiness = value
    elseif stat == "Faith" then self.faith = value
    else error("Unknown stat: " .. tostring(stat)) end
end

function Stats.equals(self: Value, other: Value): boolean
    for _, stat in Stat.entries do
        if Stats.get(self, stat) ~= Stats.get(other, stat) then return false end
    end
    return true
end

function Stats.clone(self: Value): Value
    return Stats.new(self.production, self.food, self.gold, self.science,
        self.culture, self.happiness, self.faith)
end

function Stats.isEmpty(self: Value): boolean
    for _, stat in Stat.entries do
        if Stats.get(self, stat) ~= 0 then return false end
    end
    return true
end

function Stats.clear(self: Value)
    for _, stat in Stat.entries do Stats.set(self, stat, 0) end
end

function Stats.add(self: Value, other: Value): Value
    for _, stat in Stat.entries do
        Stats.set(self, stat, Stats.get(self, stat) + Stats.get(other, stat))
    end
    return self
end

function Stats.addStat(self: Value, stat: Stat.Id, value: number): Value
    Stats.set(self, stat, Stats.get(self, stat) + value)
    return self
end

function Stats.plus(self: Value, other: Value): Value
    return Stats.add(Stats.clone(self), other)
end

function Stats.times(self: Value, multiplier: number): Value
    local result = Stats.new()
    for _, stat in Stat.entries do
        Stats.set(result, stat, Stats.get(self, stat) * multiplier)
    end
    return result
end

function Stats.minus(self: Value, other: Value): Value
    return Stats.plus(self, Stats.times(other, -1))
end

function Stats.timesInPlace(self: Value, multiplier: number)
    for _, stat in Stat.entries do
        Stats.set(self, stat, Stats.get(self, stat) * multiplier)
    end
end

function Stats.div(self: Value, divisor: number): Value
    return Stats.times(self, 1 / divisor)
end

function Stats.applyRankingWeights(self: Value)
    self.food *= 14
    self.production *= 12.01
    self.gold *= 6
    self.science *= 9.01
    self.culture *= 8
    self.happiness *= 10
    self.faith *= 7
end

-- Snapshot in upstream iteration order, excluding zero values.
function Stats.entries(self: Value): {StatValuePair}
    local entries = {}
    for _, stat in Stat.entries do
        local value = Stats.get(self, stat)
        if value ~= 0 then table.insert(entries, {key = stat, value = value}) end
    end
    return entries
end

function Stats.sum(self: Value): number
    return self.production + self.food + self.gold + self.science
        + self.culture + self.happiness + self.faith
end

function Stats.min(self: Value): number
    local result = self.production
    for index = 2, #Stat.entries do
        local value = Stats.get(self, Stat.entries[index])
        if result > value then result = value end
    end
    return result
end

function Stats.max(self: Value): number
    local result = self.production
    for index = 2, #Stat.entries do
        local value = Stats.get(self, Stat.entries[index])
        if result < value then result = value end
    end
    return result
end

local function parsePart(part: string): (Stat.Id?, number?)
    local sign, digits, name = string.match(part, "^([+-])([0-9]+) ([A-Za-z]+)$")
    if sign == nil or digits == nil or name == nil then return nil, nil end
    local stat = Stat.safeValueOf(name)
    if stat == nil then return nil, nil end
    local amount = tonumber(digits)
    if amount == nil then return nil, nil end
    return stat, if sign == "-" then -amount else amount
end

function Stats.isStats(text: string): boolean
    for _, part in string.split(text, ", ") do
        local stat = parsePart(part)
        if stat == nil then return false end
    end
    return true
end

function Stats.parse(text: string): Value
    local result = Stats.new()
    for _, part in string.split(text, ", ") do
        local stat, amount = parsePart(part)
        assert(stat ~= nil and amount ~= nil, "Invalid stats string: " .. text)
        Stats.addStat(result, stat, amount)
    end
    return result
end

-- Unlike the upstream mutable shared constants, exported defaults are frozen.
Stats.ZERO = table.freeze(Stats.new()) :: Value
Stats.DefaultCityCenterMinimum = table.freeze(Stats.new(1, 2)) :: Value
return table.freeze(Stats)
