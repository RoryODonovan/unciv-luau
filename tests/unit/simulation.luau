--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original synthetic simulation tests; formula expectations derived from cited upstream source.
local Game = require("../../src/simulation/Game")
local Mechanics = require("../../src/simulation/Mechanics")
local replay = require("../winning-replay")
local function equal(a: any, b: any): boolean
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in a do if not equal(value, b[key]) then return false end end
    for key in b do if a[key] == nil then return false end end
    return true
end
assert(Mechanics.growthFood(1) == 15 and Mechanics.growthFood(2) == 24 and Mechanics.growthFood(3) == 33)
assert(Mechanics.damage(1, true, 0.5) == 30 and Mechanics.damage(1, false, 0.5) == 30)
assert(math.abs(Mechanics.damage(2, true, 0.5) * Mechanics.damage(2, false, 0.5) - 900) < 1e-8)
local state = Game.new(1)
assert(#state.tiles == 37 and #state.units == 3 and #state.cities == 1)
assert(equal(Game.snapshot(state, 1), Game.snapshot(Game.new(1), 1)))
assert(not equal(Game.snapshot(state, 1).tiles, Game.snapshot(Game.new(2), 1).tiles))
local before = Game.snapshot(state, 1)
local invalid: {any} = {{kind="MoveUnit",unitId=1,tileId=37}, {kind="MoveUnit",unitId=3,tileId=30}, {kind="FoundCity",unitId=2}, {kind="Research",technology="Writing"}, {kind="SetProduction",cityId=1,item="Warrior"}, {kind="Unknown"}, {kind="MoveUnit"}, {kind="Research"}}
for _, command in invalid do assert(not Game.apply(state, 1, command).ok); assert(equal(before, Game.snapshot(state, 1))) end
assert(not Game.apply(state, 2, {kind="EndTurn"}).ok)
local detached = Game.snapshot(state, 1)
detached.tiles[1].food = 999; detached.units[1].hp = 0; table.insert(detached.availableResearch[1].prerequisites, "fake")
assert(equal(before, Game.snapshot(state, 1)))
assert(Game.apply(state, 1, {kind="FoundCity",unitId=1}).ok)
assert(Game.apply(state, 1, {kind="Research",technology="Agriculture"}).ok)
assert(Game.apply(state, 1, {kind="SetProduction",cityId=2,item="Settler"}).ok)
for _ = 1, 7 do assert(Game.apply(state, 1, {kind="EndTurn"}).ok) end
local grown = Game.snapshot(state, 1)
assert(grown.cities[2].population >= 2 and grown.gold > 0 and grown.science > 0)
assert(table.find(grown.technologies, "Agriculture") ~= nil)
local settlerProduced = false
for _, entry in grown.log do if string.find(entry, "Haven 2 produced a Settler", 1, true) then settlerProduced = true end end
assert(settlerProduced)
-- Real legal winning replay. Never reads or mutates internal fields to issue commands.
local win, twin = Game.new(1), Game.new(1)
for index, command in replay do
    local result = Game.apply(win, 1, command :: Game.Command)
    assert(result.ok, "winning replay command " .. index .. ": " .. result.message)
    assert(Game.apply(twin, 1, command :: Game.Command).ok)
    assert(equal(Game.snapshot(win, 1), Game.snapshot(twin, 1)))
end
local won = Game.snapshot(win, 1)
assert(won.phase == "Finished" and won.winner == 1 and won.turn == 10)
assert(won.reason == "You captured the rival capital.")
assert(not Game.apply(win, 1, {kind="EndTurn"}).ok)
assert(equal(won, Game.snapshot(win, 1)))
-- Inaction loses through legal AI combat, always bounded.
local loss = Game.new(1)
for _ = 1, 40 do if Game.snapshot(loss, 1).phase == "Finished" then break end; assert(Game.apply(loss, 1, {kind="EndTurn"}).ok) end
assert(Game.snapshot(loss, 1).phase == "Finished" and Game.snapshot(loss, 1).winner == 2)
-- A far retreating settler survives to the round limit without a city.
local bounded = Game.new(1)
-- A controlled headless fixture isolates score-bound behavior from elimination.
-- Fixture setup is separate from the legal end-to-end winning replay above.
bounded.units = {bounded.units[1]}; bounded.units[1].tileId = 1; bounded.units[1].moves = 0
bounded.cities = {}; bounded.aiCapital = -1
for _ = 1, 40 do assert(Game.apply(bounded, 1, {kind="EndTurn"}).ok) end
assert(bounded.turn == 40 and bounded.phase == "Finished" and bounded.winner == 1)
assert(string.find(bounded.reason :: string, "Round limit reached", 1, true) ~= nil)
assert(not pcall(function() Game.new(0/0) end))
assert(not pcall(function() (Game.getRules().productionCosts :: any).Warrior = 1 end))
print("simulation: deterministic replay, legal victory/loss, economy, formula, validation and round-bound checks passed")


