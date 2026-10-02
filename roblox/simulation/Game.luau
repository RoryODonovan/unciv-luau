--!strict
-- Generated module-only Roblox form. Source: src/simulation/Game.luau
-- Source SHA-256: c69fd537e7a86b5032bffb149ea2df6afc4d50ac0eeb3a40c26b59b444131ad1
-- Reproduce with tools/roblox-export.mjs; preserve MPL notices below.
-- Covered source: https://github.com/RoryODonovan/unciv-luau
-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- Obtain a copy at https://mozilla.org/MPL/2.0/.
--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original bounded simulation orchestration and AI; synthetic rules, no copied assets.
-- Provenance-Kind: original
-- Uses attributed HexMath and Mechanics; does not implement full Unciv gameplay.
local HexMath = require(script.Parent.Parent.map.HexMath)
local Mechanics = require(script.Parent.Mechanics)
local Rules = require(script.Parent.Rules)
local Save = require(script.Parent.Save)
export type Command = {kind: "MoveUnit", unitId: number, tileId: number}
    | {kind: "FoundCity", unitId: number} | {kind: "SetProduction", cityId: number, item: string}
    | {kind: "Research", technology: string} | {kind: "EndTurn"}
    | {kind: "FortifyUnit", unitId: number} | {kind: "UpgradeUnit", unitId: number} | {kind: "Purchase", cityId: number, item: string}
export type Tile = {id: number, x: number, y: number, terrain: string, ownerId: number?, food: number, production: number}
export type Unit = {id: number, ownerId: number, kind: string, tileId: number, hp: number, moves: number, fortified: boolean, level: number}
export type City = {id: number, ownerId: number, tileId: number, name: string, population: number, food: number, production: number, queue: string, hp: number, buildings: {string}}
export type Research = {id: string, progress: number, cost: number}
export type Technology = {id: string, name: string, cost: number, prerequisites: {string}}
type Player = {gold: number, science: number, technologies: {string}, research: Research?}
export type Event = {id: number, kind: string, message: string, tileId: number?, unitId: number?, ownerId: number?, amount: number?}
export type Options = {difficulty: string?, radius: number?, forest: boolean?}
export type Statistics = {cities: number, units: number, population: number, technologies: number}
export type State = {seed: number, difficulty: string, radius: number, forest: boolean, events: {Event}, nextEvent: number, turn: number, revision: number, phase: string, winner: number?, reason: string?, tiles: {Tile}, units: {Unit}, cities: {City}, players: {Player}, log: {string}, nextUnit: number, nextCity: number, aiCapital: number}
export type View = {seed: number, difficulty: string, legalMoves: {[string]: {number}}, events: {Event}, scores: {number}, statistics: {Statistics}, productionCosts: {[string]: number}, purchaseCosts: {[string]: number}, turn: number, revision: number, phase: string, winner: number?, reason: string?, gold: number, science: number, research: Research?, technologies: {string}, tiles: {Tile}, units: {Unit}, cities: {City}, log: {string}, availableProduction: {string}, availableResearch: {Technology}, objectives: {string}}
local Game = {}
local function copy<T>(value: T): T
    if type(value) ~= "table" then return value :: T end
    local result: any = {}
    for key, child in value :: any do result[key] = copy(child) end
    return result
end
local function event(state: State, kind: string, message: string, tileId: number?, unitId: number?, ownerId: number?, amount: number?)
    table.insert(state.events, {id = state.nextEvent, kind = kind, message = message, tileId = tileId, unitId = unitId, ownerId = ownerId, amount = amount})
    state.nextEvent += 1
    if #state.events > 32 then table.remove(state.events, 1) end
end
local function log(state: State, message: string)
    table.insert(state.log, message)
    if #state.log > 16 then table.remove(state.log, 1) end
end
local function tileById(state: State, id: number): Tile?
    for _, tile in state.tiles do if tile.id == id then return tile end end
    return nil
end
local function unitById(state: State, id: number): Unit?
    for _, unit in state.units do if unit.id == id then return unit end end
    return nil
end
local function unitAt(state: State, tileId: number): Unit?
    for _, unit in state.units do if unit.tileId == tileId then return unit end end
    return nil
end
local function cityAt(state: State, tileId: number): City?
    for _, city in state.cities do if city.tileId == tileId then return city end end
    return nil
