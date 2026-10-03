--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original coherent-world deployment, existing-save preservation and real-turn regressions.
local Game=require("../../src/simulation/BaseGame")
local Map=require("../../src/simulation/WorldMap")
local Rules=require("../../src/simulation/BaseRules")
local Sizes=require("../../src/map/MapSizes")
local Save=require("../../src/simulation/BaseSave")
local function equal(a: any,b: any): boolean
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in a do if not equal(v,b[k]) then return false end end
    for k in b do if a[k]==nil then return false end end
    return true
end
local function unit(state: any,owner: number,kind: string): any
    for _,u in state.units do if u.ownerId==owner and u.kind==kind then return u end end
    error("missing "..kind)
end
local function apply(state: any,owner: number,command: any)
    local result=Game.apply(state,owner,command); assert(result.ok,result.message)
end
-- Natural food and production under the game rules: the terrain's, replaced (Forest, Jungle, Oasis) or reduced (Marsh)
-- by a feature, plus the resource's.
local function natural(tile: any): (number,number)
    local terrain=Rules.terrains[tile.terrain]; local feature=if tile.feature then Rules.features[tile.feature] else nil
    local food,production=terrain.yields.food,terrain.yields.production
    if feature and feature.overrideYields then food,production=feature.yields.food,feature.yields.production
    elseif feature then food+=feature.yields.food; production+=feature.yields.production end
    food,production=math.max(0,food),math.max(0,production)
    if tile.resource then local r=Rules.resources[tile.resource].yields; food+=r.food; production+=r.production end
    return food,production
end
local function metadataFree(value: any)
    if type(value)~="table" then return end
    for key,child in value do
        assert(key~="startIds" and key~="starts" and key~="diagnostics" and key~="centers" and key~="neighbors","generation metadata must stay transient")
        metadataFree(child)
    end
end
-- Adjacent protected regions once exhausted both starter repairs on this exact Duel seed.
-- Inspect the completed map: the second repair must not remove the first site's useful plot.
local protectedMap=Map.generateSphere(116784261,2)
local protectedStarts=protectedMap.startIds :: {number}
for owner,start in protectedStarts do
    local workTile=false
    for _,id in protectedMap.neighbors[start] do
        local tile=protectedMap.tiles[id]
        local terrain=Rules.terrains[tile.terrain]
        local food,production=natural(tile)
        if terrain.passable and food>=2 and production>=1 then workTile=true end
    end
    assert(workTile,string.format("Sphere Duel seed116784261 actor%d needs one same adjacent food/production work tile after both repairs",owner))
end
local protectedState: any=Game.new(116784261,{mapShape="Sphere",frequency=2,humanPlayers=2})
assert(equal(protectedState.tiles,protectedMap.tiles),"deploying both regions must preserve repaired terrain/resources")
for owner=1,2 do
    apply(protectedState,owner,{kind="FoundCity",unitId=unit(protectedState,owner,"Settler").id})
    local city=protectedState.cities[owner]
    assert(city.tileId==protectedStarts[owner])
    apply(protectedState,owner,{kind="SetCityFocus",cityId=city.id,focus="Food"})
    apply(protectedState,owner,{kind="EndTurn"})
end
for _=1,16 do
    for owner=1,2 do apply(protectedState,owner,{kind="EndTurn"}) end
