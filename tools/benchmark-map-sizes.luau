--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original CLI benchmark; times detached save tables, not host JSON/network/storage.
local Game=require("../src/simulation/BaseGame")
local Map=require("../src/simulation/WorldMap")
local function measure(label: string, count: number, action: ()->())
    local started=os.clock()
    for _=1,count do action() end
    print(string.format("%s: %.3f ms/op (%d samples)",label,(os.clock()-started)*1000/count,count))
end
for _,radius in {7,40} do
    print("radius "..radius)
    measure("generation",10,function() Map.generate(42,radius) end)
    local map=Map.generate(42,radius)
    local start=Map.tileId(map,-radius+1,0) :: number
    local goal=Map.tileId(map,radius-1,0) :: number
    measure("opposite-start path",3,function() local path=Map.shortestPath(map,start,goal); assert(path) end)
    local state=Game.new(42,{radius=radius})
    for _,u in state.units do if u.ownerId==1 and u.kind=="Settler" then assert(Game.apply(state,1,{kind="FoundCity",unitId=u.id}).ok); break end end
    measure("snapshot",20,function() Game.snapshot(state,1) end)
    measure("save serialize",5,function() Game.serialize(state) end)
    local saved=Game.serialize(state)
    measure("save restore",5,function() assert(Game.restore(saved)) end)
    measure("solo round including AI",20,function() assert(Game.apply(state,1,{kind="EndTurn"}).ok) end)
    assert(Game.serialize(state))
end

local stress=Game.new(42,{radius=40})
for _,u in stress.units do if u.ownerId==1 and u.kind=="Settler" then assert(Game.apply(stress,1,{kind="FoundCity",unitId=u.id}).ok); break end end
local occupied={}; for _,u in stress.units do occupied[u.tileId]=true end; for _,c in stress.cities do occupied[c.tileId]=true end
for _,tile in stress.tiles do
    if #stress.units>=169 then break end
    if occupied[tile.id] or not Map.movementCost(tile) then continue end
    table.insert(stress.units,{id=stress.nextUnit,ownerId=1,kind="Warrior",tileId=tile.id,hp=100,moves=2,fortified=false,level=0})
    stress.nextUnit+=1
end
stress.players[1].gold=100000
assert(#stress.units==169 and Game.serialize(stress))
print("radius 40, 169 units")
measure("snapshot",20,function() Game.snapshot(stress,1) end)
measure("solo round including AI",20,function() assert(Game.apply(stress,1,{kind="EndTurn"}).ok) end)
assert(Game.serialize(stress))
measure("save serialize",5,function() Game.serialize(stress) end)
local stressSave=Game.serialize(stress)
measure("save restore",5,function() assert(Game.restore(stressSave)) end)