end
local function distance(state: State, a: number, b: number): number
    local first, second = tileById(state, a), tileById(state, b)
    assert(first and second)
    return HexMath.getDistanceXY(first.x, first.y, second.x, second.y)
end
local function hasTechnology(player: Player, id: string): boolean
    return table.find(player.technologies, id) ~= nil
end
local function eligible(player: Player, technology: Technology): boolean
    if hasTechnology(player, technology.id) then return false end
    for _, prerequisite in technology.prerequisites do if not hasTechnology(player, prerequisite) then return false end end
    return true
end
local function addUnit(state: State, owner: number, kind: string, tileId: number)
    local stats = (Rules.unitStats :: any)[kind]
    table.insert(state.units, {id = state.nextUnit, ownerId = owner, kind = kind, tileId = tileId, hp = stats.hp, moves = 0, fortified = false, level = 0})
    state.nextUnit += 1
end
local function removeUnit(state: State, id: number)
    for index, unit in state.units do if unit.id == id then table.remove(state.units, index); return end end
end
local function claim(state: State, city: City)
    for _, tile in state.tiles do
        if distance(state, city.tileId, tile.id) <= 1 and (tile.ownerId == nil or tile.id == city.tileId) then tile.ownerId = city.ownerId end
    end
end
local function addCity(state: State, owner: number, tileId: number): City
    local city: City = {id = state.nextCity, ownerId = owner, tileId = tileId, name = (if owner == 1 then "Haven " else "Rival ") .. tostring(state.nextCity), population = 1, food = 0, production = 0, queue = "Warrior", hp = 100, buildings = {}}
    state.nextCity += 1
    table.insert(state.cities, city)
    claim(state, city)
    return city
end
local function finish(state: State, winner: number, reason: string)
    state.phase = "Finished"; state.winner = winner; state.reason = reason
    log(state, reason)
    event(state, if winner == 1 then "Victory" else "Defeat", reason, nil, nil, winner)
end
local function evaluate(state: State)
    if state.phase == "Finished" then return end
    for _, city in state.cities do if city.id == state.aiCapital and city.ownerId == 1 then finish(state, 1, "You captured the rival capital."); return end end
    local survives = false
    for _, city in state.cities do if city.ownerId == 1 then survives = true end end
    for _, unit in state.units do if unit.ownerId == 1 and unit.kind == "Settler" then survives = true end end
    if not survives then finish(state, 2, "Your civilization has no city or settler.") end
end
local function strength(state: State, unit: Unit): number
    return 10 + (if hasTechnology(state.players[unit.ownerId], "BronzeWorking") then 3 else 0) + unit.level * 3 + (if unit.fortified then 3 else 0)
end
local function attack(state: State, attacker: Unit, destination: Tile)
    attacker.fortified = false
    local defender, city = unitAt(state, destination.id), cityAt(state, destination.id)
    local defense = if defender then (if defender.kind == "Warrior" then strength(state, defender) else 3) else 9
    local defenderHp = if defender then defender.hp else (city :: City).hp
    local ratio = strength(state, attacker) / defense
    local outgoing = math.max(1, math.floor(Mechanics.damage(ratio, false, 0.5) * (0.5 + attacker.hp / 200) + 0.5))
    local incoming = if defender and defender.kind == "Settler" then 0 else math.max(1, math.floor(Mechanics.damage(ratio, true, 0.5) * (0.5 + defenderHp / 200) + 0.5))
    attacker.fortified = false
    attacker.moves = 0; attacker.hp -= incoming
    event(state, "Attack", "Attack dealt " .. outgoing .. " damage.", destination.id, attacker.id, attacker.ownerId, outgoing)
    if defender then defender.hp -= outgoing else (city :: City).hp = math.max(0, (city :: City).hp - outgoing) end
    log(state, "Warrior " .. attacker.id .. " attacked: " .. outgoing .. " damage, " .. incoming .. " received.")
    if defender and defender.hp <= 0 then removeUnit(state, defender.id) end
    if attacker.hp <= 0 then removeUnit(state, attacker.id) end
    if attacker.hp > 0 and unitAt(state, destination.id) == nil then
        if city and city.ownerId ~= attacker.ownerId then
            if city.hp <= 0 then
                city.ownerId = attacker.ownerId; city.hp = 50; city.production = 0; city.queue = "Warrior"
                for _, tile in state.tiles do if distance(state, city.tileId, tile.id) <= 1 then tile.ownerId = city.ownerId end end
                attacker.tileId = destination.id
                log(state, city.name .. " was captured.")
            end
        else attacker.tileId = destination.id end
    end
    evaluate(state)
