--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Provenance-Kind: original
-- Original indexed bounded map, Dijkstra traversal and fog projection. Uses attributed HexMath.
local HexMath = require("../map/HexMath")
local SphereTopology = require("../map/SphereTopology")
local WorldGeneration = require("../map/WorldGeneration")
local Rules = require("./BaseRules")
export type Tile = {id: number, x: number?, y: number?, terrain: string, resource: string?, ownerId: number?, improvement: string?, road: boolean?}
export type Map = {radius: number, tiles: {Tile}, index: {[string]: number}, neighbors: {{number}}, mapShape: string?, frequency: number?, startIds: {number}?, distanceRows: {[number]: {number}}?, distanceOrder: {number}?}
export type Cost = (number, number) -> number?
local WorldMap = {}
local offsets = {{1,0},{0,1},{1,1},{-1,0},{0,-1},{-1,-1}}
local function integer(value: number): boolean return value == value and math.abs(value) <= 9007199254740991 and value % 1 == 0 end
local function key(x: number, y: number): string return tostring(x) .. ":" .. tostring(y) end
function WorldMap.fromTiles(tiles: {Tile}, radius: number): Map
    assert(integer(radius) and radius >= Rules.minRadius and radius <= Rules.maxRadius, "radius must be 3..40")
    assert(#tiles == 1+3*radius*(radius+1), "incomplete map")
    local index: {[string]: number}, neighbors: {{number}} = {}, {}
    for id, tile in tiles do
        assert(tile.id == id and tile.x ~= nil and tile.y ~= nil and integer(tile.x) and integer(tile.y) and HexMath.getDistanceXY(0,0,tile.x,tile.y) <= radius, "invalid map tile")
        local coordinate = key(tile.x :: number,tile.y :: number)
        assert(index[coordinate] == nil and Rules.terrains[tile.terrain] ~= nil, "duplicate coordinate or invalid terrain")
        index[coordinate]=id
    end
    for id, tile in tiles do
        local adjacent: {number} = {}
        for _, offset in offsets do local other=index[key((tile.x :: number)+offset[1],(tile.y :: number)+offset[2])]; if other then table.insert(adjacent,other) end end
        table.sort(adjacent); neighbors[id]=adjacent
    end
    return {radius=radius,tiles=tiles,index=index,neighbors=neighbors}
end
function WorldMap.generate(seed: number, radius: number): Map
    assert(integer(seed), "seed must be a finite safe integer")
    assert(integer(radius) and radius >= Rules.minRadius and radius <= Rules.maxRadius, "radius must be 3..40")
    local tiles: {Tile} = {}
    local centers: {WorldGeneration.Center} = {}
    for x=-radius,radius do for y=-radius,radius do
        if HexMath.getDistanceXY(0,0,x,y) > radius then continue end
        local id=#tiles+1
        tiles[id]={id=id,x=x,y=y,terrain="Plains"}
        centers[id]={x=(x-y/2)/radius,y=0,z=(math.sqrt(3)/2*y)/radius}
    end end
    local map=WorldMap.fromTiles(tiles,radius)
    local generated=WorldGeneration.generate(seed,centers,map.neighbors,"Hex")
    for id,tile in tiles do tile.terrain=generated.tiles[id].terrain; tile.resource=generated.tiles[id].resource end
    map.startIds=table.clone(generated.starts)
    return map
end
function WorldMap.tileId(map: Map, x: number, y: number): number? return map.index[key(x,y)] end
-- Exact adjacency distances. At most eight full BFS rows are retained per live map.
local function graphDistances(map: Map, source: number, limit: number?, goal: number?): {number}
    local distances: {number} = {}; distances[source]=0
    local queue={source}; local head=1
    while head<=#queue do
        local current=queue[head]; head+=1
        if current==goal then break end
        if limit and distances[current]>=limit then continue end
        for _,other in map.neighbors[current] do if distances[other]==nil then distances[other]=distances[current]+1; table.insert(queue,other) end end
    end
    return distances
end
function WorldMap.distance(map: Map, first: number, second: number): number
    local a,b=map.tiles[first],map.tiles[second]; assert(a and b,"unknown tile")
    if map.mapShape~="Sphere" then return HexMath.getDistanceXY(a.x :: number,a.y :: number,b.x :: number,b.y :: number) end
    map.distanceRows=map.distanceRows or {}; map.distanceOrder=map.distanceOrder or {}
    local rows=map.distanceRows :: {[number]: {number}}; local order=map.distanceOrder :: {number}
    if not rows[second] then
        if #order==8 then rows[table.remove(order,1) :: number]=nil end
        rows[second]=graphDistances(map,second,nil,nil); table.insert(order,second)
    end
    return rows[second][first]
end
function WorldMap.inRange(map: Map, first: number, second: number, range: number): boolean
    assert(map.tiles[first] and map.tiles[second] and range%1==0 and range>=0,"invalid range query")
    if map.mapShape~="Sphere" then return WorldMap.distance(map,first,second)<=range end
    return graphDistances(map,first,range,second)[second]~=nil
end
function WorldMap.range(map: Map, center: number, range: number): {number}
    assert(map.tiles[center] and range%1==0 and range>=0,"invalid range query")
    local ids: {number}={}; for id in graphDistances(map,center,range,nil) do table.insert(ids,id) end; table.sort(ids); return ids
end
function WorldMap.cappedDistance(map: Map, first: number, second: number, limit: number): number
    assert(map.tiles[first] and map.tiles[second] and limit%1==0 and limit>=0,"invalid capped distance")
    if map.mapShape~="Sphere" then return math.min(limit,WorldMap.distance(map,first,second)) end
    local distances=graphDistances(map,first,limit,second)
    return distances[second] or limit
end
function WorldMap.fromSphereTiles(tiles: {Tile}, frequency: number): Map
    local descriptor=SphereTopology.generate(frequency)
    assert(#tiles==#descriptor.cells,"incomplete sphere")
    local neighbors: {{number}}={}
    for id,tile in tiles do
        assert(tile.id==id and tile.x==nil and tile.y==nil and Rules.terrains[tile.terrain],"invalid sphere tile")
        neighbors[id]=descriptor.cells[id].neighbors
    end
    return {radius=0,tiles=tiles,index={},neighbors=neighbors,mapShape="Sphere",frequency=frequency}
end
function WorldMap.sphereStarts(frequency: number): {number}
    local cells=SphereTopology.generate(frequency).cells; local first=cells[1].center
    local opposite,best=1,math.huge
    for id,cell in cells do local p=cell.center; local d=first.x*p.x+first.y*p.y+first.z*p.z; if d<best then opposite,best=id,d end end
    return {1,opposite}
end
function WorldMap.generateSphere(seed: number, frequency: number): Map
    assert(integer(seed),"seed must be a finite safe integer")
    local cells=SphereTopology.generate(frequency).cells
    local tiles: {Tile}={}
    local centers: {WorldGeneration.Center}={}
    for id,cell in cells do
        tiles[id]={id=id,terrain="Plains"}
        local p=cell.center; centers[id]={x=p.x,y=p.y,z=p.z}
    end
    local map=WorldMap.fromSphereTiles(tiles,frequency)
    local generated=WorldGeneration.generate(seed,centers,map.neighbors,"Sphere")
    for id,tile in tiles do tile.terrain=generated.tiles[id].terrain; tile.resource=generated.tiles[id].resource end
    map.startIds=table.clone(generated.starts)
    return map
end
function WorldMap.movementCost(tile: Tile): number?
    local terrain=Rules.terrains[tile.terrain]
    if not terrain or not terrain.passable then return nil end
    return if tile.road then Rules.roadMovement else terrain.movement
end
-- Heap order matches the former scan: minimum cost first, then ascending tile ID.
type Entry = {id: number, cost: number}
local function before(a: Entry, b: Entry): boolean return a.cost<b.cost or (a.cost==b.cost and a.id<b.id) end
local function push(heap: {Entry}, entry: Entry)
    local index=#heap+1
    while index>1 do
        local parent=math.floor(index/2)
        if not before(entry,heap[parent]) then break end
        heap[index]=heap[parent]; index=parent
    end
    heap[index]=entry
end
local function pop(heap: {Entry}): Entry
    local first=heap[1]
    local last=table.remove(heap) :: Entry
    if #heap==0 then return first end
    local index=1
    while index*2<=#heap do
        local child=index*2
        if child<#heap and before(heap[child+1],heap[child]) then child+=1 end
        if not before(heap[child],last) then break end
        heap[index]=heap[child]; index=child
    end
    heap[index]=last
    return first
end
local function search(map: Map, start: number, budget: number, cost: Cost?, goal: number?): ({[number]: number}, {[number]: number})
    assert(map.tiles[start] ~= nil and budget >= 0 and budget == budget,"invalid search")
    local distances: {[number]: number}, previous: {[number]: number}, visited: {[number]: boolean} = {[start]=0},{},{}
    local heap: {Entry}={{id=start,cost=0}}
    local getCost: Cost = cost or function(_from: number, to: number): number? return WorldMap.movementCost(map.tiles[to]) end
    while #heap>0 do
        local entry=pop(heap)
        local current,best=entry.id,entry.cost
        if visited[current] or distances[current]~=best then continue end
        if best>budget then break end
        visited[current]=true
        if current==goal then break end
        for _, nextId in map.neighbors[current] do
            if visited[nextId] then continue end
            local step=getCost(current,nextId)
            if step == nil then continue end
            assert(step==step and step>0 and step<math.huge,"path cost must be finite and positive")
            local candidate=best+step
            if candidate<=budget and (distances[nextId]==nil or candidate<distances[nextId]) then
                distances[nextId]=candidate; previous[nextId]=current; push(heap,{id=nextId,cost=candidate})
            end
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
    local seen: {[number]: boolean}={}
    for _,center in centers do for _,id in WorldMap.range(map,center,range) do seen[id]=true end end
    local result: {number}={}; for id in seen do table.insert(result,id) end; table.sort(result); return result
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


