--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original foundation tests: independent path-cost oracle and fog non-disclosure checks.
local Rules=require("../../src/simulation/BaseRules")
local WorldMap=require("../../src/simulation/WorldMap")
local function equal(a: any,b: any): boolean
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in a do if not equal(v,b[k]) then return false end end
    for k in b do if a[k]==nil then return false end end
    return true
end
local function frozen(value: any)
    if type(value)~="table" then return end
    assert(table.isfrozen(value))
    for _,child in value do frozen(child) end
end
frozen(Rules)
assert(Rules.units.Worker and Rules.units.Archer and Rules.units.Swordsman and #Rules.technologyOrder>=12)
for _,id in Rules.technologyOrder do
    for _,prerequisite in Rules.technologies[id].prerequisites do assert((table.find(Rules.technologyOrder,prerequisite) :: number) < (table.find(Rules.technologyOrder,id) :: number)) end
end
for radius=3,7 do
    local map=WorldMap.generate(132,radius)
    assert(#map.tiles==1+3*radius*(radius+1) and equal(map,WorldMap.generate(132,radius)))
    assert(not equal(map.tiles,WorldMap.generate(133,radius).tiles))
    for id,adjacent in map.neighbors do
        assert(#adjacent<=6)
        for _,other in adjacent do assert(WorldMap.distance(map,id,other)==1 and table.find(map.neighbors[other],id)) end
    end
end
local map=WorldMap.generate(33,3)
for _,tile in map.tiles do tile.terrain="Plains" end
local start=WorldMap.tileId(map,-2,0) :: number
local goal=WorldMap.tileId(map,2,0) :: number
local expensive=WorldMap.tileId(map,0,0) :: number
map.tiles[expensive].terrain="Hills"
local weighted: WorldMap.Cost=function(_from, to) return if to==expensive then 100 else 1 end
local route,cost=WorldMap.shortestPath(map,start,goal,weighted)
assert(route and cost==5 and #route==6 and table.find(route,expensive)==nil,"must avoid expensive direct corridor")
local sum=0
for i=2,#(route :: {number}) do assert(WorldMap.distance(map,(route :: {number})[i-1],(route :: {number})[i])==1); sum+=weighted((route :: {number})[i-1],(route :: {number})[i]) :: number end
assert(sum==cost)
local blocked: WorldMap.Cost=function(_tile,_from) return nil end
assert(WorldMap.shortestPath(map,start,goal,blocked)==nil)
assert(equal(WorldMap.reachable(map,start,5,blocked),{[start]=0}))
assert(not pcall(function() WorldMap.shortestPath(map,start,goal,function(_tile,_from) return 0 end) end))
-- Bellman-Ford is an independent oracle for the weighted Dijkstra results.
for seed=1,6 do
    local world=WorldMap.generate(seed,4)
    local source=WorldMap.tileId(world,0,0) :: number
    local distance: {[number]: number}={[source]=0}
    for _=1,#world.tiles-1 do
        for id,adjacent in world.neighbors do
            if distance[id]==nil then continue end
            for _,other in adjacent do
                local step=WorldMap.movementCost(world.tiles[other])
                if step and (distance[other]==nil or distance[id]+step<distance[other]) then distance[other]=distance[id]+step end
            end
        end
    end
    assert(equal(distance,WorldMap.reachable(world,source,math.huge)))
    for target=1,#world.tiles do
        local path,total=WorldMap.shortestPath(world,source,target)
        assert(total==distance[target])
        if path then assert(path[1]==source and path[#path]==target) end
    end
end
local known,shown=map.tiles[start],map.tiles[goal]
known.ownerId=2; known.improvement="Farm"; known.road=true; known.resource="Wheat"
shown.ownerId=1; shown.improvement="Mine"; shown.resource="Iron"
local view=WorldMap.projectTiles(map,{start},{goal})
assert(view[start].terrain==known.terrain and view[start].resource=="Wheat" and view[start].ownerId==nil and view[start].improvement==nil and view[start].road==nil)
assert(view[goal].ownerId==1 and view[goal].improvement=="Mine" and view[goal].visible)
for key in view[expensive] do assert(key=="id" or key=="x" or key=="y" or key=="discovered" or key=="visible") end
assert(view[expensive].terrain==nil and view[expensive].resource==nil)
view[goal].ownerId=2; assert(shown.ownerId==1)
local vision=WorldMap.visibility(map,{expensive},1)
assert(#vision==7 and equal(vision,WorldMap.visibility(map,{expensive,expensive},1)))
assert(not pcall(function() WorldMap.generate(1,41) end))
assert(not pcall(function() WorldMap.generate(0/0,3) end))
print("base map and rule foundations passed")



