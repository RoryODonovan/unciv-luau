--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original release simulation regression tests. Controlled fixtures isolate economy/validation.
local Game = require("../../src/simulation/Game")
local replay = require("../winning-replay")
local HexMath = require("../../src/map/HexMath")
local function equal(a: any, b: any): boolean
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in a do if not equal(v, b[k]) then return false end end
    for k in b do if a[k] == nil then return false end end
    return true
end
local function rejected(state: Game.State, command: any)
    local before = Game.serialize(state)
    local ok, result = pcall(function() return Game.apply(state, 1, command) end)
    assert(ok and not result.ok, "invalid command must return rejection")
    assert(equal(before, Game.serialize(state)), "rejection must not mutate any state")
end
local legacy = Game.new(1)
for _, command in replay do
    assert(Game.apply(legacy, 1, command :: Game.Command).ok)
    local restored, err = Game.restore(Game.serialize(legacy))
    assert(restored and not err and equal(Game.serialize(legacy), Game.serialize(restored)))
end
assert(legacy.winner == 1 and legacy.turn == 10)
-- Save resumes preserve every subsequent deterministic action, event and outcome.
local first, second = Game.new(1), Game.new(1)
for index, command in replay do
    assert(Game.apply(first, 1, command :: Game.Command).ok)
    assert(Game.apply(second, 1, command :: Game.Command).ok)
    if index % 3 == 0 then local restored = Game.restore(Game.serialize(second)); assert(restored); second = restored end
    assert(equal(Game.snapshot(first, 1), Game.snapshot(second, 1)))