end
local function move(state: State, unit: Unit, destination: Tile)
    local defender, city = unitAt(state, destination.id), cityAt(state, destination.id)
    if (defender and defender.ownerId ~= unit.ownerId) or (city and city.ownerId ~= unit.ownerId) then attack(state, unit, destination)
    else unit.tileId = destination.id; unit.moves -= if destination.terrain == "Forest" then 2 else 1; event(state, "Move", "Unit moved.", destination.id, unit.id, unit.ownerId) end
    unit.fortified = false
end
local function isBuilding(item: string): boolean
    return item == "Granary" or item == "Workshop" or item == "Library"
end
local function spawnTile(state: State, city: City): Tile?
    for _, tile in state.tiles do
        local existingCity = cityAt(state, tile.id)
        if distance(state, city.tileId, tile.id) <= 1 and unitAt(state, tile.id) == nil and (not existingCity or existingCity.ownerId == city.ownerId) then return tile end
    end
    return nil
end
local function completeItem(state: State, city: City, item: string, spawn: Tile?)
    if isBuilding(item) then table.insert(city.buildings, item); if city.queue == item then city.queue = "Warrior" end
    else assert(spawn); addUnit(state, city.ownerId, item, spawn.id) end
end
local function canMove(state: State, unit: Unit, tile: Tile): boolean
    if state.phase ~= "Playing" or unit.moves <= 0 or distance(state, unit.tileId, tile.id) ~= 1 then return false end
    local occupant, city = unitAt(state, tile.id), cityAt(state, tile.id)
    if occupant and occupant.ownerId == unit.ownerId then return false end
    local hostile = (occupant and occupant.ownerId ~= unit.ownerId) or (city and city.ownerId ~= unit.ownerId)
    if hostile and unit.kind ~= "Warrior" then return false end
    return hostile ~= nil and hostile ~= false or unit.moves >= (if tile.terrain == "Forest" then 2 else 1)
