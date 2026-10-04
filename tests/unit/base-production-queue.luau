--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original G14a production queue fixtures through public commands, forecasts, events and saves.
local Game=require("../../src/simulation/BaseGame")
local Save=require("../../src/simulation/BaseSave")
local Rules=require("../../src/simulation/BaseRules")
local Map=require("../../src/simulation/WorldMap")
local function equal(a: any,b: any): boolean
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in a do if not equal(v,b[k]) then return false end end
    for k in b do if a[k]==nil then return false end end; return true
end
local function apply(s: any,actor: number,cmd: any)
    local result=Game.apply(s,actor,cmd); assert(result.ok,result.message)
end
local function rejected(s: any,actor: number,cmd: any,message: string?)
    local before=Game.serialize(s); local result=Game.apply(s,actor,cmd)
    assert(not result.ok and equal(before,Game.serialize(s)),"refusal must not mutate state")
    if message then assert(result.message==message,result.message) end
end
local function fixture(shape: string?): (any,any,any)
    local s: any=Game.new(42,if shape=="Sphere" then {humanPlayers=2,mapShape="Sphere",frequency=2,maxTurns=120} else {humanPlayers=2,radius=8,maxTurns=120})
    for actor=1,2 do
        for _,u in s.units do if u.ownerId==actor and u.kind=="Settler" then apply(s,actor,{kind="FoundCity",unitId=u.id}); break end end
        apply(s,actor,{kind="EndTurn"})
    end
    for _,p in s.players do p.technologies=table.clone(Rules.technologyOrder); p.research=nil; p.gold=10000 end
    return s,s.cities[1],s.cities[2]
end
local function queue(s: any,c: any,item: string) apply(s,1,{kind="QueueProduction",cityId=c.id,item=item}) end
local function viewCity(view: any,id: number): any
    for _,c in view.cities do if c.id==id then return c end end; error("city missing")
end
local function skips(view: any): {any}
    local list={}; for _,e in view.events do if e.kind=="QueueSkipped" then table.insert(list,e) end end; return list
end
assert(Rules.productionQueueLimit==3 and Game.getRules().productionQueueLimit==3)
do
    local s,c,rival=fixture()
    assert(c.queueNext==nil)
    queue(s,c,"Monument"); queue(s,c,"Granary")
    assert(c.queue=="Warrior" and equal(c.queueNext,{"Monument","Granary"}),"append preserves current and order")
    rejected(s,1,{kind="QueueProduction",cityId=c.id,item="Worker"},"The production queue is full.")
    apply(s,1,{kind="RemoveQueued",cityId=c.id,index=1})
    assert(equal(c.queueNext,{"Granary"}),"remove shifts later items")
    for _,index in {0,-1,2,1.5,math.huge,0/0,"1"} do
        rejected(s,1,{kind="RemoveQueued",cityId=c.id,index=index},"Invalid queued production index.")
    end
    rejected(s,1,{kind="RemoveQueued",cityId=c.id,index=1,extra=1})
    rejected(s,1,{kind="RemoveQueued",cityId=c.id})
    rejected(s,2,{kind="QueueProduction",cityId=rival.id,item="Monument"},"Wait for your civilization's turn.")
    rejected(s,1,{kind="QueueProduction",cityId=rival.id,item="Monument"},"Select your city.")
    rejected(s,1,{kind="RemoveQueued",cityId=rival.id,index=1},"Select your city.")
    apply(s,1,{kind="SetProduction",cityId=c.id,item="Worker"})
    assert(c.queue=="Worker" and equal(c.queueNext,{"Granary"}),"SetProduction keeps successors")
    apply(s,1,{kind="RemoveQueued",cityId=c.id,index=1}); assert(c.queueNext==nil,"last removal clears optional field")
    rejected(s,1,{kind="RemoveQueued",cityId=c.id,index=1})
    c.queue=""; local stored=c.production
    queue(s,c,"Monument"); assert(c.queue=="Monument" and c.queueNext==nil and c.production==stored,"idle append becomes current")
    rejected(s,1,{kind="QueueProduction",cityId=c.id,item="Monument"},"This item is already in the production queue.")
    queue(s,c,"Granary")
    rejected(s,1,{kind="QueueProduction",cityId=c.id,item="Granary"},"This item is already in the production queue.")
    apply(s,1,{kind="RemoveQueued",cityId=c.id,index=1})
    apply(s,1,{kind="SetProduction",cityId=c.id,item="Warrior"}); queue(s,c,"Warrior"); queue(s,c,"Warrior")
    assert(equal(c.queueNext,{"Warrior","Warrior"}),"units may repeat current and future ids")
