--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Tests for conversions of Unciv models/stats at
-- revision 42939c6a2cf31aa76f44ffc033015ad12fece9f5.
local Stat = require("../../src/models/stats/Stat")
local Stats = require("../../src/models/stats/Stats")

local function near(actual: number, expected: number)
    assert(math.abs(actual - expected) < 1e-10,
        tostring(actual) .. " differs from " .. tostring(expected))
end

assert(#Stat.names() == 7)
assert(Stat.safeValueOf("Gold") == Stat.Gold)
assert(Stat.safeValueOf("gold") == nil)
assert(not Stat.isStat("Mana"))
assert(Stat.isCityWide(Stat.Food) and Stat.isCityWide(Stat.Production))
assert(not Stat.isCityWide(Stat.Happiness))
assert(Stat.statsUsableToBuy.Gold and Stat.statsUsableToBuy.Food)
local names = Stat.names()
table.remove(names)
assert(#Stat.names() == 7)

local original = Stats.new(1, 2, 3, 4, 5, 6, 7)
local copy = Stats.clone(original)
assert(copy ~= original and Stats.equals(original, copy))
Stats.set(copy, Stat.Gold, -2)
assert(original.gold == 3 and copy.gold == -2)
assert(Stats.get(copy, Stat.Gold) == -2)
assert(Stats.sum(original) == 28)
assert(Stats.min(original) == 1 and Stats.max(original) == 7)
assert(Stats.min(Stats.new(2)) == 0)
assert(Stats.max(Stats.new(-2)) == 0)
assert(Stats.sum(Stats.new(1, -1)) == 0)
assert(not Stats.isEmpty(Stats.new(1, -1)))

local bonus = Stats.new(2, -1, 0, 3)
local sum = Stats.plus(original, bonus)
assert(sum.production == 3 and sum.food == 1 and sum.science == 7)
assert(original.production == 1 and bonus.production == 2)
assert(Stats.equals(Stats.minus(sum, bonus), original))
assert(Stats.add(copy, bonus) == copy)
assert(copy.production == 3 and bonus.production == 2)
assert(Stats.addStat(copy, Stat.Faith, -7) == copy and copy.faith == 0)
local double = Stats.times(original, 2)
assert(double.production == 2 and double.faith == 14 and original.faith == 7)
assert(Stats.equals(Stats.div(double, 2), original))
Stats.timesInPlace(double, 0.5)
assert(Stats.equals(double, original))
Stats.clear(double)
assert(Stats.isEmpty(double) and not Stats.isEmpty(original))

local entries = Stats.entries(Stats.new(0, -1, 2, 0, 3))
assert(#entries == 3)
assert(entries[1].key == Stat.Food and entries[1].value == -1)
assert(entries[2].key == Stat.Gold and entries[3].key == Stat.Culture)
entries[1].value = 100
assert(Stats.entries(original)[1].value == 1)

local ranking = Stats.new(1, 1, 1, 1, 1, 1, 1)
Stats.applyRankingWeights(ranking)
near(ranking.production, 12.01)
near(ranking.food, 14)
near(ranking.gold, 6)
near(ranking.science, 9.01)
near(ranking.culture, 8)
near(ranking.happiness, 10)
near(ranking.faith, 7)

for _, valid in {"+1 Gold", "-12 Food, +3 Production", "+01 Faith", "+0 Science", "+1 Gold, -1 Gold"} do
    assert(Stats.isStats(valid), valid)
end
for _, invalid in {"", "1 Gold", "+1 gold", "+1 Mana", "+1.5 Food", "+1 Gold,+2 Food",
    "+1 Gold, ", " +1 Gold", "+1 Gold ", "+1 Gold\n", "+ 1 Gold"} do
    assert(not Stats.isStats(invalid), invalid)
    assert(not pcall(Stats.parse, invalid), invalid)
end
local parsed = Stats.parse("+10 Gold, -2 Food, -3 Gold")
assert(parsed.gold == 7 and parsed.food == -2 and parsed.production == 0)
assert(Stats.parse("+1 Gold, -1 Gold").gold == 0)
assert(Stats.DefaultCityCenterMinimum.production == 1)
assert(Stats.DefaultCityCenterMinimum.food == 2)
assert(not pcall(Stats.set, Stats.ZERO, Stat.Gold, 1))
local defaultCopy = Stats.clone(Stats.DefaultCityCenterMinimum)
Stats.clear(defaultCopy)
assert(Stats.DefaultCityCenterMinimum.food == 2)

-- Explicit numeric difference: arithmetic retains double precision.
local precise = Stats.new(16777216)
Stats.addStat(precise, Stat.Production, 1)
assert(precise.production == 16777217)
print("stats: passed")