end
local function scores(state: State): ({number}, {Statistics})
    local result, stats = {0, 0}, {} :: {Statistics}
    for owner = 1, 2 do table.insert(stats, {cities = 0, units = 0, population = 0, technologies = #state.players[owner].technologies}); result[owner] += stats[owner].technologies * 5 end
    for _, city in state.cities do local row = stats[city.ownerId]; row.cities += 1; row.population += city.population; result[city.ownerId] += 10 + city.population * 3 end
    for _, unit in state.units do stats[unit.ownerId].units += 1; result[unit.ownerId] += 2 end
    return result, stats
end
local function economy(state: State, owner: number)
    local player = state.players[owner]
    for _, city in state.cities do
        if city.ownerId ~= owner then continue end
        local worked: {Tile} = {}
        for _, tile in state.tiles do if tile.ownerId == owner and distance(state, city.tileId, tile.id) <= 1 then table.insert(worked, tile) end end
        table.sort(worked, function(a: Tile, b: Tile) return if a.food + a.production == b.food + b.production then a.id < b.id else a.food + a.production > b.food + b.production end)
        local food, production = 2, 2
        for index = 1, math.min(city.population, #worked) do food += worked[index].food; production += worked[index].production end
        if hasTechnology(player, "Agriculture") then food += 1 end
        if table.find(city.buildings, "Granary") then food += 2 end
        if table.find(city.buildings, "Workshop") then production += 2 end
        if hasTechnology(player, "Engineering") then production += 1 end
        city.food += math.max(1, food - city.population)
        local threshold = Mechanics.growthFood(city.population)
        if city.food >= threshold then city.food -= threshold; city.population += 1; log(state, city.name .. " grew to " .. city.population .. "."); event(state, "Growth", "City grew.", city.tileId, nil, owner, city.population) end
        city.production += if owner == 2 and state.difficulty == "Easy" then math.max(1, math.floor(production / 2)) else production
        city.hp = math.min(100, city.hp + (if hasTechnology(player, "Masonry") then 8 else 5))
        player.gold += city.population + 1
        local science = city.population + 2 + (if hasTechnology(player, "Writing") then 2 else 0) + (if table.find(city.buildings, "Library") then 3 else 0)
        player.science += science
        if player.research then
            player.research.progress += science
            if player.research.progress >= player.research.cost then
                table.insert(player.technologies, player.research.id)
                log(state, (if owner == 1 then "You researched " else "Rival researched ") .. player.research.id .. ".")
                event(state, "Research", "Technology completed: " .. player.research.id, nil, nil, owner)
                player.research = nil
            end
        end
        local item = city.queue
        local cost: number = (Rules.productionCosts :: any)[item]
        if city.production >= cost then
            local spawn = spawnTile(state, city)
            if isBuilding(item) or spawn then
                city.production -= cost; completeItem(state, city, item, spawn)
                log(state, city.name .. " produced a " .. item .. ".")
                event(state, "Production", "Completed " .. item .. ".", city.tileId, nil, owner)
            end
        end
    end
end
local function ai(state: State)
    local player = state.players[2]
    if not player.research then
        for _, technology in Rules.technologies do if eligible(player, technology) then player.research = {id = technology.id, progress = 0, cost = technology.cost}; break end end
    end
    economy(state, 2)
    local order: {number} = {}
    for _, unit in state.units do if unit.ownerId == 2 then unit.moves = if state.difficulty == "Hard" then 2 else 1; table.insert(order, unit.id) end end
    for _, id in order do
        local unit = unitById(state, id)
        if not unit or state.phase == "Finished" then continue end
        for _ = 1, (if state.difficulty == "Hard" then 2 else 1) do
            if unit.hp <= 0 or unit.moves <= 0 or tostring(state.phase) == "Finished" then break end
            if state.difficulty ~= "Easy" and unit.hp < 45 then
                unit.fortified = true; unit.moves = 0; unit.hp = math.min(100, unit.hp + 16); break
            end
            local target: number? = nil
            local bestDistance = math.huge
            for _, city in state.cities do if city.ownerId == 1 and distance(state, unit.tileId, city.tileId) < bestDistance then target = city.tileId; bestDistance = distance(state, unit.tileId, city.tileId) end end
            if not target then for _, enemy in state.units do if enemy.ownerId == 1 and distance(state, unit.tileId, enemy.tileId) < bestDistance then target = enemy.tileId; bestDistance = distance(state, unit.tileId, enemy.tileId) end end end
            if not target then break end
            local nextTile: Tile? = nil
            local nextDistance = math.huge
            for _, tile in state.tiles do
                local occupant = unitAt(state, tile.id)
                if canMove(state, unit, tile) then
                    local d = distance(state, tile.id, target)
                    if state.difficulty ~= "Easy" and occupant and occupant.ownerId == 1 then d -= (if occupant.hp < 45 then 3 else 1) end
                    if d < nextDistance then nextTile = tile; nextDistance = d end
                end
            end
            if nextTile and nextDistance < bestDistance then move(state, unit, nextTile) else break end
        end
    end
end
function Game.new(seed: number?, options: Options?): State
    local settings: Options = options or {}
    local difficulty = settings.difficulty or "Easy"
    local radius = settings.radius or 3
    assert(difficulty == "Easy" or difficulty == "Normal" or difficulty == "Hard", "unknown difficulty")
    assert(radius >= 3 and radius <= 5 and radius % 1 == 0, "radius must be an integer from 3 to 5")
    local supplied = seed or 1
    assert(supplied == supplied and math.abs(supplied) <= 9007199254740991 and supplied % 1 == 0, "seed must be a finite integer")
    local random = supplied % 2147483647
    if random == 0 then random = 1 end
    local state: State = {seed = supplied, difficulty = difficulty, radius = radius, forest = settings.forest == true, events = {}, nextEvent = 1, turn = 1, revision = 0, phase = "Playing", tiles = {}, units = {}, cities = {}, players = {}, log = {}, nextUnit = 1, nextCity = 1, aiCapital = 0}
    for _ = 1, 2 do table.insert(state.players, {gold = 0, science = 0, technologies = {}}) end
    for x = -radius, radius do for y = -radius, radius do
        if HexMath.getDistanceXY(0, 0, x, y) <= radius then
            random = (random * 48271) % 2147483647
            local terrain = if settings.forest and random % 5 == 0 then "Forest" elseif random % 4 == 0 then "Hills" else "Plains"
            local yields = (Rules.terrainYields :: any)[terrain]
            table.insert(state.tiles, {id = #state.tiles + 1, x = x, y = y, terrain = terrain, food = yields.food, production = yields.production})
        end
    end end
    local start, rival = 0, 0
    for _, tile in state.tiles do if tile.x == -2 and tile.y == -1 then start = tile.id elseif tile.x == 2 and tile.y == 1 then rival = tile.id end end
    addUnit(state, 1, "Settler", start)
    for _, tile in state.tiles do if distance(state, tile.id, start) == 1 then addUnit(state, 1, "Warrior", tile.id); break end end
    local capital = addCity(state, 2, rival); state.aiCapital = capital.id
    addUnit(state, 2, "Warrior", rival)
    for _, unit in state.units do unit.moves = (Rules.unitStats :: any)[unit.kind].moves end
    log(state, "Found a city, research technologies, and capture the rival capital within 40 rounds.")
    return state
end
function Game.apply(state: State, actorId: number, command: Command): {ok: boolean, message: string}
    local function reject(message: string): {ok: boolean, message: string} return {ok = false, message = message} end
    if state.phase ~= "Playing" then return reject("The match has finished.") end
    if actorId ~= 1 then return reject("Only the human player can submit commands.") end
    if type(command) ~= "table" or getmetatable(command) ~= nil then return reject("Invalid command.") end
    local function finiteId(id: any): boolean return type(id) == "number" and id == id and id >= 1 and id <= 1000000 and id % 1 == 0 end
    if command.kind == "MoveUnit" or command.kind == "FoundCity" or command.kind == "FortifyUnit" or command.kind == "UpgradeUnit" then
        if not finiteId(command.unitId) then return reject("Invalid unit identifier.") end
        local unit = unitById(state, command.unitId :: number)
        if not unit or unit.ownerId ~= actorId then return reject("Select one of your units.") end
        if command.kind == "UpgradeUnit" then
            local player = state.players[actorId]
            if unit.kind ~= "Warrior" or unit.level >= 1 or not hasTechnology(player, "BronzeWorking") or player.gold < Rules.upgradeCost then return reject("Upgrade requires an unupgraded warrior, Bronze Working and 30 gold.") end
            player.gold -= Rules.upgradeCost; unit.level = 1
            event(state, "Upgrade", "Warrior upgraded.", unit.tileId, unit.id, actorId)
        elseif command.kind == "FortifyUnit" then
            if unit.kind ~= "Warrior" or unit.moves <= 0 or unit.fortified then return reject("Select a warrior with movement to fortify.") end
            unit.fortified = true; unit.moves = 0
        elseif unit.moves <= 0 then return reject("This unit has no movement remaining.")
        elseif command.kind == "MoveUnit" then
            if not finiteId(command.tileId) then return reject("Invalid tile identifier.") end
            local destination = tileById(state, command.tileId)
            if not destination or distance(state, unit.tileId, destination.id) ~= 1 then return reject("Move to an adjacent tile.") end
            local occupant, city = unitAt(state, destination.id), cityAt(state, destination.id)
            if occupant and occupant.ownerId == actorId then return reject("A friendly unit occupies that tile.") end
            if unit.kind ~= "Warrior" and ((occupant and occupant.ownerId ~= actorId) or (city and city.ownerId ~= actorId)) then return reject("Settlers cannot attack.") end
            if not canMove(state, unit, destination) then return reject("Not enough movement for this terrain.") end
            move(state, unit, destination)
        else
            if unit.kind ~= "Settler" then return reject("Only settlers can found cities.") end
            for _, city in state.cities do if distance(state, city.tileId, unit.tileId) < 2 then return reject("Found at least two tiles from an existing city.") end end
            local city = addCity(state, actorId, unit.tileId); removeUnit(state, unit.id); log(state, "Founded " .. city.name .. "."); event(state, "FoundCity", "Founded " .. city.name .. ".", city.tileId, unit.id, actorId)
        end
    elseif command.kind == "SetProduction" or command.kind == "Purchase" then
        if not finiteId(command.cityId) then return reject("Invalid city identifier.") end
        local city: City? = nil
        for _, candidate in state.cities do if candidate.id == command.cityId then city = candidate; break end end
        if not city or city.ownerId ~= actorId then return reject("Select one of your cities.") end
        if type(command.item) ~= "string" or (Rules.productionCosts :: any)[command.item] == nil then return reject("Unknown production item.") end
        if isBuilding(command.item) and table.find(city.buildings, command.item) then return reject("This city already has that building.") end
        if command.kind == "Purchase" then
            local cost: number = (Rules.purchaseCosts :: any)[command.item]
            local player = state.players[actorId]
            if player.gold < cost then return reject("Not enough gold.") end
            local spawn = spawnTile(state, city)
            if not isBuilding(command.item) and not spawn then return reject("No free tile to deploy this unit.") end
            player.gold -= cost; completeItem(state, city, command.item, spawn)
            event(state, "Purchase", "Purchased " .. command.item .. ".", city.tileId, nil, actorId, cost)
        else
            if city.queue == command.item then return reject("Already producing this item.") end
            city.queue = command.item
        end
    elseif command.kind == "Research" then
        local selected: Technology? = nil
        for _, technology in Rules.technologies do if technology.id == command.technology then selected = technology; break end end
        if not selected or not eligible(state.players[actorId], selected) then return reject("Technology is unavailable or prerequisites are missing.") end
        if state.players[actorId].research and (state.players[actorId].research :: Research).id == selected.id then return reject("Already researching this technology.") end
        state.players[actorId].research = {id = selected.id, progress = 0, cost = selected.cost}
    elseif command.kind == "EndTurn" then
        economy(state, 1); ai(state); evaluate(state)
        if state.phase == "Playing" then
            if state.turn >= Rules.maxTurns then
                local scores = scores(state)
                finish(state, if scores[1] > scores[2] then 1 else 2, "Round limit reached: " .. scores[1] .. " to " .. scores[2] .. "; ties favor the rival.")
            else
                state.turn += 1
                for _, unit in state.units do if unit.ownerId == 1 then unit.moves = (Rules.unitStats :: any)[unit.kind].moves; if not cityAt(state, unit.tileId) or (cityAt(state, unit.tileId) :: City).ownerId == 1 then unit.hp = math.min((Rules.unitStats :: any)[unit.kind].hp, unit.hp + (if unit.fortified then 16 else 8)) end end end
            end
        end
    else return reject("Unknown command.") end
    state.revision += 1
    return {ok = true, message = "Command completed."}
end
function Game.snapshot(state: State, actorId: number): View
    assert(actorId == 1 or actorId == 2, "unknown actor")
    local player = state.players[actorId]
    local research: {Technology} = {}
    for _, technology in Rules.technologies do if eligible(player, technology) then table.insert(research, copy(technology)) end end
    local legal: {[string]: {number}} = {}
    for _, unit in state.units do
        if unit.ownerId == actorId then
            local targets = {} :: {number}
            for _, tile in state.tiles do if canMove(state, unit, tile) then table.insert(targets, tile.id) end end
            legal[tostring(unit.id)] = targets
        end
    end
    local score, stats = scores(state)
    return {seed = state.seed, difficulty = state.difficulty, legalMoves = legal, events = copy(state.events), scores = score, statistics = stats, productionCosts = copy(Rules.productionCosts) :: any, purchaseCosts = copy(Rules.purchaseCosts) :: any, turn = state.turn, revision = state.revision, phase = state.phase, winner = state.winner, reason = state.reason, gold = player.gold, science = player.science, research = copy(player.research), technologies = copy(player.technologies), tiles = copy(state.tiles), units = copy(state.units), cities = copy(state.cities), log = copy(state.log), availableProduction = {"Warrior", "Settler", "Scout", "Granary", "Workshop", "Library"}, availableResearch = research, objectives = {"Found your first city with the settler.", "Capture the rival capital to win.", "Round limit: 40; score cities, population, units, and technologies."}}
end
function Game.serialize(state: State): any
    local saved = {format = "unciv-luau-original", version = 1, state = state}
    assert(Save.valid(saved), "cannot serialize an invalid simulation state")
    return copy(saved)
end
function Game.restore(saved: any): (State?, string?)
    if not Save.valid(saved) then return nil, "Unsupported or corrupt simulation save." end
    return copy(saved.state) :: State, nil
end
function Game.getRules() return Rules end
return table.freeze(Game)
