--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original idle-production regression fixtures through the public command, snapshot and save APIs.
local Game=require("../../src/simulation/BaseGame")
local Save=require("../../src/simulation/BaseSave")
local Rules=require("../../src/simulation/BaseRules")
local function apply(s: any, actor: number, command: any)
    local result=Game.apply(s,actor,command); assert(result.ok,result.message)
end
local function equal(a: any,b: any): boolean
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in a do if not equal(v,b[k]) then return false end end
    for k in b do if a[k]==nil then return false end end
    return true
end
local function fixture(): (any,any)
    local s: any=Game.new(42,{humanPlayers=2,radius=8,maxTurns=120})
    for _,u in s.units do if u.ownerId==1 and u.kind=="Settler" then apply(s,1,{kind="FoundCity",unitId=u.id}); break end end
    local city=s.cities[1]; assert(city.queue=="Warrior","new cities still start on Warrior")
    return s,city
end
local function idleForecast(s: any,city: any)
    local before=Game.serialize(s)
    local view=Game.snapshot(s,1); local f=view.cityForecasts[tostring(city.id)]
    assert(city.queue=="" and f.productionBlocked=="Idle" and f.productionTurns==nil,"idle queue has an explicit forecast")
    assert(f.production>0,"the idle city still has a production yield")
    assert(equal(before,Game.serialize(s)),"forecast is read-only")
    assert(table.find(view.availableProductionByCity[tostring(city.id)],"Warrior"),"idle city offers real choices")
end
do
    local s,city=fixture()
    apply(s,1,{kind="SetProduction",cityId=city.id,item="Monument"})
    city.production=Rules.productionCosts.Monument+7
    local made=Game.snapshot(s,1).cityForecasts[tostring(city.id)].production
    apply(s,1,{kind="EndTurn"})
    assert(table.find(city.buildings,"Monument") and city.queue=="","completed building goes idle")
    assert(city.production==7+made,"completion keeps its overflow")
    idleForecast(s,city)
    local stored=city.production; local count=s.nextUnit
    for _=1,3 do
        apply(s,2,{kind="EndTurn"}); apply(s,1,{kind="EndTurn"})
        assert(city.production==stored and s.nextUnit==count,"idle turns neither accumulate production nor train Warriors")
        idleForecast(s,city)
    end
    local saved=Game.serialize(s)
    assert(saved.version==1 and Save.valid(saved),"idle saves keep version 1")
    local restored=assert(Game.restore(saved)); local direct=assert(Save.restore(saved))
    assert(equal(saved,Game.serialize(restored)) and equal(saved,Save.serialize(direct)),"both idle restore paths round-trip unchanged")
    local bad=Game.serialize(s); bad.state.cities[1].queue="UnknownItem"
    assert(not Save.valid(bad),"only the empty string joins valid production ids")
    bad=Game.serialize(s); bad.state.cities[1].queue=false
    assert(not Save.valid(bad),"queue must still be a string")
    apply(s,2,{kind="EndTurn"})
    for _,kind in {"SetProduction","Purchase"} do
        local before=Game.serialize(s)
        local command: any={kind=kind,cityId=city.id,item=""}
        local rejected=Game.apply(s,1,command)
        assert(not rejected.ok and equal(before,Game.serialize(s)),"clients cannot select or purchase idle")
    end
    apply(s,1,{kind="SetProduction",cityId=city.id,item="Warrior"})
    local f=Game.snapshot(s,1).cityForecasts[tostring(city.id)]
    assert(city.production==stored and f.productionBlocked==nil and f.productionTurns==1,"choosing from idle uses retained overflow")
    apply(s,1,{kind="EndTurn"})
    assert(city.queue=="Warrior" and s.nextUnit==count+1,"completed unit still repeats")
end
-- Purchases preserve an unrelated idle queue and its stored overflow, for both unit and building items.
do
    local s,city=fixture(); city.queue=""; city.production=9; s.players[1].gold=1000
    local count=s.nextUnit
    apply(s,1,{kind="Purchase",cityId=city.id,item="Warrior"})
    assert(s.nextUnit==count+1 and city.queue=="" and city.production==9)
    apply(s,1,{kind="Purchase",cityId=city.id,item="Monument"})
    assert(table.find(city.buildings,"Monument") and city.queue=="" and city.production==9)
    idleForecast(s,city)
end
-- The AI selects from an idle queue before production, then fills a queue emptied by that same turn's completion.
do
    local s: any=Game.new(42,{radius=8,barbarians=false})
    local city=s.cities[1]; assert(city.ownerId==2)
    city.queue=""; city.production=100
    apply(s,1,{kind="EndTurn"})
    assert(#city.buildings>0,"the AI chose and completed a building this turn")
    assert(city.queue~="" and Rules.productionCosts[city.queue],"AI completion selects a real next item before turn end")
    assert(Save.valid(Game.serialize(s)))
end
-- Leave an optional building outside the AI's ordinary priorities while the global cap blocks every unit.
local function cappedFixture(remaining: string?): (any,any)
    local s: any=Game.new(42,{radius=10,barbarians=false})
    local city=s.cities[1]; city.queue=""; city.production=9
    for _,id in Rules.technologyOrder do if id~=Rules.scienceVictoryTechnology then table.insert(s.players[2].technologies,id) end end
    for _,id in Rules.buildingOrder do if id~=Rules.scienceVictoryBuilding and id~=remaining then table.insert(city.buildings,id) end end
    s.players[2].gold=10000
    local used={}; for _,u in s.units do used[u.tileId]=true end
    for _,tile in s.tiles do
        if #s.units>=Rules.maxUnits then break end
        if used[tile.id] or tile.id==city.tileId then continue end
        tile.terrain="Plains"; tile.resource=nil; tile.feature=nil
        table.insert(s.units,{id=s.nextUnit,ownerId=2,kind="Worker",tileId=tile.id,hp=50,moves=0,fortified=false,level=0})
        s.nextUnit += 1
    end
    assert(#s.units==Rules.maxUnits and Save.valid(Game.serialize(s)))
    return s,city
end
for _,item in {"Walls","Temple"} do
    local s,city=cappedFixture(item)
    -- Keep the legal building queued long enough to observe it after the economy step.
    city.production=0; city.focus="Science"; s.players[2].income.gold=0
    local view=Game.snapshot(s,2)
    assert(table.find(view.availableProductionByCity[tostring(city.id)],item),item.." is legal at the unit cap")
    assert(view.cityForecasts[tostring(city.id)].production<Rules.productionCosts[item],"fixture cannot finish "..item.." in one turn")
    apply(s,1,{kind="EndTurn"})
    assert(city.queue==item and #s.units==Rules.maxUnits,"AI queues remaining "..item.." instead of blocked Warrior")
    local f=Game.snapshot(s,2).cityForecasts[tostring(city.id)]
    assert(f.productionBlocked==nil and f.productionTurns~=nil)
    assert(Save.valid(Game.serialize(s)))
end
-- Even when every available building is finished and the unit cap blocks every unit, an AI keeps a real queue.
do
    local s,city=cappedFixture(nil)
    apply(s,1,{kind="EndTurn"})
    assert(city.queue=="Warrior" and #s.units==Rules.maxUnits,"AI keeps a repeatable item blocked by the unit cap")
    local f=Game.snapshot(s,2).cityForecasts[tostring(city.id)]
    assert(f.productionBlocked=="NotAvailable" and f.productionTurns==nil)
    assert(Save.valid(Game.serialize(s)))
end
print("base idle production: building completion, retained overflow, idle forecasts, client refusals, purchases, unit repetition, saves and same-turn AI choices passed")
