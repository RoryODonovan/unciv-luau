--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original graph, save, fog and real-turn regression fixtures.
local Game=require("../../src/simulation/BaseGame")
local Save=require("../../src/simulation/BaseSave")
local Map=require("../../src/simulation/WorldMap")
local Sphere=require("../../src/map/SphereTopology")
local Sizes=require("../../src/map/MapSizes")
local function equal(a: any,b: any): boolean
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in a do if not equal(v,b[k]) then return false end end
    for k in b do if a[k]==nil then return false end end; return true
end
local function unit(state: any,owner: number,kind: string): any
    for _,u in state.units do if u.ownerId==owner and u.kind==kind then return u end end; error("missing unit")
end
local function apply(state: any,owner: number,command: any)
    local result=Game.apply(state,owner,command); assert(result.ok,result.message)
end
for _,preset in Sizes.spherePresets do
    local f=preset.frequency; local s: any=Game.new(42,{humanPlayers=2,mapShape="Sphere",frequency=f})
    assert(s.mapShape=="Sphere" and s.frequency==f and s.radius==nil and #s.tiles==preset.tileCount)
    assert(equal(s,Game.new(42,{humanPlayers=2,mapShape="Sphere",frequency=f})),"seed determinism")
    local saved=Game.serialize(s); assert(saved.version==2 and Save.valid(saved))
    local restored=Game.restore(saved); assert(restored and equal(saved,Game.serialize(restored)))
    local descriptor=Sphere.generate(f); local map=Map.fromSphereTiles(s.tiles,f); local starts={unit(s,1,"Settler").tileId,unit(s,2,"Settler").tileId}
    local path,cost=Map.shortestPath(map,starts[1],starts[2]); assert(path and #path>2 and cost,"connected playable generated starts")
    local total=0
    for i=2,#path do assert(table.find(map.neighbors[path[i-1]],path[i])); total+=Map.movementCost(s.tiles[path[i]]) :: number end
    assert(total==cost and #path-1>=Map.distance(map,starts[1],starts[2]),"optimal land route respects adjacency and terrain costs")
    for owner=1,2 do
        local view=Game.snapshot(s,owner); assert(view.mapShape=="Sphere" and view.frequency==f and view.radius==nil and view.seed==nil)
        local unknown=0
        for _,tile in view.tiles do
            assert(tile.x==nil and tile.y==nil and (tile :: any).corners==nil and (tile :: any).center==nil)
            if not tile.explored then unknown+=1; assert(tile.terrain==nil and tile.resource==nil and tile.ownerId==nil and tile.food==nil) end
        end
        if f>2 then assert(unknown>0) end
        assert(view.scores[3-owner]==0 and view.statistics[3-owner].units==0)
    end
    apply(s,1,{kind="FoundCity",unitId=unit(s,1,"Settler").id}); apply(s,1,{kind="EndTurn"})
    apply(s,2,{kind="FoundCity",unitId=unit(s,2,"Settler").id}); apply(s,2,{kind="EndTurn"})
    assert(#s.cities==2 and #Game.snapshot(s,1).cities>=1 and #Game.snapshot(s,2).cities>=1)
    assert(Game.restore(Game.serialize(s)))
    local solo: any=Game.new(73,{mapShape="Sphere",frequency=f})
    apply(solo,1,{kind="FoundCity",unitId=unit(solo,1,"Settler").id})
    for _=1,12 do if solo.phase=="Playing" then apply(solo,1,{kind="EndTurn"}) end end
    assert(solo.turn>1 and #solo.cities>=2 and solo.players[2].science>0 and Save.valid(Game.serialize(solo)),"actual AI turns")
    -- Movement and vision across the longitude seam use graph neighbors, including pentagons.
    local seamA,seamB=0,0
    for id,cell in descriptor.cells do for _,other in cell.neighbors do
        local p,q=cell.center,descriptor.cells[other].center
        if p.x<0 and q.x<0 and p.z<0 and q.z>=0 then seamA,seamB=id,other; break end
    end; if seamA>0 then break end end
    assert(seamA>0 and Map.inRange(map,seamA,seamB,1) and Map.distance(map,seamA,seamB)==1)
    assert(table.find(Map.visibility(map,{seamA},1),seamB))
    local seamState: any=Game.new(42,{humanPlayers=2,mapShape="Sphere",frequency=f})
    local mover=unit(seamState,1,"Warrior")
    for _,u in seamState.units do if u~=mover and (u.tileId==seamA or u.tileId==seamB) then u.tileId=starts[2]; if u.ownerId==1 then u.tileId=starts[1] end end end
    -- Keep all other units at distinct unaffected graph cells.
    local occupied={[seamA]=true,[seamB]=true}
    for _,u in seamState.units do if u~=mover then
        local id=u.tileId; while occupied[id] do id=id%#seamState.tiles+1 end
        occupied[id]=true; u.tileId=id; seamState.tiles[id].terrain="Plains"; seamState.tiles[id].resource=nil; seamState.tiles[id].feature=nil
    end end
    mover.tileId=seamA; mover.moves=2
    for _,id in {seamA,seamB} do seamState.tiles[id].terrain="Plains"; seamState.tiles[id].resource=nil; seamState.tiles[id].feature=nil end
    apply(seamState,1,{kind="MoveUnit",unitId=mover.id,tileId=seamB}); assert(mover.tileId==seamB and Save.valid(Game.serialize(seamState)))
    local defender=unit(seamState,2,"Warrior"); defender.tileId=seamA; defender.hp=100
    seamState.diplomacy.status="War"; mover.moves=2
    for owner=1,2 do
        local seamView=Game.snapshot(seamState,owner)
        assert(seamView.tiles[seamA].visible and seamView.tiles[seamB].visible,"both actors see across seam")
    end
    apply(seamState,1,{kind="MoveUnit",unitId=mover.id,tileId=seamA})
    assert(defender.hp<100 and Save.valid(Game.serialize(seamState)),"melee combat crosses the seam")
    for second=1,20 do Map.distance(map,1,second) end; assert(map.distanceOrder and #map.distanceOrder<=8)
    assert(Map.cappedDistance(map,starts[1],starts[2],2)==2)
    -- Sphere-only version 2 has no coordinate or geometry escape hatches.
    for _,bad in {"radius","corners","neighbors","center"} do local corrupt=Game.serialize(s); corrupt.state[bad]={}; assert(not Save.valid(corrupt)) end
    local bad=Game.serialize(s); bad.state.tiles[1].x=0; assert(not Save.valid(bad))
    bad=Game.serialize(s); bad.version=1; assert(not Save.valid(bad))
    bad=Game.serialize(s); bad.state.frequency=23; assert(not Save.valid(bad))
    bad=Game.serialize(s); table.remove(bad.state.tiles); assert(not Save.valid(bad))
    print(preset.name.." sphere gameplay, both fog views, saves, seam movement and AI passed")
end
local stress: any=Game.new(42,{humanPlayers=2,mapShape="Sphere",frequency=22})
local occupied={}; for _,u in stress.units do occupied[u.tileId]=true end
for _,tile in stress.tiles do
    if #stress.units>=169 then break end
    if occupied[tile.id] then continue end
    tile.terrain="Plains"; tile.resource=nil; tile.feature=nil
    table.insert(stress.units,{id=stress.nextUnit,ownerId=if stress.nextUnit%2==0 then 1 else 2,kind="Warrior",tileId=tile.id,hp=100,moves=2,fortified=false,level=0}); stress.nextUnit+=1
end
stress.diplomacy.status="War"
assert(#stress.units==169 and Save.valid(Game.serialize(stress)))
for owner=1,2 do local view=Game.snapshot(stress,owner); assert(#view.units>=80); apply(stress,owner,{kind="EndTurn"}) end
assert(Save.valid(Game.serialize(stress)))
local legacy=Game.serialize(Game.new(42,{radius=4})); assert(legacy.version==1 and legacy.state.mapShape==nil and legacy.state.frequency==nil and Game.restore(legacy))
assert(not Save.valid({format="unciv-luau-base",version=2}))
assert(not Save.valid({format="unciv-luau-base",version=2,state=false}))
print("Sphere Huge 169-unit war snapshots and turns, legacy v1 preservation passed")