end
for _, difficulty in {"Easy", "Normal", "Hard"} do
    for seed = 1, 6 do
        local state = Game.new(seed, {difficulty = difficulty, radius = 3 + seed % 3, forest = seed % 2 == 0})
        assert(#state.tiles == 1 + 3 * state.radius * (state.radius + 1))
        assert(Game.apply(state, 1, {kind="FoundCity", unitId=1}).ok)
        for _ = 1, 40 do
            if state.phase == "Finished" then break end
            assert(Game.apply(state, 1, {kind="EndTurn"}).ok)
            local restored = Game.restore(Game.serialize(state)); assert(restored and equal(Game.snapshot(state, 1), Game.snapshot(restored, 1)))
        end
        assert(state.phase == "Finished" and state.turn <= 40)
        assert(#state.events <= 32 and #state.log <= 16)
    end
end
-- Difficulty has explicit economy and movement pressure, not just a label.
local easy, normal, hard = Game.new(1), Game.new(1, {difficulty="Normal"}), Game.new(1, {difficulty="Hard"})
for _, state in {easy, normal, hard} do assert(Game.apply(state, 1, {kind="FoundCity", unitId=1}).ok); assert(Game.apply(state, 1, {kind="EndTurn"}).ok) end
assert(easy.cities[1].production < normal.cities[1].production)
assert(not equal(Game.snapshot(easy, 1).units, Game.snapshot(hard, 1).units))
-- Every advertised legal move is accepted by the same authoritative core.
for _, options in {{difficulty="Easy"}, {difficulty="Hard", forest=true}} do
    local state = Game.new(2, options :: Game.Options)
    for unitId, destinations in Game.snapshot(state, 1).legalMoves do
        for _, tileId in destinations do
            local clone = Game.restore(Game.serialize(state)); assert(clone)
            assert(Game.apply(clone, 1, {kind="MoveUnit", unitId=tonumber(unitId) :: number, tileId=tileId}).ok)
        end
    end
end
local state = Game.new(3)
assert(Game.apply(state, 1, {kind="FoundCity", unitId=1}).ok)
local city, warrior = state.cities[2], state.units[1]
assert(warrior.kind == "Warrior")
local malformed: {any} = {nil, false, "bad", 0, {kind="FortifyUnit"}, {kind="UpgradeUnit",unitId=0/0}, {kind="MoveUnit",unitId=warrior.id,tileId=math.huge}, {kind="Purchase",cityId=city.id,item={}}, {kind="Purchase",cityId=-1,item="Scout"}, {kind="SetProduction",cityId=city.id,item="Unknown"}, {kind="UpgradeUnit",unitId=3}, {kind="FortifyUnit",unitId=3}}
for _, command in malformed do rejected(state, command) end
rejected(state, nil)
rejected(state, setmetatable({kind="EndTurn"},{}))
rejected(state, {kind="Purchase",cityId=city.id,item="Granary"})
rejected(state, {kind="UpgradeUnit",unitId=warrior.id})
-- Controlled economy fixture: funds/technologies are not exposed as commands.
state.players[1].gold = 1000; state.players[1].technologies = {"Agriculture", "BronzeWorking"}
assert(Game.apply(state, 1, {kind="UpgradeUnit",unitId=warrior.id}).ok)
assert(warrior.level == 1 and state.players[1].gold == 970)
rejected(state, {kind="UpgradeUnit",unitId=warrior.id})
warrior.hp = 40
assert(Game.apply(state, 1, {kind="FortifyUnit",unitId=warrior.id}).ok)
assert(warrior.moves == 0 and warrior.fortified)
rejected(state, {kind="FortifyUnit",unitId=warrior.id})
assert(Game.apply(state, 1, {kind="EndTurn"}).ok)
assert(warrior.hp == 56 and warrior.fortified)
local target = Game.snapshot(state, 1).legalMoves[tostring(warrior.id)][1]
assert(target and Game.apply(state, 1, {kind="MoveUnit",unitId=warrior.id,tileId=target}).ok and not warrior.fortified)
for _, building in {"Granary", "Workshop", "Library"} do
    local funds = state.players[1].gold
    assert(Game.apply(state, 1, {kind="Purchase",cityId=city.id,item=building}).ok)
    assert(state.players[1].gold == funds - (Game.getRules().purchaseCosts :: any)[building])
    assert(table.find(city.buildings, building))
    rejected(state, {kind="Purchase",cityId=city.id,item=building})
    rejected(state, {kind="SetProduction",cityId=city.id,item=building})
end
local count, gold = #state.units, state.players[1].gold
assert(Game.apply(state, 1, {kind="Purchase",cityId=city.id,item="Scout"}).ok)
assert(#state.units == count + 1 and state.players[1].gold == gold - 36 and state.units[#state.units].kind == "Scout")
rejected(state, {kind="FortifyUnit",unitId=state.units[#state.units].id})
-- Building production happens once and resets the queue; effect changes actual food/production/science.
local base, built = Game.new(4), Game.new(4)
for _, fixture in {base, built} do assert(Game.apply(fixture,1,{kind="FoundCity",unitId=1}).ok) end
built.cities[2].buildings = {"Granary","Workshop","Library"}
assert(Game.apply(base,1,{kind="EndTurn"}).ok and Game.apply(built,1,{kind="EndTurn"}).ok)
assert(built.cities[2].food == base.cities[2].food + 2 and built.cities[2].production == base.cities[2].production + 2 and built.players[1].science == base.players[1].science + 3)
local production = Game.new(5); assert(Game.apply(production,1,{kind="FoundCity",unitId=1}).ok)
assert(Game.apply(production,1,{kind="SetProduction",cityId=2,item="Granary"}).ok)
production.cities[2].production = 16
assert(Game.apply(production,1,{kind="EndTurn"}).ok)
assert(#production.cities[2].buildings == 1 and production.cities[2].queue == "Warrior")
-- No deployable tile means no purchase spending or production consumption.
local blocked = Game.new(1); assert(Game.apply(blocked,1,{kind="FoundCity",unitId=1}).ok)
blocked.players[1].gold = 100
local home = blocked.cities[2]
local center = blocked.tiles[home.tileId]
for _, tile in blocked.tiles do
    if HexMath.getDistanceXY(center.x,center.y,tile.x,tile.y) <= 1 then
        local occupied = false
        for _, unit in blocked.units do if unit.tileId == tile.id then occupied=true end end
        if not occupied then table.insert(blocked.units,{id=blocked.nextUnit,ownerId=1,kind="Warrior",tileId=tile.id,hp=100,moves=0,fortified=false,level=0}); blocked.nextUnit += 1 end
    end
end
rejected(blocked,{kind="Purchase",cityId=home.id,item="Warrior"})
home.production = 20
assert(Game.apply(blocked,1,{kind="EndTurn"}).ok)
assert(home.production >= 20)
-- Optional forest is authoritative in both command validation and legal destinations.
local forest = Game.new(2,{forest=true})
local forestWarrior = forest.units[2]
local forestTarget: Game.Tile? = nil
for _, tile in forest.tiles do
    if tile.terrain ~= "Forest" then continue end
    for _, neighbor in forest.tiles do
        if HexMath.getDistanceXY(tile.x,tile.y,neighbor.x,neighbor.y) ~= 1 then continue end
        local occupied=false
        for _, unit in forest.units do if unit.id ~= forestWarrior.id and (unit.tileId == tile.id or unit.tileId == neighbor.id) then occupied=true end end
        local hostileCity=false
        for _, candidate in forest.cities do if candidate.tileId == tile.id or candidate.tileId == neighbor.id then hostileCity=true end end
        if not occupied and not hostileCity then forestWarrior.tileId=neighbor.id; forestTarget=tile; break end
    end
    if forestTarget then break end
end
assert(forestTarget)
forestWarrior.moves=1
assert(not table.find(Game.snapshot(forest,1).legalMoves[tostring(forestWarrior.id)],forestTarget.id))
rejected(forest,{kind="MoveUnit",unitId=forestWarrior.id,tileId=forestTarget.id})
forestWarrior.moves=2
assert(Game.apply(forest,1,{kind="MoveUnit",unitId=forestWarrior.id,tileId=forestTarget.id}).ok and forestWarrior.moves==0)
-- Fortification only improves defense, not an attack initiated from a fortified tile.
local combat = Game.new(1)
local enemy = combat.units[3]
local adjacent = Game.snapshot(combat,2).legalMoves[tostring(enemy.id)][1]
assert(adjacent)
combat.units[2].tileId=adjacent
local attackerFortified = Game.restore(Game.serialize(combat)); assert(attackerFortified)
local defenderFortified = Game.restore(Game.serialize(combat)); assert(defenderFortified)
attackerFortified.units[2].fortified=true; defenderFortified.units[3].fortified=true
for _, fixture in {combat,attackerFortified,defenderFortified} do assert(Game.apply(fixture,1,{kind="MoveUnit",unitId=2,tileId=enemy.tileId}).ok) end
assert(combat.units[2].hp==attackerFortified.units[2].hp and combat.units[3].hp==attackerFortified.units[3].hp)
assert(defenderFortified.units[3].hp>combat.units[3].hp)
-- Simultaneous lethal city combat leaves a defeated uncaptured city at zero HP,
-- and remains saveable until healing/capture on a later action.
local lethal = Game.new(1)
local approach = Game.snapshot(lethal,2).legalMoves["3"][1]; assert(approach)
table.remove(lethal.units,3)
lethal.units[2].tileId=approach; lethal.units[2].hp=1; lethal.cities[1].hp=1
assert(Game.apply(lethal,1,{kind="MoveUnit",unitId=2,tileId=lethal.cities[1].tileId}).ok)
assert(#lethal.units==1 and lethal.cities[1].hp==0 and lethal.cities[1].ownerId==2)
assert(Game.restore(Game.serialize(lethal)))
-- Save copies detach both directions; snapshots and saves never alias live state.
local saved = Game.serialize(state)
local restored = Game.restore(saved); assert(restored)
local initial = Game.serialize(restored)
saved.state.players[1].gold = 1
assert(equal(initial, Game.serialize(restored)))
restored.players[1].gold = 2
assert(state.players[1].gold ~= 2)
local clean = Game.serialize(Game.new(1))
local corruptions: {(any)->()} = {
    function(v) v.format="foreign" end, function(v) v.version=2 end, function(v) v.extra=true end,
    function(v) v.state.extra=true end, function(v) v.state.turn=0 end, function(v) v.state.turn=41 end,
    function(v) v.state.seed=0/0 end, function(v) v.state.revision=math.huge end, function(v) v.state.radius=6 end,
    function(v) v.state.difficulty="Impossible" end, function(v) v.state.forest="yes" end,
    function(v) v.state.phase="Waiting" end, function(v) v.state.winner=1 end, function(v) v.state.reason="bad" end,
    function(v) v.state.nextUnit=3 end, function(v) v.state.nextCity=1 end, function(v) v.state.aiCapital=999 end,
    function(v) v.state.tiles[1].x=99 end, function(v) v.state.tiles[1].terrain="Ocean" end,
    function(v) v.state.tiles[1].food=999 end, function(v) v.state.tiles[1].ownerId=3 end,
    function(v) v.state.tiles[2].x=v.state.tiles[1].x; v.state.tiles[2].y=v.state.tiles[1].y end,
    function(v) v.state.tiles[2].id=1 end, function(v) v.state.tiles[1]=nil end,
    function(v) v.state.units[1].id=0/0 end, function(v) v.state.units[1].hp=0 end,
    function(v) v.state.units[1].moves=999 end, function(v) v.state.units[1].kind="Dragon" end,
    function(v) v.state.units[1].tileId=99 end, function(v) v.state.units[1].ownerId=0 end,
    function(v) v.state.units[2].tileId=v.state.units[1].tileId end,
    function(v) v.state.units[2].id=v.state.units[1].id end,
    function(v) v.state.units[1].fortified=true end, function(v) v.state.units[2].level=2 end,
    function(v) v.state.units[2].level=1 end, function(v) v.state.cities[1].hp=-1 end,
    function(v) v.state.cities[1].population=-1 end, function(v) v.state.cities[1].queue="Dragon" end,
    function(v) v.state.cities[1].buildings={"Granary","Granary"} end,
    function(v) v.state.cities[1].buildings={"Warrior"} end,
    function(v) v.state.cities[1].ownerId=1 end,
    function(v) v.state.players[1].gold=-1 end, function(v) v.state.players[1].technologies={"Writing"} end,
    function(v) v.state.players[1].technologies={"Agriculture","Agriculture"} end,
    function(v) v.state.players[1].research={id="Agriculture",progress=12,cost=12} end,
    function(v) v.state.players[1].research={id="Dragon",progress=0,cost=12} end,
    function(v) v.state.players[1].research={id="Agriculture",progress=0,cost=1} end,
    function(v) v.state.players[1].research={id="Writing",progress=0,cost=24} end,
    function(v) v.state.events={{id=1,kind="Move",message="bad",tileId=999}};v.state.nextEvent=2 end,
    function(v) v.state.events={{id=1,kind="Move",message="bad"}} end,
    function(v) v.state.log={string.rep("x",257)} end,
    function(v) setmetatable(v.state,{}) end,
    function(v) v.state.units[1].kind=v end,
    function(v) v.state.players[1].research=v.state end,
    function(v) for _=1,33 do table.insert(v.state.events,{id=1,kind="Move",message="bad"}) end end,
    function(v) v.state.tiles[1].x=0.5 end,
    function(v) v.state.units[1].hp=0/0 end,
    function(v) v.state.nextEvent=0 end,
    function(v) v.state.phase="Finished";v.state.winner=3;v.state.reason="bad" end,
    function(v) v.state.units[1].tileId={} end,
    function(v) v.state.nextEvent=2 end,
    function(v) v.state.units={v.state.units[3]} end,
    function(v) v.state.events={{id=1,kind="Move",message="bad"},{id=3,kind="Move",message="bad"}};v.state.nextEvent=4 end,
}
-- The old substring whitelist accepted compound names consisting of adjacent
-- valid schema keys. Check every object shape, including the empty string key.
for _, compound in {"format version", "version state", ""} do
    table.insert(corruptions, function(v) v[compound] = {} end)
end
for _, compound in {"seed difficulty", "difficulty radius", "tiles units", "nextUnit nextCity", ""} do
    table.insert(corruptions, function(v) v.state[compound] = {} end)
end
for _, compound in {"id x", "ownerId food", ""} do
    table.insert(corruptions, function(v) v.state.tiles[1][compound] = {} end)
end
for _, compound in {"id ownerId", "fortified level", ""} do
    table.insert(corruptions, function(v) v.state.units[1][compound] = {} end)
end
for _, compound in {"name population", "hp buildings", ""} do
    table.insert(corruptions, function(v) v.state.cities[1][compound] = {} end)
end
for _, compound in {"gold science", "technologies research", ""} do
    table.insert(corruptions, function(v) v.state.players[1][compound] = {} end)
end
for _, compound in {"id progress", "progress cost", ""} do
    table.insert(corruptions, function(v)
        v.state.players[1].research = {id="Agriculture",progress=0,cost=12,[compound]={}}
    end)
end
for _, compound in {"id kind", "ownerId amount", ""} do
    table.insert(corruptions, function(v)
        v.state.events = {{id=1,kind="Move",message="test",[compound]={}}}; v.state.nextEvent=2
    end)
end
-- Unexpected cyclic/deep payloads must reject before Game.restore's copy can recurse.
table.insert(corruptions, function(v) v.state["seed difficulty"] = v end)
table.insert(corruptions, function(v) v.state["seed difficulty"] = v.state end)
table.insert(corruptions, function(v)
    local payload: any = {}; payload.self = payload; v.state["seed difficulty"] = payload
end)
table.insert(corruptions, function(v)
    local payload: any = {}; v.state["seed difficulty"] = payload
    for _=1,10000 do local nextNode = {}; payload.child=nextNode; payload=nextNode end
end)
table.insert(corruptions, function(v)
    local payload: any = {}; v.state.extra=payload
    for _=1,10000 do local nextNode = {}; payload.child=nextNode; payload=nextNode end
end)
table.insert(corruptions, function(v) v.state["seed difficulty"] = function() return true end end)
table.insert(corruptions, function(v) v.state["seed difficulty"] = string.rep("x",100000) end)
table.insert(corruptions, function(v) v.state.players[2] = v.state.players[1] end)
table.insert(corruptions, function(v)
    local payload = {}; v.state["seed difficulty"] = payload
    for index=1,9000 do payload[index]=true end
end)
for index, corrupt in corruptions do
    local candidate = Game.serialize(Game.new(1)); corrupt(candidate)
    local ok, result = pcall(function() return Game.restore(candidate) end)
    assert(ok and result == nil, "corrupt save " .. index .. " must reject without exception")
    local validState = Game.restore({format="unciv-luau-original",version=1,state=candidate.state})
    if validState == nil then
        local serialized = pcall(function() return Game.serialize(candidate.state) end)
        assert(not serialized, "corrupt state " .. index .. " must fail before serialization copy")
    end
    assert(equal(clean, Game.serialize(Game.new(1))))
end
for _, invalid in {false, 42, "bad", {}} do assert(Game.restore(invalid) == nil) end
assert(Game.restore(nil) == nil)
assert(not pcall(function() Game.new(1,{difficulty="bad"}) end))
assert(not pcall(function() Game.new(1,{radius=2}) end))
assert(not pcall(function() Game.new(1e20) end))
print("simulation release: resumed replay, 18 varied matches, legal moves/forest, combat fortification, upgrades/buildings/blocked purchases, detached saves and " .. #corruptions .. " corrupt-schema checks passed")
