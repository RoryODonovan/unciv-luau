--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Preset expectations from core/src/com/unciv/logic/map/MapSize.kt at
-- 42939c6a2cf31aa76f44ffc033015ad12fece9f5; other scenarios are original.
local Sizes=require("../../src/map/MapSizes")
local Map=require("../../src/simulation/WorldMap")
local Game=require("../../src/simulation/BaseGame")
local Save=require("../../src/simulation/BaseSave")
local Rules=require("../../src/simulation/BaseRules")
local function copy(value: any): any
    if type(value)~="table" then return value end
    local result={}; for key,child in value do result[key]=copy(child) end; return result
end
local function equal(a: any,b: any): boolean
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in a do if not equal(v,b[k]) then return false end end
    for k in b do if a[k]==nil then return false end end
    return true
end
assert(table.isfrozen(Sizes) and table.isfrozen(Sizes.presets))
assert(Sizes.get("Unknown")==nil and Sizes.get("tiny")==nil)
local names={"Tiny","Small","Medium","Large","Huge"}
local radii={10,15,20,30,40}
local counts={331,721,1261,2791,4921}
for i,preset in Sizes.presets do
    assert(preset.name==names[i] and preset.radius==radii[i] and preset.tileCount==counts[i])
    assert(Sizes.get(names[i])==preset and table.isfrozen(preset))
    local map=Map.generate(42,preset.radius)
    assert(#map.tiles==preset.tileCount and equal(map,Map.generate(42,preset.radius)))
    for id,neighbors in map.neighbors do
        for _,other in neighbors do assert(Map.distance(map,id,other)==1 and table.find(map.neighbors[other],id)) end
    end
    local s=Game.new(42,{radius=preset.radius,humanPlayers=2})
    local loaded,err=Game.restore(Game.serialize(s))
    assert(loaded and not err and equal(s,loaded))
    local view=Game.snapshot(loaded,1)
    assert(view.radius==preset.radius and #view.tiles==preset.tileCount and view.seed==nil)
end
assert(Game.new().radius==4 and Rules.maxUnits==169 and Rules.maxCities==24)
for radius=3,7 do assert(Game.restore(Game.serialize(Game.new(42,{radius=radius})))) end
assert(not pcall(function() Game.new(1,{radius=41}) end))
assert(not pcall(function() Game.new(1,{radius=2}) end))
assert(not pcall(function() Game.new(1,{radius=10.5}) end))
-- Entire Huge topology, every tile field and both complete explored arrays exceed
-- the old 16,384-entry budget but must remain inside the new bounded trust boundary.
local full=Game.new(42,{radius=40,humanPlayers=2})
for _,tile in full.tiles do tile.terrain="Plains"; tile.resource="Wheat"; tile.ownerId=1; tile.improvement="Farm"; tile.road=true end
for _,p in full.players do p.explored={}; for id=1,#full.tiles do table.insert(p.explored,id) end end
local saved=Game.serialize(full)
assert(saved.version==1 and #saved.state.tiles==4921 and Save.valid(saved))
local roundtrip=Game.restore(saved)
assert(roundtrip and equal(full,roundtrip))
saved.state.tiles[1].terrain="Desert"; assert(full.tiles[1].terrain=="Plains" and roundtrip.tiles[1].terrain=="Plains")
local function corrupt(change: (any)->())
    local bad=Game.serialize(full); change(bad)
    assert(not Save.valid(bad) and Game.restore(bad)==nil)
end
corrupt(function(s) s.state.radius=41 end)
corrupt(function(s) s.state.radius=39 end)
corrupt(function(s) table.remove(s.state.tiles) end)
corrupt(function(s) s.state.tiles[4922]=copy(s.state.tiles[1]) end)
corrupt(function(s) s.state.tiles[4921].x=s.state.tiles[1].x; s.state.tiles[4921].y=s.state.tiles[1].y end)
corrupt(function(s) s.state.players[1].explored[4921]=4922 end)
corrupt(function(s) s.state.tiles[1].extra=true end)
corrupt(function(s) s.state.mapSize="Huge" end)
corrupt(function(s) for _=1,164 do table.insert(s.state.units,copy(s.state.units[1])) end end)
corrupt(function(s) for _=1,25 do table.insert(s.state.cities,{}) end end)
corrupt(function(s) s.state.log=s.state.tiles end)
corrupt(function(s) s.state.log[1]=s.state end)
-- Geometric visibility agrees with an independent full-map oracle, including edges
-- and duplicate centers; terrain does not block the geometric disk.
local map=Map.generate(42,40)
local center=Map.tileId(map,0,0) :: number
local edge=Map.tileId(map,40,0) :: number
for _,range in {0,1,2,5,80} do
    local expected={}
    for id=1,#map.tiles do if Map.distance(map,center,id)<=range or Map.distance(map,edge,id)<=range then table.insert(expected,id) end end
    assert(equal(expected,Map.visibility(map,{center,edge,center},range)))
end
for _,tile in map.tiles do tile.terrain="Plains" end
local first=Map.tileId(map,-39,0) :: number
local last=Map.tileId(map,39,0) :: number
local path,cost=Map.shortestPath(map,first,last)
assert(path and #path==79 and cost==78)
for i=2,#(path :: {number}) do assert(Map.distance(map,(path :: {number})[i-1],(path :: {number})[i])==1) end
assert(equal(Map.reachable(map,center,2), (function(): {[number]: number}
    local expected={}; for _,id in Map.visibility(map,{center},2) do expected[id]=Map.distance(map,center,id) end; return expected
end)()))
-- Preserve exact paths, not only costs: this independent scan oracle reproduces
-- the former ascending-ID Dijkstra settlement and predecessor tie behavior.
local function scanPath(world: Map.Map, source: number, goal: number): {number}?
    local distances: {[number]: number}={[source]=0}
    local previous: {[number]: number},visited: {[number]: boolean}={},{}
    for _=1,#world.tiles do
        local best=math.huge; local current: number?=nil
        for id=1,#world.tiles do
            if distances[id]~=nil and not visited[id] and distances[id]<best then best=distances[id]; current=id end
        end
        if not current then break end
        visited[current]=true; if current==goal then break end
        for _,target in world.neighbors[current] do
            if visited[target] then continue end
            local step=Map.movementCost(world.tiles[target])
            if step and (distances[target]==nil or best+step<distances[target]) then distances[target]=best+step; previous[target]=current end
        end
    end
    if not distances[goal] then return nil end
    local result={goal}; local current=goal
    while current~=source do current=previous[current]; table.insert(result,1,current) end
    return result
end
for seed=1,6 do
    local world=Map.generate(seed,4)
    local source=Map.tileId(world,0,0) :: number
    for target=1,#world.tiles do assert(equal(scanPath(world,source,target),Map.shortestPath(world,source,target))) end
end
-- Hidden changes cannot influence Huge snapshots or legal moves; projections detach.
local fog=Game.new(42,{radius=40,humanPlayers=2})
local view=Game.snapshot(fog,1)
local hidden: number?=nil
for _,tile in view.tiles do
    if not tile.explored then
        hidden=tile.id
        assert(tile.terrain==nil and tile.resource==nil and tile.ownerId==nil and tile.improvement==nil and tile.road==nil and tile.food==nil)
    end
end
assert(hidden)
local other=copy(fog)
other.tiles[hidden :: number].terrain="Grassland"; other.tiles[hidden :: number].resource="Wheat"; other.tiles[hidden :: number].ownerId=2; other.tiles[hidden :: number].improvement="Farm"
other.players[2].gold=900; other.players[2].science=100
for _,u in other.units do if u.ownerId==2 then u.hp=1 end end
assert(equal(view,Game.snapshot(other,1)))
view.tiles[1].visible=true; assert(equal(Game.snapshot(fog,1),Game.snapshot(other,1)))
-- Exercise actual Huge solo economy/AI rounds at the existing entity limit.
local stress=Game.new(42,{radius=40})
for _,u in stress.units do if u.ownerId==1 and u.kind=="Settler" then assert(Game.apply(stress,1,{kind="FoundCity",unitId=u.id}).ok); break end end
local occupied={}; for _,u in stress.units do occupied[u.tileId]=true end; for _,c in stress.cities do occupied[c.tileId]=true end
for _,tile in stress.tiles do
    if #stress.units==Rules.maxUnits then break end
    if occupied[tile.id] or not Map.movementCost(tile) then continue end
    table.insert(stress.units,{id=stress.nextUnit,ownerId=1,kind="Warrior",tileId=tile.id,hp=100,moves=2,fortified=false,level=0}); stress.nextUnit+=1
end
stress.players[1].gold=100000
assert(#stress.units==169 and Save.valid(Game.serialize(stress)))
local stressView=Game.snapshot(stress,1)
assert(#stressView.units>=167 and #stressView.tiles==4921)
for _,u in stress.units do if u.ownerId==1 then assert(stressView.legalMoves[tostring(u.id)]) end end
for _=1,20 do assert(Game.apply(stress,1,{kind="EndTurn"}).ok) end
assert(stress.turn==21 and stress.revision==21 and #stress.units<=169 and #stress.cities<=24)
local loaded=Game.restore(Game.serialize(stress)); assert(loaded and equal(stress,loaded))
print("map presets, Huge saves/fog/path/turn and 169-unit stress passed")