end
do
    local s,c=fixture()
    rejected(s,1,{kind="QueueProduction",cityId=c.id,item="Unknown"},"Production item is unavailable.")
    rejected(s,1,{kind="QueueProduction",cityId=c.id,item=""})
    rejected(s,1,{kind="QueueProduction",cityId=c.id,item="Swordsman"},"Not enough Iron: needs 1, 0 available and 0 in use.")
    s.players[1].technologies={}
    rejected(s,1,{kind="QueueProduction",cityId=c.id,item="Granary"},"Production item is unavailable.")
end
-- Overflow is retained and at most one item completes per city per economy step.
for _,item in {"Monument","Warrior"} do
    local s,c=fixture(); apply(s,1,{kind="SetProduction",cityId=c.id,item=if item=="Warrior" then "Worker" else item})
    if item=="Warrior" then apply(s,1,{kind="SetProduction",cityId=c.id,item=item}) end
    queue(s,c,"Granary"); queue(s,c,"Worker")
    c.production=Rules.productionCosts[item]+70
    local made=Game.snapshot(s,1).cityForecasts[tostring(c.id)].production
    apply(s,1,{kind="EndTurn"})
    assert(c.queue=="Granary" and equal(c.queueNext,{"Worker"}) and c.production==70+made,"completion advances with overflow")
    assert(not table.find(c.buildings,"Granary"),"overflow does not complete two items in one turn")
    apply(s,2,{kind="EndTurn"}); apply(s,1,{kind="EndTurn"})
    assert(c.queue=="Worker" and c.queueNext==nil and table.find(c.buildings,"Granary"),"successors advance in order")
end
for _,item in {"Monument","Warrior"} do
    local s,c=fixture(); if item=="Monument" then apply(s,1,{kind="SetProduction",cityId=c.id,item=item}) end
    queue(s,c,"Granary"); queue(s,c,"Worker"); c.production=9
    apply(s,1,{kind="Purchase",cityId=c.id,item="Scout"})
    assert(c.queue==item and equal(c.queueNext,{"Granary","Worker"}) and c.production==9,"unrelated purchase preserves all queue state")
    apply(s,1,{kind="Purchase",cityId=c.id,item=item})
    assert(c.queue=="Granary" and equal(c.queueNext,{"Worker"}) and c.production==9,"purchase of current advances without spending stored production")
