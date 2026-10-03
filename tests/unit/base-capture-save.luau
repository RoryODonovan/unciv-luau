--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original authoritative city-capture and immediate save/restore regression fixtures.
local Game=require("../../src/simulation/BaseGame")
local Save=require("../../src/simulation/BaseSave")
local Map=require("../../src/simulation/WorldMap")
local function apply(state: any,actor: number,command: any)
    local result=Game.apply(state,actor,command); assert(result.ok,result.message)
end
local function unit(state: any,actor: number,kind: string): any
    for _,u in state.units do if u.ownerId==actor and u.kind==kind then return u end end
    error("missing unit")
end
local function equal(a: any,b: any): boolean
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in a do if not equal(v,b[k]) then return false end end
    for k in b do if a[k]==nil then return false end end
    return true
end
for _,shape in {"Hex","Sphere"} do
    for _,domination in {false,true} do
        local state: any=Game.new(42,if shape=="Sphere" then {humanPlayers=2,mapShape="Sphere",frequency=2} else {humanPlayers=2,radius=4})
        apply(state,1,{kind="FoundCity",unitId=unit(state,1,"Settler").id})
        apply(state,1,{kind="EndTurn"})
        apply(state,2,{kind="FoundCity",unitId=unit(state,2,"Settler").id})
        local graph=if shape=="Sphere" then Map.fromSphereTiles(state.tiles,state.frequency) else Map.fromTiles(state.tiles,state.radius)
        if not domination then
            -- The rival keeps its original capital when a second city is captured.
            local occupied={}; for _,u in state.units do occupied[u.tileId]=true end
            local site: number?=nil
            for _,tile in state.tiles do
                if not occupied[tile.id] and Map.distance(graph,tile.id,state.cities[1].tileId)>=3 and Map.distance(graph,tile.id,state.cities[2].tileId)>=3 then site=tile.id; break end
            end
            assert(site,"need a distinct second-city site")
            state.tiles[site].terrain="Plains"; state.tiles[site].resource=nil
            local settler={id=state.nextUnit,ownerId=2,kind="Settler",tileId=site,hp=50,moves=2,fortified=false,level=0}
            table.insert(state.units,settler); state.nextUnit+=1
            apply(state,2,{kind="FoundCity",unitId=settler.id})
        end
        apply(state,2,{kind="EndTurn"})
        local target=state.cities[if domination then 2 else 3]
        local attacker=unit(state,1,"Warrior")
        local occupied={}; for _,u in state.units do occupied[u.tileId]=true end
        local adjacent: number?=nil
        for _,id in graph.neighbors[target.tileId] do if not occupied[id] then adjacent=id; break end end
        assert(adjacent,"need a free attacking tile")
        attacker.tileId=adjacent; attacker.moves=2
        state.tiles[adjacent].terrain="Plains"; state.tiles[adjacent].resource=nil
        target.hp=1
        assert(Save.valid(Game.serialize(state)),"capture fixture must start as a valid save")
        apply(state,1,{kind="DeclareWar",targetId=2})
        apply(state,1,{kind="MoveUnit",unitId=attacker.id,tileId=target.tileId})
        assert(target.ownerId==1 and attacker.tileId==target.tileId)
        assert(target.queue=="" and target.production==0,"capture clears the queue to idle")
        local forecast=Game.snapshot(state,1).cityForecasts[tostring(target.id)]
        assert(forecast.productionBlocked=="Idle" and forecast.productionTurns==nil)
        assert(state.phase==(if domination then "Finished" else "Playing"))
        if domination then assert(state.winner==1 and state.victoryType=="Domination") end
        local capture: any=nil
        for _,event in state.events do if event.kind=="Capture" then capture=event end end
        assert(capture and capture.tileId==target.tileId and capture.unitId==attacker.id and capture.ownerId==1)
        -- Save immediately while Capture is retained, including the terminal victory state.
        local saved=Game.serialize(state)
        assert(saved.version==(if shape=="Sphere" then 2 else 1) and Save.valid(saved))
        local restored,reason=Game.restore(saved)
        assert(restored and reason==nil and equal(saved,Game.serialize(restored)))
        assert(restored.cities[if domination then 2 else 3].ownerId==1)
        local unknown=Game.serialize(state)
        for _,event in unknown.state.events do if event.kind=="Capture" then event.kind="UnknownCapture" end end
        assert(not Save.valid(unknown),"unknown event kinds must still reject")
        print(shape.." immediate "..(if domination then "domination" else "city capture").." save roundtrip passed")
    end
end