end
assert(protectedState.turn==18 and #protectedState.cities==2)
for owner,city in protectedState.cities do
    assert(city.population>=2 and protectedState.players[owner].income.production>0,"both repaired starters must support actual early growth and production")
end
for _,event in protectedState.events do assert(event.kind~="Starvation","repaired starts must sustain their first citizens") end
local protectedSave=Game.serialize(protectedState)
assert(Save.valid(protectedSave) and equal(protectedSave,Game.serialize(Game.restore(protectedSave) :: Game.State)))
print("Sphere Duel protected-neighbor seed116784261: both useful work tiles, actual founding/growth/turns and save passed")
local names={"Duel","Tiny","Small","Medium","Large","Huge"}
local seeds={0,1,2,42,73,99991}
local seenTerrains: {[string]: boolean}={}
local seenFeatures: {[string]: boolean}={}
local riverMaps=0
local scenarios=0
for _,shape in {"Hex","Sphere"} do
    for _,name in names do
        local preset=if shape=="Sphere" then Sizes.getSphere(name) else Sizes.get(name)
        local radius=if name=="Duel" then 4 else (preset :: any).radius
        local frequency=if shape=="Sphere" then (preset :: any).frequency else nil
        local tiles=if shape=="Sphere" then (preset :: any).tileCount else 1+3*radius*(radius+1)
        local options: any=if shape=="Sphere" then {mapShape="Sphere",frequency=frequency,humanPlayers=2} else {radius=radius,humanPlayers=2}
        local began=os.clock()
        for _,seed in seeds do
            local map=if shape=="Sphere" then Map.generateSphere(seed,frequency :: number) else Map.generate(seed,radius)
            local starts=map.startIds :: {number}
            assert(#map.tiles==tiles and #starts==2 and Map.distance(map,starts[1],starts[2])>=3)
            assert(Map.shortestPath(map,starts[1],starts[2]),"both starts must share a passable land component")
            for id,tile in map.tiles do
                assert(tile.id==id and Rules.terrains[tile.terrain])
                seenTerrains[tile.terrain]=true
                if tile.feature then seenFeatures[tile.feature]=true; assert(table.find(Rules.features[tile.feature].terrains,tile.terrain),"a feature on one of its terrains") end
                if tile.terrain=="Tundra" then assert(tile.resource==nil) end
                if shape=="Sphere" then assert(tile.x==nil and tile.y==nil)
                else assert(tile.x~=nil and tile.y~=nil and Map.tileId(map,tile.x,tile.y)==id) end
            end
            for _,start in starts do
                assert(map.tiles[start].terrain=="Plains" or map.tiles[start].terrain=="Grassland")
                local deployment,food,production=0,0,0
                local initialWorkTile=false
                for _,id in map.neighbors[start] do
                    local tile=map.tiles[id]; local rule=Rules.terrains[tile.terrain]
                    if rule.passable then
                        deployment+=1
                        local tileFood,tileProduction=natural(tile)
                        food=math.max(food,tileFood); production=math.max(production,tileProduction)
                        if tileFood>=2 and tileProduction>=1 then initialWorkTile=true end
                    end
                end
                local reachable=Map.reachable(map,start,math.huge)
                local localResources: {[string]: boolean}={}
                for _,id in Map.range(map,start,2) do
                    local resource=map.tiles[id].resource
                    if reachable[id] and resource then localResources[resource]=true end
                end
                assert(localResources.Iron and localResources.Horses and (localResources.Wheat or localResources.Deer) and (localResources.Gold or localResources.Spices),string.format("%s %s seed%d start%d missing reachable local bonus/strategic/luxury resources",shape,name,seed,start))
                assert(deployment>=3 and initialWorkTile,string.format("%s %s seed%d start%d deployment%d bestFood%d bestProduction%d sameWorkTile%s",shape,name,seed,start,deployment,food,production,tostring(initialWorkTile)))
            end
            local state: any=Game.new(seed,options)
            assert(#state.units==6 and #state.cities==0 and equal(state.tiles,map.tiles),"deployment must preserve generated geography")
            local occupied={}
            for _,u in state.units do assert(not occupied[u.tileId] and Map.movementCost(state.tiles[u.tileId])); occupied[u.tileId]=true end
            for owner=1,2 do
                local settler=unit(state,owner,"Settler")
                assert(settler.tileId==starts[owner])
                for _,kind in {"Warrior","Worker"} do assert(table.find(map.neighbors[settler.tileId],unit(state,owner,kind).tileId)) end
                local view=Game.snapshot(state,owner); metadataFree(view)
                for _,tile in view.tiles do if not tile.explored then assert(tile.terrain==nil and tile.resource==nil) end end
            end
            local saved=Game.serialize(state); assert(Save.valid(saved)); metadataFree(saved)
            local restored=Game.restore(saved); assert(restored and equal(state,restored))
            local rebuilt=if shape=="Sphere" then Map.fromSphereTiles(restored.tiles,frequency :: number) else Map.fromTiles(restored.tiles,radius)
            assert(rebuilt.startIds==nil,"restoring stored terrain must not run generation or invent starts")
            if seed==0 then assert(equal(state,Game.new(seed,options)),"restart with the same current generator must reproduce the world") end
            apply(state,1,{kind="FoundCity",unitId=unit(state,1,"Settler").id})
            apply(state,1,{kind="EndTurn"})
            apply(state,2,{kind="FoundCity",unitId=unit(state,2,"Settler").id})
            assert(#state.cities==2 and Map.distance(map,state.cities[1].tileId,state.cities[2].tileId)>=3)
            apply(state,2,{kind="EndTurn"}); assert(state.turn==2 and Save.valid(Game.serialize(state)))
            scenarios+=1
        end
        local soloOptions: any=table.clone(options); soloOptions.humanPlayers=1
        local solo: any=Game.new(42,soloOptions)
        assert(#solo.units==5 and #solo.cities==1 and solo.cities[1].ownerId==2)
        apply(solo,1,{kind="FoundCity",unitId=unit(solo,1,"Settler").id})
        for _=1,8 do apply(solo,1,{kind="EndTurn"}) end
        assert(solo.turn==9 and solo.players[2].science>0 and #solo.cities>=2 and Save.valid(Game.serialize(solo)),"real solo economy and AI must operate on the generated land")
        print(string.format("%s %s coherent worlds: %d seeds, legal deployment, founding, exact saves and AI %.2fms",shape,name,#seeds,(os.clock()-began)*1000))
    end
end
-- Woods are a feature now: new worlds hold no Forest terrain (it stays valid for older saves) but every feature.
assert(seenTerrains.Tundra and seenTerrains.Water and seenTerrains.Mountain and not seenTerrains.Forest and seenTerrains.Desert)
for _,id in Rules.featureOrder do assert(seenFeatures[id],"worlds include "..id) end
assert(Rules.terrains.Tundra.passable and Rules.terrains.Tundra.movement==1 and Rules.terrains.Tundra.defensePercent==0 and Rules.terrains.Tundra.yields.food==1)
assert(not table.find(Rules.improvements.Farm.terrains,"Tundra"),"generation must not expand unrelated improvement balance")
-- Existing public support includes frequency one, tiny-map capacity and finite safe integer seeds.
for _,shape in {"Hex","Sphere"} do
    for _,seed in {-9007199254740991,9007199254740991,-42,9586495911} do
        local options: any=if shape=="Sphere" then {mapShape="Sphere",frequency=1,humanPlayers=2} else {radius=3,humanPlayers=2}
        local first=Game.new(seed,options)
        assert(equal(first,Game.new(seed,options)) and Save.valid(Game.serialize(first)))
        assert(#first.units==6)
        apply(first,1,{kind="FoundCity",unitId=unit(first,1,"Settler").id})
        apply(first,1,{kind="EndTurn"})
        apply(first,2,{kind="FoundCity",unitId=unit(first,2,"Settler").id})
        assert(Game.restore(Game.serialize(first)))
    end
end
-- Stored terrain is authoritative even when it differs from the current seed generator.
for _,shape in {"Hex","Sphere"} do
    local state: any=Game.new(42,if shape=="Sphere" then {mapShape="Sphere",frequency=2,humanPlayers=2} else {radius=4,humanPlayers=2})
    local saved=Game.serialize(state)
    for id,tile in saved.state.tiles do
        tile.terrain=if id%5==0 then "Water" elseif id%3==0 then "Forest" else "Plains"
        tile.resource=if tile.terrain=="Forest" then "Deer" else nil
        tile.feature=nil; tile.river=nil
    end
    for _,u in saved.state.units do saved.state.tiles[u.tileId].terrain="Plains"; saved.state.tiles[u.tileId].resource=nil end
    assert(Save.valid(saved) and not equal(saved.state.tiles,state.tiles))
    local restored=Game.restore(saved)
    assert(restored and equal(saved,Game.serialize(restored)),"loading an old stored map must preserve every terrain/resource record")
end
-- Tundra stays passable and supports the existing Road order without gaining farms/resources.
local tundra: any=Game.new(42,{radius=4,humanPlayers=2})
apply(tundra,1,{kind="FoundCity",unitId=unit(tundra,1,"Settler").id})
local worker=unit(tundra,1,"Worker")
local tundraTile=tundra.tiles[worker.tileId]
tundraTile.terrain="Tundra"; tundraTile.resource=nil; tundraTile.ownerId=1
for _,id in {"Agriculture","Mining","BronzeWorking","Masonry","Engineering"} do table.insert(tundra.players[1].technologies,id) end
apply(tundra,1,{kind="BuildImprovement",unitId=worker.id,improvement="Road"})
for _=1,2 do apply(tundra,1,{kind="EndTurn"}); apply(tundra,2,{kind="EndTurn"}) end
assert(tundraTile.road and Map.movementCost(tundraTile)==1 and Save.valid(Game.serialize(tundra)))
assert(table.find(Rules.improvements.Road.terrains,"Tundra"))
local tundraSave=Game.serialize(tundra); assert(Game.restore(tundraSave))
print(string.format("World integration passed %d seeded multiplayer worlds and 12 solo AI worlds; stored-map loading remains exact",scenarios))