end
do
    local s,c=fixture(); apply(s,1,{kind="SetProduction",cityId=c.id,item="Monument"})
    queue(s,c,"Granary"); queue(s,c,"Worker")
    apply(s,1,{kind="Purchase",cityId=c.id,item="Granary"})
    apply(s,1,{kind="Purchase",cityId=c.id,item="Monument"})
    assert(c.queue=="Worker" and c.queueNext==nil,"unavailable head is dropped and the next item chosen")
    local events=skips(Game.snapshot(s,1)); assert(#events==1 and events[1].cityId==c.id and events[1].ownerId==1)
    assert(events[1].message=="Skipped Granary: Production item is unavailable." and events[1].tileId==nil and not events[1].public)
    assert(#skips(Game.snapshot(s,2))==0,"skip event is owner private")
    assert(Save.valid(Game.serialize(s)),"skip events can be saved")
end
do
    local s,c=fixture(); apply(s,1,{kind="SetProduction",cityId=c.id,item="Monument"})
    local tile=s.tiles[c.tileId]; tile.terrain="Hills"; tile.feature=nil; tile.resource="Iron"; tile.improvement="Mine"
    queue(s,c,"Swordsman")
    tile.resource=nil; tile.improvement=nil
    c.production=Rules.productionCosts.Monument+7
    local made=Game.snapshot(s,1).cityForecasts[tostring(c.id)].production
    apply(s,1,{kind="EndTurn"})
    assert(c.queue=="" and c.queueNext==nil and c.production==7+made,"exhausted unavailable successors go idle with overflow")
    local events=skips(Game.snapshot(s,1))
    assert(#events==1 and events[1].message=="Skipped Swordsman: Not enough Iron: needs 1, 0 available and 0 in use.")
    apply(s,2,{kind="EndTurn"}); local stored=c.production; apply(s,1,{kind="EndTurn"})
    assert(c.production==stored,"idle does not accumulate production")
end
-- A wonder completed by the rival advances a current losing race and invalidates a future race.
do
    local s,c,rival=fixture()
    queue(s,c,"HangingGardens"); queue(s,c,"Granary")
    apply(s,1,{kind="SetProduction",cityId=c.id,item="HangingGardens"})
    c.production=3
    apply(s,1,{kind="EndTurn"})
    apply(s,2,{kind="SetProduction",cityId=rival.id,item="HangingGardens"})
    local stored=c.production; rival.production=Rules.productionCosts.HangingGardens
    apply(s,2,{kind="EndTurn"})
    assert(c.queue=="Granary" and c.queueNext==nil and c.production==stored,"lost current wonder advances while retaining production")
    assert(#skips(Game.snapshot(s,1))==1 and skips(Game.snapshot(s,1))[1].message=="Skipped HangingGardens: Production item is unavailable.","loser conversion skips an unavailable successor")
    local lost=false; for _,e in Game.snapshot(s,1).events do if e.kind=="WonderLost" then lost=true end end; assert(lost)
end
do
    local s,c,rival=fixture(); apply(s,1,{kind="SetProduction",cityId=c.id,item="Monument"})
    queue(s,c,"HangingGardens"); queue(s,c,"Worker")
    apply(s,1,{kind="EndTurn"})
    apply(s,2,{kind="SetProduction",cityId=rival.id,item="HangingGardens"})
    rival.production=Rules.productionCosts.HangingGardens; apply(s,2,{kind="EndTurn"})
    apply(s,1,{kind="Purchase",cityId=c.id,item="Monument"})
    assert(c.queue=="Worker" and c.queueNext==nil and #skips(Game.snapshot(s,1))==1,"future lost wonder is skipped on activation")
end
-- Same-owner current wonder reservation is shared with SetProduction; activation checks it again.
do
    local s,c,rival=fixture(); local graph=Map.fromTiles(s.tiles,s.radius); local site: number?=nil
    for _,tile in s.tiles do if not tile.ownerId and Rules.terrains[tile.terrain].passable and Map.distance(graph,tile.id,c.tileId)>=3 and Map.distance(graph,tile.id,rival.tileId)>=3 then site=tile.id; break end end
    assert(site)
    local second={id=s.nextCity,ownerId=1,originalOwnerId=1,capital=false,tileId=site,name="Queue fixture",population=1,food=0,production=0,queue="Warrior",hp=Rules.cityHp,buildings={},focus="Balanced"}
    s.nextCity+=1; table.insert(s.cities,second); s.tiles[site].ownerId=1
    apply(s,1,{kind="SetProduction",cityId=second.id,item="HangingGardens"})
    rejected(s,1,{kind="QueueProduction",cityId=c.id,item="HangingGardens"},"Production item is unavailable.")
    apply(s,1,{kind="SetProduction",cityId=second.id,item="Worker"})
    queue(s,c,"HangingGardens")
    rejected(s,1,{kind="QueueProduction",cityId=c.id,item="HangingGardens"},"This item is already in the production queue.")
    apply(s,1,{kind="SetProduction",cityId=second.id,item="HangingGardens"})
    queue(s,c,"Granary"); c.production=Rules.productionCosts.Warrior
    apply(s,1,{kind="EndTurn"})
    assert(c.queue=="Granary" and #skips(Game.snapshot(s,1))==1,"activation skips another own city's reserved wonder")
end
do
    local s,c=fixture(); queue(s,c,"Granary")
    apply(s,1,{kind="SetProduction",cityId=c.id,item="Granary"})
    apply(s,1,{kind="Purchase",cityId=c.id,item="Granary"})
    assert(c.queue=="" and c.queueNext==nil and #skips(Game.snapshot(s,1))==1,"SetProduction's retained duplicate is skipped after completing it")
end
for _,shape in {"Hex","Sphere"} do
    local s,c,rival=fixture(shape); queue(s,c,"Monument"); queue(s,c,"Granary"); c.production=5
    for _,tile in s.tiles do tile.terrain="Grassland"; tile.feature=nil; tile.resource=nil; tile.improvement=nil; tile.river=nil end
    local before=Game.serialize(s); local view=Game.snapshot(s,1); local own=viewCity(view,c.id)
    assert(view.cityForecasts[tostring(c.id)].production==2,"bare grassland fixture makes two production per turn")
    assert(equal(own.queueNext,{"Monument","Granary"}) and own.queueNext~=c.queueNext)
    -- Warrior 12 + Monument 14 + Granary 16, less 5 stored, at 2 per turn: 11 then 19 turns.
    assert(equal(own.queueTurns,{11,19}),"queue turns include remaining current production and both future costs")
    assert(equal(before,Game.serialize(s)),"queue view does not mutate state")
    c.production=100
    assert(equal(viewCity(Game.snapshot(s,1),c.id).queueTurns,{2,3}),"large overflow still needs one economy step per completion")
    c.production=5
    own.queueNext[1]="Worker"; own.queueTurns[1]=999
    assert(c.queueNext[1]=="Monument" and viewCity(Game.snapshot(s,1),c.id).queueTurns[1]~=999,"view arrays are detached")
    -- Give the rival sight of the city, so the privacy assertion inspects a visible CityView.
    local graph=if shape=="Sphere" then Map.fromSphereTiles(s.tiles,s.frequency) else Map.fromTiles(s.tiles,s.radius)
    for _,u in s.units do if u.ownerId==2 then
        for _,tileId in graph.neighbors[c.tileId] do
            local occupied=false; for _,other in s.units do if other.tileId==tileId then occupied=true end end
            if not occupied then s.tiles[tileId].terrain="Plains"; s.tiles[tileId].resource=nil; s.tiles[tileId].feature=nil; u.tileId=tileId; break end
        end; break
    end end
    -- Reconcile territory sight/contact after the fixture teleports the rival, as commands do in play.
    apply(s,1,{kind="SetCityFocus",cityId=c.id,focus="Production"})
    local seen=viewCity(Game.snapshot(s,2),c.id)
    assert(seen.queueNext==nil and seen.queueTurns==nil and seen.queue==nil,"rival sees neither queue array")
    local saved=Game.serialize(s); assert(saved.version==(if shape=="Sphere" then 2 else 1))
    local restored=assert(Game.restore(saved)); local direct=assert(Save.restore(saved))
    assert(equal(saved,Game.serialize(restored)) and equal(saved,Save.serialize(direct)),"queues round-trip through both restore APIs")
    local restoredCity: any=restored.cities[1]
    restoredCity.queueNext[1]="Worker"; assert(saved.state.cities[1].queueNext[1]=="Monument","restore is detached")
    for _,invalid in {{"Warrior","Warrior","Warrior"},{"Unknown"},{""},{false},{[2]="Warrior"},{[1]="Warrior",extra="Worker"},"Warrior"} do
        local bad=Game.serialize(s); bad.state.cities[1].queueNext=invalid
        assert(not Save.valid(bad) and Game.restore(bad)==nil and Save.restore(bad)==nil,"bad successor array must reject")
    end
    local legacy=Game.serialize(s); for _,city in legacy.state.cities do city.queueNext=nil end
    assert(equal(legacy,Game.serialize(assert(Game.restore(legacy)))) and equal(legacy,Save.serialize(assert(Save.restore(legacy)))),"legacy saves keep successors absent")
    local empty=Game.serialize(s); empty.state.cities[1].queueNext={}
    assert(Save.valid(empty)); local loaded=assert(Game.restore(empty))
    assert(loaded.cities[1].queueNext==nil and equal(legacy,Game.serialize(loaded)),"empty successor arrays serialize as absent")
    assert(equal(legacy,Save.serialize(assert(Save.restore(empty)))),"direct empty restore and serialization are canonical too")
    s.cities[1].queueNext={}; assert(equal(legacy,Game.serialize(s)),"serialization also normalizes empty queues")
    assert(equal(legacy,Save.serialize(s)),"direct serialization normalizes empty queues too")
    s.cities[1].queueNext={"Warrior","Warrior"}; assert(Save.valid(Game.serialize(s)),"repeated unit ids are valid in saves")
    rival.queueNext=nil
end
print("base production queue: commands, limits, duplicates, overflow, purchases, skips, idle, wonder races, private forecasts and save compatibility passed")
