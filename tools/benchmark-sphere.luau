--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original CLI measurements; no Roblox rendering/mobile frame-rate claim.
local Game=require("../src/simulation/BaseGame")
local Map=require("../src/simulation/WorldMap")
local Sphere=require("../src/map/SphereTopology")
local function measure(label: string,count: number,action: ()->())
    local started=os.clock(); for _=1,count do action() end
    print(string.format("%s %.3f ms/op (%d samples)",label,(os.clock()-started)*1000/count,count))
end
local heapBefore=gcinfo()
measure("Huge cold topology",1,function() assert(#Sphere.generate(22).cells==4842) end)
print(string.format("Huge topology observed heap delta %.1f KiB (GC-dependent)",gcinfo()-heapBefore))
local descriptor=Sphere.generate(22)
local degreeSum=0; for _,cell in descriptor.cells do degreeSum+=#cell.neighbors end
print(string.format("Huge logical storage %d cells, %d shared corners, %d neighbor IDs, %d polygon corner references",#descriptor.cells,20*22*22,degreeSum,degreeSum))
measure("Huge warm map generation",10,function() Map.generateSphere(42,22) end)
local s: any=Game.new(42,{mapShape="Sphere",frequency=22})
for _,u in s.units do if u.ownerId==1 and u.kind=="Settler" then assert(Game.apply(s,1,{kind="FoundCity",unitId=u.id}).ok); break end end
measure("Huge actor snapshot",20,function() Game.snapshot(s,1) end)
measure("Huge detached save",5,function() Game.serialize(s) end)
local saved=Game.serialize(s)
measure("Huge restore",5,function() assert(Game.restore(saved)) end)
measure("Huge solo round including AI",20,function() if s.phase=="Playing" then assert(Game.apply(s,1,{kind="EndTurn"}).ok) end end)
local stress: any=Game.new(42,{humanPlayers=2,mapShape="Sphere",frequency=22})
local occupied={}; for _,u in stress.units do occupied[u.tileId]=true end
for _,tile in stress.tiles do
    if #stress.units>=169 then break end
    if occupied[tile.id] then continue end
    tile.terrain="Plains"; tile.resource=nil
    table.insert(stress.units,{id=stress.nextUnit,ownerId=if stress.nextUnit%2==0 then 1 else 2,kind="Warrior",tileId=tile.id,hp=100,moves=2,fortified=false,level=0}); stress.nextUnit+=1
end
stress.diplomacy.status="War"; assert(Game.serialize(stress))
measure("Huge 169-unit war both actor snapshots",20,function() Game.snapshot(stress,1); Game.snapshot(stress,2) end)
measure("Huge 169-unit war human round",10,function() assert(Game.apply(stress,1,{kind="EndTurn"}).ok); assert(Game.apply(stress,2,{kind="EndTurn"}).ok) end)
assert(Game.serialize(stress))
print("Retained caps: 2 immutable frequency descriptors; 8 BFS rows/map (<=38,736 distances); 64 local disks/match; 169 units; 24 cities")
