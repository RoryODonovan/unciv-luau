--!strict
-- Generated module-only Roblox form. Source: src/simulation/Save.luau
-- Source SHA-256: 61481f6189a435244c795b8b9e9e4549face9680ecb3d80620ba7dfa78e11c41
-- Reproduce with tools/roblox-export.mjs; preserve MPL notices below.
-- Covered source: https://github.com/RoryODonovan/unciv-luau
-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- Obtain a copy at https://mozilla.org/MPL/2.0/.
--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Provenance-Kind: original
-- Original bounded schema validator for the synthetic simulation. No host services.
local Rules = require(script.Parent.Rules)
local HexMath = require(script.Parent.Parent.map.HexMath)
local Save = {}
local function integer(value: any, low: number, high: number): boolean
    return type(value) == "number" and value == value and value >= low and value <= high and value % 1 == 0
end
local function text(value: any, limit: number): boolean
    return type(value) == "string" and #value <= limit and #value > 0
end
local function object(value: any, keys: string): boolean
    if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
    local allowed: {[string]: boolean} = {}
    for key in string.gmatch(keys, "%S+") do allowed[key] = true end
    for key in value do
        if type(key) ~= "string" or allowed[key] ~= true then return false end
    end
    return true
end
local function array(value: any, limit: number): boolean
    if type(value) ~= "table" or getmetatable(value) ~= nil or #value > limit then return false end
    local count = 0
    for key in value do if not integer(key, 1, #value) then return false end; count += 1 end
    return count == #value
end
local function owner(value: any): boolean return value == 1 or value == 2 end
local function id(value: any): boolean return integer(value, 1, 1000000) end
local function uniqueStrings(values: any, known: any, max: number): boolean
    if not array(values, max) then return false end
    local seen = {}
    for _, value in values do
        if type(value) ~= "string" or not known[value] or seen[value] then return false end
        seen[value] = true
    end
    return true
end
-- Validate the complete tree before any schema access or recursive copying. Iterative
-- traversal gives fixed depth/entry budgets and rejects cycles/shared tables, metatables,
-- non-data values and non-finite numbers even when hidden in an unexpected field.
-- The version-1 schema needs at most six levels and fewer than 4,000 entries at
-- maximum map/entity/event capacity. These limits leave bounded headroom.
local function plainTree(root: any): boolean
    if type(root) ~= "table" then return false end
    local pending: {{value: any, depth: number}} = {{value = root, depth = 1}}
    local seen: {[any]: boolean} = {[root] = true}
    local entries = 0
    while #pending > 0 do
        local node = table.remove(pending) :: {value: any, depth: number}
        local value = node.value
        if getmetatable(value) ~= nil or node.depth > 8 then return false end
        for key, child in value do
            entries += 1
            if entries > 8192 then return false end
            if type(key) == "string" then
                if #key > 256 then return false end
            elseif not integer(key, 1, 8192) then return false end
            local kind = type(child)
            if kind == "table" then
                if seen[child] then return false end
                seen[child] = true
                table.insert(pending, {value = child, depth = node.depth + 1})
            elseif kind == "number" then
                if child ~= child or math.abs(child) > 9007199254740991 then return false end
            elseif kind == "string" then
                if #child > 1024 then return false end
            elseif kind ~= "boolean" then return false end
        end
    end
    return true
end
function Save.valid(saved: any): boolean
    if not plainTree(saved) then return false end
    if not object(saved, "format version state") or saved.format ~= "unciv-luau-original" or saved.version ~= 1 then return false end
    local s = saved.state
    if not object(s, "seed difficulty radius forest events nextEvent turn revision phase winner reason tiles units cities players log nextUnit nextCity aiCapital") then return false end
    if not integer(s.seed, -9007199254740991, 9007199254740991) or not integer(s.radius, 3, 5) or type(s.forest) ~= "boolean" then return false end
    if s.difficulty ~= "Easy" and s.difficulty ~= "Normal" and s.difficulty ~= "Hard" then return false end
    if not integer(s.turn, 1, Rules.maxTurns) or not integer(s.revision, 0, 1000000000) or not id(s.nextUnit) or not id(s.nextCity) or not id(s.aiCapital) or not integer(s.nextEvent, 1, 1000000000) then return false end
    if s.phase == "Playing" then if s.winner ~= nil or s.reason ~= nil then return false end
    elseif s.phase == "Finished" then if not owner(s.winner) or not text(s.reason, 256) then return false end
    else return false end
    if not array(s.tiles, 91) or #s.tiles ~= 1 + 3 * s.radius * (s.radius + 1) or not array(s.units, #s.tiles) or not array(s.cities, #s.tiles) or not array(s.players, 2) or #s.players ~= 2 then return false end
    local tiles, coordinates = {}, {}
    for index, tile in s.tiles do
        if not object(tile, "id x y terrain ownerId food production") or tile.id ~= index or not integer(tile.x, -s.radius, s.radius) or not integer(tile.y, -s.radius, s.radius) or HexMath.getDistanceXY(0, 0, tile.x, tile.y) > s.radius then return false end
        if tile.ownerId ~= nil and not owner(tile.ownerId) then return false end
        if type(tile.terrain) ~= "string" then return false end
        local yields = (Rules.terrainYields :: any)[tile.terrain]
        if not yields or tile.food ~= yields.food or tile.production ~= yields.production or (tile.terrain == "Forest" and not s.forest) then return false end
        local key = tostring(tile.x) .. ":" .. tostring(tile.y)
        if coordinates[key] then return false end; coordinates[key] = true; tiles[tile.id] = tile
    end
    local units, occupancy = {}, {}
    for _, unit in s.units do
        if not object(unit, "id ownerId kind tileId hp moves fortified level") or not id(unit.id) or unit.id >= s.nextUnit or units[unit.id] or not owner(unit.ownerId) or not id(unit.tileId) or not tiles[unit.tileId] or occupancy[unit.tileId] then return false end
        if type(unit.kind) ~= "string" then return false end
        local stats = (Rules.unitStats :: any)[unit.kind]
        if not stats or not integer(unit.hp, 1, stats.hp) or not integer(unit.moves, 0, stats.moves) or type(unit.fortified) ~= "boolean" or not integer(unit.level, 0, 1) then return false end
        if unit.kind ~= "Warrior" and (unit.fortified or unit.level ~= 0) then return false end
        units[unit.id] = true; occupancy[unit.tileId] = unit
    end
    local buildings = {Granary = true, Workshop = true, Library = true}
    local cities, cityTiles = {}, {}
    for _, city in s.cities do
        if not object(city, "id ownerId tileId name population food production queue hp buildings") or not id(city.id) or city.id >= s.nextCity or cities[city.id] or not owner(city.ownerId) or not id(city.tileId) or not tiles[city.tileId] or cityTiles[city.tileId] then return false end
        if not text(city.name, 80) or not integer(city.population, 1, 1000) or not integer(city.food, 0, 1000000) or not integer(city.production, 0, 1000000) or not integer(city.hp, 0, 100) or type(city.queue) ~= "string" or (Rules.productionCosts :: any)[city.queue] == nil or not uniqueStrings(city.buildings, buildings, 3) then return false end
        if table.find(city.buildings, city.queue) or tiles[city.tileId].ownerId ~= city.ownerId or (occupancy[city.tileId] and occupancy[city.tileId].ownerId ~= city.ownerId) then return false end
        cities[city.id] = true; cityTiles[city.tileId] = true
    end
    if not cities[s.aiCapital] then return false end
    local technologies: {[string]: any} = {}
    for _, tech in Rules.technologies do technologies[tech.id] = tech end
    for _, player in s.players do
        if not object(player, "gold science technologies research") or not integer(player.gold, 0, 1000000000) or not integer(player.science, 0, 1000000000) or not uniqueStrings(player.technologies, technologies, #Rules.technologies) then return false end
        for _, techId in player.technologies do for _, prereq in technologies[techId].prerequisites do if not table.find(player.technologies, prereq) then return false end end end
        if player.research ~= nil then
            local r = player.research
            if not object(r, "id progress cost") or type(r.id) ~= "string" or not technologies[r.id] or table.find(player.technologies, r.id) or r.cost ~= technologies[r.id].cost or not integer(r.progress, 0, r.cost - 1) then return false end
            for _, prereq in technologies[r.id].prerequisites do if not table.find(player.technologies, prereq) then return false end end
        end
    end
    for _, unit in s.units do if unit.level > 0 and not table.find(s.players[unit.ownerId].technologies, "BronzeWorking") then return false end end
    if not array(s.log, 16) or not array(s.events, 32) then return false end
    for _, message in s.log do if not text(message, 256) then return false end end
    local kinds = {Move=true, Attack=true, FoundCity=true, Production=true, Research=true, Growth=true, Victory=true, Defeat=true, Purchase=true, Upgrade=true}
    local previous = 0
    for _, e in s.events do
        if not object(e, "id kind message tileId unitId ownerId amount") or not integer(e.id, previous + 1, s.nextEvent - 1) or type(e.kind) ~= "string" or not (kinds :: any)[e.kind] or not text(e.message, 256) then return false end
        if e.tileId ~= nil and (not id(e.tileId) or not tiles[e.tileId]) then return false end
        if e.unitId ~= nil and (not id(e.unitId) or e.unitId >= s.nextUnit) then return false end
        if e.ownerId ~= nil and not owner(e.ownerId) then return false end
        if e.amount ~= nil and not integer(e.amount, 0, 1000000) then return false end
        previous = e.id
    end
    if #s.events == 0 then
        if s.nextEvent ~= 1 then return false end
    elseif s.events[1].id ~= s.nextEvent - #s.events or previous ~= s.nextEvent - 1 then return false end
    if s.phase == "Playing" then
        local survives = false
        for _, city in s.cities do
            if city.ownerId == 1 then survives = true end
            if city.id == s.aiCapital and city.ownerId ~= 2 then return false end
        end
        for _, unit in s.units do if unit.ownerId == 1 and unit.kind == "Settler" then survives = true end end
        if not survives then return false end
    end
    return true
end
return table.freeze(Save)
