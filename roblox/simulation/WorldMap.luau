--!strict
-- Generated module-only Roblox form. Source: src/simulation/WorldMap.luau
-- Source SHA-256: 51645a6c3235e5381a0efb6be12a25f7bbf300ac99aa2714afce9581a59cbaf9
-- Reproduce with tools/roblox-export.mjs; preserve MPL notices below.
-- Covered source: https://github.com/RoryODonovan/unciv-luau
-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- Obtain a copy at https://mozilla.org/MPL/2.0/.
--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Provenance-Kind: original
-- Original indexed bounded map, Dijkstra traversal and fog projection. Uses attributed HexMath.
local HexMath = require(script.Parent.Parent.map.HexMath)
local Rules = require(script.Parent.BaseRules)
export type Tile = {id: number, x: number, y: number, terrain: string, resource: string?, ownerId: number?, improvement: string?, road: boolean?}
export type Map = {radius: number, tiles: {Tile}, index: {[string]: number}, neighbors: {{number}}}
export type Cost = (number, number) -> number?
local WorldMap = {}
local offsets = {{1,0},{0,1},{1,1},{-1,0},{0,-1},{-1,-1}}
local function integer(value: number): boolean return value == value and math.abs(value) <= 9007199254740991 and value % 1 == 0 end
local function key(x: number, y: number): string return tostring(x) .. ":" .. tostring(y) end
function WorldMap.fromTiles(tiles: {Tile}, radius: number): Map
    assert(integer(radius) and radius >= Rules.minRadius and radius <= Rules.maxRadius, "radius must be 3..7")
    assert(#tiles == 1+3*radius*(radius+1), "incomplete map")
    local index: {[string]: number}, neighbors: {{number}} = {}, {}
    for id, tile in tiles do
        assert(tile.id == id and integer(tile.x) and integer(tile.y) and HexMath.getDistanceXY(0,0,tile.x,tile.y) <= radius, "invalid map tile")
        local coordinate = key(tile.x,tile.y)
        assert(index[coordinate] == nil and Rules.terrains[tile.terrain] ~= nil, "duplicate coordinate or invalid terrain")
        index[coordinate]=id
    end
    for id, tile in tiles do
        local adjacent: {number} = {}
        for _, offset in offsets do local other=index[key(tile.x+offset[1],tile.y+offset[2])]; if other then table.insert(adjacent,other) end end
        table.sort(adjacent); neighbors[id]=adjacent
    end
    return {radius=radius,tiles=tiles,index=index,neighbors=neighbors}
end
function WorldMap.generate(seed: number, radius: number): Map
    assert(integer(seed), "seed must be a finite safe integer")
    assert(integer(radius) and radius >= Rules.minRadius and radius <= Rules.maxRadius, "radius must be 3..7")
    local random = seed % 2147483647
    if random == 0 then random=1 end
    local function roll(limit: number): number random=(random*48271)%2147483647; return random%limit end
    local tiles: {Tile} = {}
    for x=-radius,radius do for y=-radius,radius do
        if HexMath.getDistanceXY(0,0,x,y) > radius then continue end
        local n=roll(100)
        local terrain: string=if n<35 then "Plains" elseif n<55 then "Grassland" elseif n<72 then "Hills" elseif n<86 then "Forest" elseif n<92 then "Desert" elseif n<97 then "Water" else "Mountain"
        -- A central spine joins the default opposite starts, preserving a playable route.
        if x==y or y==0 then terrain="Plains" end
        local resource: string? = nil
        if roll(4)==0 then
            if terrain=="Hills" then resource=if roll(2)==0 then "Iron" else "Gold"
            elseif terrain=="Forest" then resource=if roll(2)==0 then "Deer" else "Spices"
            elseif terrain=="Plains" or terrain=="Grassland" then resource=if roll(2)==0 then "Wheat" else "Horses"
            elseif terrain=="Desert" then resource="Gold" end
        end
        table.insert(tiles,{id=#tiles+1,x=x,y=y,terrain=terrain,resource=resource})
    end end
    return WorldMap.fromTiles(tiles,radius)
end
function WorldMap.tileId(map: Map, x: number, y: number): number? return map.index[key(x,y)] end
function WorldMap.distance(map: Map, first: number, second: number): number
    local a,b=map.tiles[first],map.tiles[second]
    assert(a and b,"unknown tile")
    return HexMath.getDistanceXY(a.x,a.y,b.x,b.y)
end
function WorldMap.movementCost(tile: Tile): number?
    local terrain=Rules.terrains[tile.terrain]
    if not terrain or not terrain.passable then return nil end
    return if tile.road then Rules.roadMovement else terrain.movement
end
local function search(map: Map, start: number, budget: number, cost: Cost?, goal: number?): ({[number]: number}, {[number]: number})
    assert(map.tiles[start] ~= nil and budget >= 0 and budget == budget,"invalid search")
    local distances: {[number]: number}, previous: {[number]: number}, visited: {[number]: boolean} = {[start]=0},{},{}
    local getCost: Cost = cost or function(_from: number, to: number): number? return WorldMap.movementCost(map.tiles[to]) end
    for _=1,#map.tiles do
        local current: number? = nil
        local best=math.huge
        for id=1,#map.tiles do
            local d=distances[id]
            if d ~= nil and not visited[id] and d<best then current=id; best=d end
        end
        if not current or best>budget then break end
        visited[current]=true
        if current==goal then break end
        for _, nextId in map.neighbors[current] do
            if visited[nextId] then continue end
            local step=getCost(current,nextId)
            if step == nil then continue end
            assert(step==step and step>0 and step<math.huge,"path cost must be finite and positive")
            local candidate=best+step
            if candidate<=budget and (distances[nextId]==nil or candidate<distances[nextId]) then distances[nextId]=candidate; previous[nextId]=current end
        end
    end
    return distances,previous
end
function WorldMap.reachable(map: Map, start: number, budget: number, cost: Cost?): {[number]: number}
    local distances=search(map,start,budget,cost,nil)
    return distances
end
function WorldMap.shortestPath(map: Map, start: number, goal: number, cost: Cost?): ({number}?, number?)
    assert(map.tiles[goal] ~= nil,"unknown goal")
    local distances,previous=search(map,start,math.huge,cost,goal)
    if distances[goal]==nil then return nil,nil end
    local path={goal}
    local current=goal
    while current ~= start do current=previous[current]; table.insert(path,1,current) end
    return path,distances[goal]
end
function WorldMap.visibility(map: Map, centers: {number}, range: number): {number}
    assert(integer(range) and range>=0 and range<=Rules.maxRadius*2,"invalid vision range")
    local seen: {[number]: boolean} = {}
    for _, center in centers do
        assert(map.tiles[center] ~= nil,"unknown center")
        for id=1,#map.tiles do if WorldMap.distance(map,center,id)<=range then seen[id]=true end end
    end
    local result: {number} = {}
    for id=1,#map.tiles do if seen[id] then table.insert(result,id) end end
    return result
end
function WorldMap.projectTiles(map: Map, discovered: {number}, visible: {number}): {any}
    local known: {[number]: boolean}, shown: {[number]: boolean} = {},{}
    for _, id in discovered do assert(map.tiles[id] ~= nil,"unknown discovered tile"); known[id]=true end
    for _, id in visible do assert(map.tiles[id] ~= nil,"unknown visible tile"); shown[id]=true; known[id]=true end
    local result: {any} = {}
    for _, tile in map.tiles do
        local row: any={id=tile.id,x=tile.x,y=tile.y,discovered=known[tile.id]==true,visible=shown[tile.id]==true}
        if known[tile.id] then row.terrain=tile.terrain; row.resource=tile.resource end
        if shown[tile.id] then row.ownerId=tile.ownerId; row.improvement=tile.improvement; row.road=tile.road end
        table.insert(result,row)
    end
    return result
end
return table.freeze(WorldMap)
