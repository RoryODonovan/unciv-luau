--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original fixtures for G8 world wonders and golden ages: the wonder rules, once-per-world completion, lost races that
-- keep their production, each wonder's effect (exact against the economy step and its forecast), the golden-age meter,
-- its trigger, effects, expiry, growing threshold and pace scaling, wonder-started and extended golden ages, events and
-- fog, saves written before G8 and their validation, the AI's wonder plan and deterministic replays.
local Game = require("../../src/simulation/BaseGame")
local Save = require("../../src/simulation/BaseSave")
local WorldMap = require("../../src/simulation/WorldMap")
local Rules = require("../../src/simulation/BaseRules")
local B: any = Rules.buildings
local function equal(a: any,b: any): boolean
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in a do if not equal(v,b[k]) then return false end end
    for k in b do if a[k]==nil then return false end end; return true
end
local function apply(s: any,owner: number,command: any)
    local result=Game.apply(s,owner,command); assert(result.ok,result.message)
end
local function rejected(s: any,owner: number,command: any,label: string,message: string?)
    local before=Game.serialize(s)
    local result=Game.apply(s,owner,command)
    assert(not result.ok,label.." was accepted")
    assert(equal(before,Game.serialize(s)),label.." changed the state")
    if message then assert(result.message==message,label..": unexpected message "..result.message) end
end
local function firstUnit(s: any,owner: number,kind: string): any
    for _, u in s.units do if u.ownerId==owner and u.kind==kind then return u end end; error("missing "..kind)
end
local function firstCity(s: any,owner: number): any
    for _, c in s.cities do if c.ownerId==owner then return c end end; error("missing city")
end
local function cityById(s: any,id: number): any
    for _, c in s.cities do if c.id==id then return c end end; error("missing city "..id)
end
local function eventsOf(events: {any},kind: string,after: number?): {any}
    local list={}; for _, e in events do if e.kind==kind and e.id>(after or 0) then table.insert(list,e) end end; return list
end
local function has(list: {any},value: any): boolean return table.find(list,value)~=nil end
local function founded(seed: number,options: any?): any
    local o: any=options or {}; o.humanPlayers=o.humanPlayers or 2; o.radius=o.radius or 8
    local s=Game.new(seed,o)
    -- Bare terrain (no features or rivers) keeps the yields simple to state.
    for _, t in s.tiles do t.feature=nil; t.river=nil end
    apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id}); apply(s,1,{kind="EndTurn"})
    apply(s,2,{kind="FoundCity",unitId=firstUnit(s,2,"Settler").id}); apply(s,2,{kind="EndTurn"}); return s
end
local function addCity(s: any,owner: number,tileId: number): any
    local c={id=s.nextCity,ownerId=owner,originalOwnerId=owner,capital=false,tileId=tileId,name="Fixture "..s.nextCity,population=1,food=0,production=0,queue="Warrior",hp=Rules.cityHp,buildings={},focus="Balanced"}
    s.nextCity += 1; table.insert(s.cities,c); s.tiles[tileId].ownerId=owner; return c
end

-- The arena: a two-human game on player 1's turn (round 2), every technology known to both, every unit removed (each
-- civilization sees only two hexes around its cities) and a second city for player 1 that player 2 cannot see.
local base=founded(71)
base.units={}
for _, p in base.players do p.technologies=table.clone(Rules.technologyOrder); p.research=nil; p.goldenAge=nil end
local graph=WorldMap.fromTiles(base.tiles,base.radius)
local home,rival=firstCity(base,1),firstCity(base,2)
local spot: number?=nil
for _, t in base.tiles do
    if t.ownerId or not Rules.terrains[t.terrain].passable then continue end
    if WorldMap.distance(graph,t.id,home.tileId)>=3 and WorldMap.distance(graph,t.id,rival.tileId)>=5 then spot=t.id; break end
end
assert(spot,"room for a second city")
local second=addCity(base,1,spot :: number)
assert(WorldMap.distance(graph,home.tileId,rival.tileId)>2,"the rival cannot see player 1's capital")
assert(Save.valid(Game.serialize(base)),"the arena is a valid state")
local baseSave=Game.serialize(base)
local function fresh(): any local s: any=Game.restore(baseSave); assert(s); return s end
-- Ends the actor's turn and checks every own city against the snapshot's forecast taken just before: production gains
-- exactly the forecast (less the cost of a completed item) and, without growth or starvation, food likewise.
local function endTurnChecked(s: any,actor: number): any
    local view=Game.snapshot(s,actor); local before={}
    for _, c in s.cities do if c.ownerId==actor then before[c.id]={food=c.food,production=c.production,population=c.population,queue=c.queue,f=view.cityForecasts[tostring(c.id)]} end end
    apply(s,actor,{kind="EndTurn"})
    for id, b in before do
        local c=cityById(s,id)
        local spent=if b.f.productionTurns==1 then Rules.productionCosts[b.queue] else 0
        assert(c.production==b.production+b.f.production-spent,"production follows the forecast in city "..id)
        if c.population==b.population and b.food+b.f.food>=0 then assert(c.food==b.food+b.f.food,"food follows the forecast in city "..id) end
    end
    return view
end

-- 1. Rules: eight wonders, one per technology, flagged `wonder=true` and placed after the ordinary buildings.
do
    local expected: {{any}}={
        {"HangingGardens","Hanging Gardens",60,"Agriculture"},{"Colossus","Colossus",70,"BronzeWorking"},{"GreatLibrary","Great Library",75,"Writing"},
        {"TerracottaArmy","Terracotta Army",90,"IronWorking"},{"Oracle","Oracle",100,"Philosophy"},{"NotreDame","Notre Dame",120,"CivilService"},
        {"HouseOfWisdom","House of Wisdom",140,"Education"},{"TajMahal","Taj Mahal",170,"Gunpowder"}}
    assert(#Rules.wonderOrder==#expected)
    local techs={}
    for index, row in expected do
        local rule=Rules.buildings[row[1]]
        assert(Rules.wonderOrder[index]==row[1] and rule.wonder==true and rule.name==row[2] and rule.cost==row[3] and rule.technology==row[4] and rule.maintenance==0 and rule.defense==0,row[1])
        assert(Rules.technologies[row[4]] and not techs[row[4]],"one wonder per technology"); techs[row[4]]=true
        assert(Rules.buildingOrder[11+index]==row[1] and Rules.productionCosts[row[1]]==row[3],"wonders follow the ordinary buildings")
    end
    assert(B.HangingGardens.yields.food==2 and B.HangingGardens.globalYields.food==1)
    assert(B.Colossus.yields.gold==3 and B.Colossus.globalYields.gold==1)
    assert(B.GreatLibrary.yields.science==4 and B.GreatLibrary.yields.culture==1)
    assert(B.TerracottaArmy.unitExperience==15 and B.Oracle.policyCostPercent==25 and B.Oracle.yields.culture==3)
    assert(B.NotreDame.happiness==4 and B.HouseOfWisdom.sciencePercent==15 and B.HouseOfWisdom.yields.science==2)
    assert(B.TajMahal.startsGoldenAge==true and B.TajMahal.yields.culture==2)
    for id, rule: any in B do
        if rule.wonder then continue end
        assert(not rule.startsGoldenAge and rule.sciencePercent==0 and rule.policyCostPercent==0 and rule.unitExperience==0 and type(rule.name)=="string",id.." is no wonder")
        for _, value in rule.globalYields do assert(value==0) end
    end
    local g=Rules.goldenAge
    assert(g.threshold==120 and g.thresholdIncrease==60 and g.turns==8 and g.tileGold==1 and g.productionPercent==20 and g.paceTurns==120 and g.minPacePercent==50 and g.maxPacePercent==200)
    assert(Rules.score.wonder==10)
    local rules=Game.getRules(); assert(rules.buildings.TajMahal.wonder==true)
    rules.buildings.TajMahal.cost=1; assert(Game.getRules().buildings.TajMahal.cost==170,"getRules is detached")
end

-- 2. Choosing a wonder: in the production menus once its technology is known, never in the purchase menus, one city per
--    civilization at a time, and a purchase is rejected.
do
    local s=fresh(); s.players[1].gold=100000
    local view=Game.snapshot(s,1)
    for _, id in Rules.wonderOrder do
        assert(has(view.availableProductionByCity[tostring(home.id)],id) and has(view.availableProduction,id),id.." can be chosen")
        assert(not has(view.availablePurchasesByCity[tostring(home.id)],id),id.." is never offered for purchase")
    end
    assert(has(view.availablePurchasesByCity[tostring(home.id)],"Library"),"ordinary buildings can still be bought")
    rejected(s,1,{kind="Purchase",cityId=home.id,item="HangingGardens"},"buying a wonder","World wonders cannot be purchased.")
    local early=fresh(); early.players[1].technologies={}
    assert(not has(Game.snapshot(early,1).availableProduction,"HangingGardens"),"a wonder needs its technology")
    rejected(early,1,{kind="SetProduction",cityId=home.id,item="HangingGardens"},"a wonder without its technology","Production item is unavailable.")
    apply(s,1,{kind="SetProduction",cityId=home.id,item="HangingGardens"})
    view=Game.snapshot(s,1)
    assert(not has(view.availableProductionByCity[tostring(second.id)],"HangingGardens"),"one city at a time races for a wonder")
    assert(has(view.availableProductionByCity[tostring(second.id)],"Colossus"))
    rejected(s,1,{kind="SetProduction",cityId=second.id,item="HangingGardens"},"a second city for the same wonder","Production item is unavailable.")
    -- The rival's own choice is unaffected by player 1's queue (it cannot see it).
    apply(s,1,{kind="EndTurn"})
    assert(has(Game.snapshot(s,2).availableProductionByCity[tostring(rival.id)],"HangingGardens"))
end

-- 3. Once per world: the first completion removes the wonder from every menu, every other city racing for it keeps its
--    production for the next item (queue Warrior) with a private WonderLost event, and nothing more completes there
--    in the same step. The forecast predicts the lost race.
do
    local s=fresh()
    local h,sc,rv=cityById(s,home.id),cityById(s,second.id),cityById(s,rival.id)
    h.queue="HangingGardens"; h.production=59
    -- A hand-made second racer in player 1's later city (the menus would not allow it) and the rival's city.
    sc.queue="HangingGardens"; sc.production=70
    rv.queue="HangingGardens"; rv.production=50
    assert(Save.valid(Game.serialize(s)),"two racing cities are a valid state")
    local view=Game.snapshot(s,1)
    assert(view.cityForecasts[tostring(home.id)].productionTurns==1,"the capital completes the wonder")
    local f=view.cityForecasts[tostring(second.id)]
    assert(f.productionTurns==nil and f.productionBlocked=="NotAvailable","the later city's race is forecast as lost")
    local mark=s.nextEvent-1
    endTurnChecked(s,1)
    assert(has(h.buildings,"HangingGardens") and h.queue=="Warrior")
    assert(sc.queue=="Warrior" and sc.production==70+f.production,"the losing city keeps its production and completes nothing")
    assert(rv.queue=="Warrior" and rv.production==50,"the rival keeps its production for its next item")
    local built=eventsOf(s.events,"WonderBuilt",mark)
    assert(#built==1 and built[1].public==true and built[1].ownerId==1 and built[1].wonder=="HangingGardens" and built[1].cityId==home.id and built[1].tileId==home.tileId)
    local lost=eventsOf(s.events,"WonderLost",mark)
    assert(#lost==2,"two lost races")
    -- In city id order: the rival's capital (id 2), then player 1's second city (id 3).
    assert(rival.id<second.id)
    assert(lost[1].cityId==rival.id and lost[1].ownerId==2 and lost[1].byOwnerId==1 and lost[1].amount==50 and lost[1].tileId==nil and not lost[1].public)
    assert(lost[2].cityId==second.id and lost[2].ownerId==1 and lost[2].byOwnerId==1 and lost[2].amount==70 and lost[2].tileId==nil and lost[2].wonder=="HangingGardens")
    for owner=1,2 do
        local v=Game.snapshot(s,owner)
        assert(not has(v.availableProduction,"HangingGardens"),"a built wonder leaves every menu")
        assert(#v.wonders==1 and v.wonders[1].id=="HangingGardens" and v.wonders[1].ownerId==1)
        assert(#eventsOf(v.events,"WonderLost")==1,"each owner sees only its own lost race")
        for _, e in eventsOf(v.events,"WonderLost") do assert(e.ownerId==owner) end
    end
    rejected(s,2,{kind="SetProduction",cityId=rival.id,item="HangingGardens"},"a built wonder","Production item is unavailable.")
    -- Validation: a completed wonder in a second city, or a queue on a completed wonder, is rejected.
    local saved=Game.serialize(s)
    local dup=Game.serialize(s); for _, c in dup.state.cities do if c.id==rival.id then table.insert(c.buildings,"HangingGardens") end end
    assert(not Save.valid(dup),"a wonder in two cities")
    local queued=Game.serialize(s); for _, c in queued.state.cities do if c.id==rival.id then c.queue="HangingGardens" end end
    assert(not Save.valid(queued),"a queue on a completed wonder")
    assert(Save.valid(saved))
    -- The rival's next step completes nothing from the lost race: it has a full turn to choose (here a Library).
    apply(s,2,{kind="SetProduction",cityId=rival.id,item="Library"})
    endTurnChecked(s,2)
    assert(has(rv.buildings,"Library"),"the kept production finishes the next item")
end

-- 4. Each wonder's effect against the forecast and the applied step. Effects serve the civilization holding the city.
local function forecastDelta(wonder: string, holderId: number?): (any, any, any, any)
    local s=fresh(); local v0=Game.snapshot(s,1)
    table.insert(cityById(s,holderId or home.id).buildings,wonder)
    local v1=Game.snapshot(s,1)
    local function delta(id: number): any
        local a,b=v0.cityForecasts[tostring(id)],v1.cityForecasts[tostring(id)]
        return {food=b.food-a.food,production=b.production-a.production,gold=b.gold-a.gold,science=b.science-a.science,culture=b.culture-a.culture}
    end
    return delta(home.id),delta(second.id),v0,v1
end
do
    local h,o=forecastDelta("HangingGardens")
    assert(equal(h,{food=3,production=0,gold=0,science=0,culture=0}) and equal(o,{food=1,production=0,gold=0,science=0,culture=0}),"Hanging Gardens: +2 food here and +1 food in every city")
    h,o=forecastDelta("Colossus")
    assert(equal(h,{food=0,production=0,gold=4,science=0,culture=0}) and equal(o,{food=0,production=0,gold=1,science=0,culture=0}),"Colossus")
    h,o=forecastDelta("GreatLibrary")
    assert(equal(h,{food=0,production=0,gold=0,science=4,culture=1}) and equal(o,{food=0,production=0,gold=0,science=0,culture=0}),"Great Library")
    h,o=forecastDelta("Oracle"); assert(h.culture==3 and o.culture==0,"Oracle culture")
    h,o=forecastDelta("NotreDame"); assert(h.culture==2 and o.culture==0,"Notre Dame culture")
    h,o=forecastDelta("TajMahal"); assert(h.culture==2 and o.culture==0,"Taj Mahal culture")
    h,o=forecastDelta("TerracottaArmy"); assert(equal(h,{food=0,production=0,gold=0,science=0,culture=0}) and equal(o,h),"Terracotta Army changes no yields")
    -- House of Wisdom: +2 science here, then +15% (rounded down) of every city's science.
    local _,_,v0,v1=forecastDelta("HouseOfWisdom")
    for _, id: number in {home.id,second.id} do
        local before=v0.cityForecasts[tostring(id)].science; local after=v1.cityForecasts[tostring(id)].science
        local expectedBase=before+(if id==home.id then 2 else 0)
        assert(after==math.floor(expectedBase*115/100),"House of Wisdom science in city "..id)
    end
    -- Notre Dame: +4 happiness for the owner (the meter's next gain shows it).
    do
        local s=fresh(); local mood=Game.snapshot(s,1).goldenAge.progressPerTurn
        table.insert(cityById(s,home.id).buildings,"NotreDame")
        assert(Game.snapshot(s,1).goldenAge.progressPerTurn==mood+4)
        apply(s,1,{kind="SetCityFocus",cityId=home.id,focus="Food"}); assert(s.players[1].happiness==Game.snapshot(fresh(),1).goldenAge.progressPerTurn+4)
    end
    -- Oracle: every policy costs 25% less (after escalation, rounded down), in the menu and when adopted.
    do
        local s=fresh(); s.players[1].culture=1000; s.players[1].policies={"Tradition"}
        local plain=Game.snapshot(s,1).availablePolicies
        table.insert(cityById(s,home.id).buildings,"Oracle")
        local cheap=Game.snapshot(s,1).availablePolicies
        assert(#plain==#cheap)
        for index, entry in plain do assert(cheap[index].id==entry.id and cheap[index].cost==math.floor(entry.cost*75/100),"Oracle discount on "..entry.id) end
        local liberty: any=nil; for _, entry in cheap do if entry.id=="Liberty" then liberty=entry end end
        apply(s,1,{kind="AdoptPolicy",policy="Liberty"}); assert(s.players[1].culture==1000-liberty.cost and liberty.cost==math.floor(37*75/100))
    end
    -- Terracotta Army: new military units, built or bought, start with 15 experience (one promotion ready); civilians none.
    do
        local s=fresh(); s.players[1].gold=100000
        table.insert(cityById(s,home.id).buildings,"TerracottaArmy")
        apply(s,1,{kind="Purchase",cityId=second.id,item="Warrior"})
        local warrior=s.units[#s.units]; assert(warrior.kind=="Warrior" and warrior.xp==15)
        local own: any=nil; for _, u in Game.snapshot(s,1).units do if u.id==warrior.id then own=u end end
        assert(own.xp==15 and #own.promotionsAvailable>0,"a promotion is ready at once")
        apply(s,1,{kind="Purchase",cityId=home.id,item="Worker"}); assert(s.units[#s.units].kind=="Worker" and s.units[#s.units].xp==nil)
        local hs=cityById(s,home.id); hs.queue="Archer"; hs.production=17
        apply(s,1,{kind="EndTurn"})
        local archer=s.units[#s.units]; assert(archer.kind=="Archer" and archer.xp==15 and archer.ownerId==1,"built units too")
        local plain=fresh(); plain.players[1].gold=1000; apply(plain,1,{kind="Purchase",cityId=home.id,item="Warrior"}); assert(plain.units[#plain.units].xp==nil)
        assert(Save.valid(Game.serialize(s)))
    end
    -- Wonders follow the city: when the rival holds the city, the effects serve the rival and the score counts for it.
    do
        local s=fresh(); table.insert(cityById(s,second.id).buildings,"HangingGardens")
        local mine=Game.snapshot(s,1); local theirs=Game.snapshot(s,2)
        local c=cityById(s,second.id); c.ownerId=2; s.tiles[c.tileId].ownerId=2
        local after=Game.snapshot(s,2)
        assert(after.cityForecasts[tostring(rival.id)].food==theirs.cityForecasts[tostring(rival.id)].food+1,"the captor's cities gain the global food")
        assert(Game.snapshot(s,1).cityForecasts[tostring(home.id)].food==mine.cityForecasts[tostring(home.id)].food-1,"the loser's cities lose it")
        assert(after.wonders[1].ownerId==2)
    end
    -- Score: each wonder counts 10 for its holder.
    do
        local s=fresh(); local score=Game.snapshot(s,1).scores[1]
        table.insert(cityById(s,home.id).buildings,"Colossus"); table.insert(cityById(s,second.id).buildings,"Oracle")
        assert(Game.snapshot(s,1).scores[1]==score+20)
    end
    -- A completed wonder takes effect from its owner's next step: the step that completes it matches the forecast taken
    -- without it, and the next step's forecast includes it.
    do
        local s=fresh(); local builder=cityById(s,home.id); builder.queue="HangingGardens"; builder.production=59
        local before=endTurnChecked(s,1)
        assert(has(builder.buildings,"HangingGardens"))
        apply(s,2,{kind="EndTurn"})
        local with=Game.snapshot(s,1).cityForecasts[tostring(second.id)].food
        table.remove(builder.buildings,table.find(builder.buildings,"HangingGardens") :: number)
        local without=Game.snapshot(s,1).cityForecasts[tostring(second.id)].food
        table.insert(builder.buildings,"HangingGardens")
        assert(with==without+1,"the next step's forecast includes the global food")
        -- The step that follows applies exactly that forecast.
        endTurnChecked(s,1)
        assert(before.cityForecasts[tostring(home.id)].productionTurns==1)
    end
end

-- 5. Golden ages: the meter fills with positive happiness, the threshold starts a golden age that boosts gold tiles and
--    production for eight owner steps, nothing fills the meter during it, it ends with an event, and the next threshold
--    is higher. Golden-age events and fields are private.
local function goldenArena(): any
    local s=fresh(); local h=cityById(s,home.id)
    -- The capital works a Gold hill (2 gold) on its Gold focus; a Workshop makes the production gain visible.
    for _, id in WorldMap.range(graph,home.tileId,2) do local t=s.tiles[id]; if id~=home.tileId and Rules.terrains[t.terrain].passable then t.terrain="Plains"; t.resource=nil; t.improvement=nil; t.road=nil end end
    local hill=nil; for _, id in graph.neighbors[home.tileId] do if s.tiles[id].ownerId==1 and Rules.terrains[s.tiles[id].terrain].passable then hill=id; break end end
    assert(hill,"a hill for the gold mine"); s.tiles[hill].terrain="Hills"; s.tiles[hill].resource="Gold"
    h.focus="Gold"; h.buildings={"Workshop"}
    assert(Save.valid(Game.serialize(s)))
    return s
end
do
    local s=goldenArena()
    local view=Game.snapshot(s,1)
    local gain=view.goldenAge.progressPerTurn
    assert(gain>0 and view.goldenAge.active==false and view.goldenAge.turnsLeft==0 and view.goldenAge.progress==0 and view.goldenAge.threshold==120 and view.goldenAge.ages==0 and view.goldenAge.turns==8)
    -- One step fills the meter by the step's happiness.
    endTurnChecked(s,1)
    assert(s.players[1].goldenAge and s.players[1].goldenAge.progress==gain and s.players[1].goldenAge.turnsLeft==0,"the meter fills")
    assert(Game.snapshot(s,1).goldenAge.progress==gain)
    apply(s,2,{kind="EndTurn"})
    -- One short of the threshold: the next step starts a golden age and keeps the remainder.
    s.players[1].goldenAge={progress=120-gain+3,turnsLeft=0,ages=0}
    local plain=Game.snapshot(s,1).cityForecasts[tostring(home.id)]
    local mark=s.nextEvent-1
    endTurnChecked(s,1)
    local g=s.players[1].goldenAge
    assert(g.turnsLeft==8 and g.ages==1 and g.progress==3,"the golden age begins and keeps the remainder")
    local started=eventsOf(s.events,"GoldenAgeStarted",mark)
    assert(#started==1 and started[1].ownerId==1 and started[1].amount==8 and started[1].cause=="Happiness" and started[1].tileId==nil and not started[1].public)
    assert(#eventsOf(Game.snapshot(s,2).events,"GoldenAgeStarted")==0,"the rival is not told")
    local view2=Game.snapshot(s,2); assert(view2.goldenAge.active==false and view2.goldenAge.ages==0,"the rival's own record")
    view=Game.snapshot(s,1)
    assert(view.goldenAge.active and view.goldenAge.turnsLeft==8 and view.goldenAge.threshold==180 and view.goldenAge.progressPerTurn==0 and view.goldenAge.ages==1)
    -- Its effects: +1 gold on the centre and on the worked Gold hill, +20% production (rounded down).
    local golden=view.cityForecasts[tostring(home.id)]
    assert(golden.gold==plain.gold+2,"one more gold on the centre and on the gold tile")
    assert(golden.production==math.floor(plain.production*120/100) and golden.production>plain.production,"twenty percent more production")
    assert(golden.food==plain.food and golden.science==plain.science and golden.culture==plain.culture)
    local secondPlain=Game.snapshot(fresh(),1).cityForecasts[tostring(second.id)]
    local secondGolden=view.cityForecasts[tostring(second.id)]
    assert(secondGolden.production==math.floor(secondPlain.production*120/100) and secondGolden.gold>=secondPlain.gold+1,"every city")
    -- Eight steps (each matching its forecast), no meter gain during them, then the end event.
    apply(s,2,{kind="EndTurn"})
    for step=1,8 do
        mark=s.nextEvent-1
        endTurnChecked(s,1)
        assert(s.players[1].goldenAge.progress==3,"no meter gain during a golden age")
        assert(s.players[1].goldenAge.turnsLeft==8-step)
        assert(#eventsOf(s.events,"GoldenAgeEnded",mark)==(if step==8 then 1 else 0))
        apply(s,2,{kind="EndTurn"})
    end
    assert(Game.snapshot(s,1).goldenAge.active==false)
    assert(Game.snapshot(s,1).cityForecasts[tostring(home.id)].production==plain.production,"the bonus ends with the age")
    local ended=eventsOf(s.events,"GoldenAgeEnded"); assert(ended[#ended].ownerId==1 and #eventsOf(Game.snapshot(s,2).events,"GoldenAgeEnded")==0)
    -- The meter fills again, toward the higher threshold.
    local gainNow=Game.snapshot(s,1).goldenAge.progressPerTurn
    endTurnChecked(s,1); assert(s.players[1].goldenAge.progress==3+gainNow)
    -- Unhappiness never drains the meter.
    local sad=fresh(); sad.players[1].goldenAge={progress=40,turnsLeft=0,ages=2}
    for _, c in sad.cities do if c.ownerId==1 then c.population=12 end end
    assert(Game.snapshot(sad,1).goldenAge.progressPerTurn==0 and Game.snapshot(sad,1).goldenAge.threshold==240)
    apply(sad,1,{kind="EndTurn"}); assert(sad.players[1].happiness<0 and sad.players[1].goldenAge.progress==40)
end

-- 6. Thresholds and length scale with the round limit; every golden age raises the next threshold.
do
    local paces: {{any}}={{120,8,{120,180,240}},{60,4,{60,90,120}},{20,4,{60,90,120}},{150,10,{150,225,300}},{240,16,{240,360,480}},{500,16,{240,360,480}}}
    for _, row in paces do
        local s=Game.new(9,{maxTurns=row[1]})
        for ages, threshold in row[3] do
            s.players[1].goldenAge={progress=0,turnsLeft=0,ages=ages-1}
            local g=Game.snapshot(s,1).goldenAge
            assert(g.turns==row[2] and g.threshold==threshold,"pace "..row[1].." age "..ages..": "..g.turns.."/"..g.threshold)
        end
    end
end

-- 7. Taj Mahal starts a golden age when completed (from the next step), or extends one already running.
do
    local s=goldenArena(); local h=cityById(s,home.id)
    h.queue="TajMahal"; h.production=169
    local mark=s.nextEvent-1
    local plain=endTurnChecked(s,1)
    assert(plain.goldenAge.active==false and has(h.buildings,"TajMahal"))
    local g=s.players[1].goldenAge; assert(g.turnsLeft==8 and g.ages==1,"the wonder starts a golden age")
    local started=eventsOf(s.events,"GoldenAgeStarted",mark)
    assert(#started==1 and started[1].cause=="Wonder" and started[1].wonder=="TajMahal" and started[1].amount==8)
    assert(g.progress==plain.goldenAge.progressPerTurn,"the meter still filled in that step")
    apply(s,2,{kind="EndTurn"})
    assert(Game.snapshot(s,1).goldenAge.active)
    endTurnChecked(s,1); assert(s.players[1].goldenAge.turnsLeft==7)
    -- Extension: three steps left, then the wonder adds eight more with no new start event and no new age counted.
    local t=goldenArena(); t.players[1].goldenAge={progress=10,turnsLeft=3,ages=1}
    local th=cityById(t,home.id); th.queue="TajMahal"; th.production=169
    mark=t.nextEvent-1
    endTurnChecked(t,1)
    assert(equal(t.players[1].goldenAge,{progress=10,turnsLeft=10,ages=1}),"the golden age is extended")
    assert(#eventsOf(t.events,"GoldenAgeStarted",mark)==0 and #eventsOf(t.events,"GoldenAgeEnded",mark)==0 and #eventsOf(t.events,"WonderBuilt",mark)==1)
    -- Extension of a final step: the age that would have ended continues.
    local u=goldenArena(); u.players[1].goldenAge={progress=0,turnsLeft=1,ages=1}
    local uh=cityById(u,home.id); uh.queue="TajMahal"; uh.production=169
    mark=u.nextEvent-1
    endTurnChecked(u,1)
    assert(u.players[1].goldenAge.turnsLeft==8 and #eventsOf(u.events,"GoldenAgeEnded",mark)==0)
    -- In a shorter match the wonder's golden age is shorter too.
    local quick=founded(71,{maxTurns=60}); quick.units={}
    for _, p in quick.players do p.technologies=table.clone(Rules.technologyOrder); p.research=nil end
    local qh=firstCity(quick,1); qh.queue="TajMahal"; qh.production=169
    apply(quick,1,{kind="EndTurn"}); assert(quick.players[1].goldenAge.turnsLeft==4)
end

-- 8. Fog: everyone learns that a wonder was completed and by whom, but the city only while it can see it. Changing which
--    unseen city holds the wonder changes nothing in the rival's projection.
do
    local function build(cityId: number): any
        local s=fresh(); local c=cityById(s,cityId); c.queue="Colossus"; c.production=69
        apply(s,1,{kind="EndTurn"}); return s
    end
    local a,b=build(home.id),build(second.id)
    local va,vb=Game.snapshot(a,2),Game.snapshot(b,2)
    assert(equal(va,vb),"which unseen city holds the wonder is invisible to the rival")
    local e=eventsOf(va.events,"WonderBuilt")
    assert(#e==1 and e[1].ownerId==1 and e[1].wonder=="Colossus" and e[1].public and e[1].tileId==nil and e[1].cityId==nil,"public news without a location")
    assert(equal(va.wonders,{{id="Colossus",ownerId=1}}),"the wonder list has no location either")
    assert(#eventsOf(va.events,"Production")==0,"the builder's production event stays private")
    -- The builder sees its own city.
    local own=Game.snapshot(a,1)
    assert(equal(own.wonders,{{id="Colossus",ownerId=1,cityId=home.id,tileId=home.tileId,cityName=home.name}}))
    local ownEvent=eventsOf(own.events,"WonderBuilt")[1]; assert(ownEvent.cityId==home.id and ownEvent.tileId==home.tileId)
    -- A rival scout next to the city reveals it, in the list and in the event.
    local near: number?=nil; for _, id in graph.neighbors[home.tileId] do if Rules.terrains[a.tiles[id].terrain].passable then near=id; break end end
    assert(near); table.insert(a.units,{id=a.nextUnit,ownerId=2,kind="Scout",tileId=near,hp=60,moves=3,fortified=false,level=0}); a.nextUnit += 1
    local seen=Game.snapshot(a,2)
    assert(equal(seen.wonders,{{id="Colossus",ownerId=1,cityId=home.id,tileId=home.tileId,cityName=home.name}}),"a visible city shows its wonder")
    local seenEvent=eventsOf(seen.events,"WonderBuilt")[1]; assert(seenEvent.cityId==home.id and seenEvent.tileId==home.tileId)
    -- Each actor's golden age is its own: no rival field reveals player 1's meter.
    a.players[1].goldenAge={progress=99,turnsLeft=5,ages=2}
    local rivalView=Game.snapshot(a,2); assert(rivalView.goldenAge.progress==0 and not rivalView.goldenAge.active)
end

-- 9. Saves: a save written before G8 (no golden-age record, no wonder) restores unchanged through both paths and plays on;
--    G8 fields round-trip and are validated case by case.
do
    local legacy=Game.serialize(fresh())
    for _, p in legacy.state.players do assert(p.goldenAge==nil) end
    assert(Save.valid(legacy))
    local restored: any=Game.restore(legacy); assert(restored and equal(Game.serialize(restored),legacy),"restore adds no field")
    local viaSave: any=Save.restore(legacy); assert(viaSave and equal(viaSave,legacy.state))
    local v=Game.snapshot(restored,1); assert(v.goldenAge.progress==0 and v.goldenAge.ages==0 and #v.wonders==0)
    apply(restored,1,{kind="EndTurn"}); assert(restored.players[1].goldenAge.progress>0,"the meter starts filling after loading")
    -- A game whose civilization never has positive happiness writes no record.
    local sad: any=Game.restore(legacy); for _, c in sad.cities do c.population=12 end
    apply(sad,1,{kind="EndTurn"}); apply(sad,2,{kind="EndTurn"}); for _, p in sad.players do assert(p.goldenAge==nil) end
    -- Round trip with wonders, a lost race and golden-age records.
    local s=goldenArena(); local h=cityById(s,home.id); h.queue="TajMahal"; h.production=169
    local rv=cityById(s,rival.id); rv.queue="TajMahal"; rv.production=30
    apply(s,1,{kind="EndTurn"})
    local saved=Game.serialize(s)
    local again: any=Game.restore(saved); assert(again and equal(Game.serialize(again),saved),"G8 fields round-trip")
    local function variant(change: (any)->()): any local value=Game.serialize(s); change(value.state); return value end
    local function accepts(change: (any)->(),label: string) assert(Save.valid(variant(change)),label.." rejected") end
    local function rejects(change: (any)->(),label: string)
        local value=variant(change); assert(not Save.valid(value),label.." accepted")
        local loaded,message=Save.restore(value); assert(loaded==nil and type(message)=="string"); assert(Game.restore(value)==nil)
    end
    accepts(function(st) st.players[2].goldenAge={progress=0,turnsLeft=0,ages=0} end,"an empty record")
    accepts(function(st) st.players[2].goldenAge={progress=500,turnsLeft=16,ages=3} end,"an active record")
    accepts(function(st) st.players[1].goldenAge=nil end,"no record")
    rejects(function(st) st.players[2].goldenAge={progress=-1,turnsLeft=0,ages=0} end,"negative progress")
    rejects(function(st) st.players[2].goldenAge={progress=1.5,turnsLeft=0,ages=0} end,"fractional progress")
    rejects(function(st) st.players[2].goldenAge={progress=0,turnsLeft=1001,ages=1} end,"too many turns")
    rejects(function(st) st.players[2].goldenAge={progress=0,turnsLeft=2,ages=0} end,"an active age that was never begun")
    rejects(function(st) st.players[2].goldenAge={progress=0,turnsLeft=0} end,"a missing field")
    rejects(function(st) st.players[2].goldenAge={progress=0,turnsLeft=0,ages=0,active=true} end,"a derived field")
    rejects(function(st) st.players[2].goldenAge="golden" end,"a text record")
    rejects(function(st) table.insert(st.cities[2].buildings,"TajMahal") end,"a wonder in two cities")
    rejects(function(st) for _, c in st.cities do if c.id==second.id then c.queue="TajMahal" end end end,"a queue on a completed wonder")
    accepts(function(st) for _, c in st.cities do if c.id==second.id then c.queue="Oracle" end end end,"a queue on an open wonder")
    local function eventOf(st: any,kind: string): any for _, e in st.events do if e.kind==kind then return e end end; error("no "..kind) end
    accepts(function(st) eventOf(st,"WonderLost").wonder="Oracle" end,"another wonder id")
    rejects(function(st) eventOf(st,"WonderBuilt").wonder="Library" end,"an ordinary building as a wonder")
    rejects(function(st) eventOf(st,"WonderBuilt").wonder="Pyramid" end,"an unknown wonder")
    rejects(function(st) eventOf(st,"WonderBuilt").wonder=3 end,"a numeric wonder")
    rejects(function(st) eventOf(st,"GoldenAgeStarted").cause="Luck" end,"an unknown cause")
    rejects(function(st) eventOf(st,"GoldenAgeStarted").kind="GoldenAgeBegan" end,"an unknown kind")
    for _, kind in {"WonderBuilt","WonderLost","GoldenAgeStarted"} do assert(eventOf(saved.state,kind)) end
end

-- 10. The AI: one wonder at a time in its most productive city, only when it can finish within 30 turns at its rate; it
--     keeps a wonder it is building, re-plans after losing a race, and never leaves a queue on a completed wonder.
do
    local s: any=Game.new(23,{humanPlayers=1,radius=10,difficulty="Easy"})
    for _, t in s.tiles do t.feature=nil; t.river=nil end
    apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id})
    -- Every technology but Rocketry (which would put the Space Project first).
    for _, p in s.players do p.technologies=table.move(Rules.technologyOrder,1,#Rules.technologyOrder-1,1,{}); p.research=nil end
    local g2=WorldMap.fromTiles(s.tiles,s.radius)
    -- Three AI cities (so it trains no settler), each on Tundra with every core building and 14 citizens, and an AI worker
    -- (so it trains no worker): the AI's next choice after its core buildings is a wonder or a military unit.
    local aiCities={firstCity(s,2)}
    while #aiCities<3 do
        local far: number?=nil
        for _, t in s.tiles do
            if t.ownerId or not Rules.terrains[t.terrain].passable then continue end
            local ok=true; for _, c in s.cities do if WorldMap.distance(g2,t.id,c.tileId)<5 then ok=false end end
            if ok then far=t.id; break end
        end
        assert(far,"room for another AI city"); table.insert(aiCities,addCity(s,2,far :: number))
    end
    for _, c in aiCities do
        for _, id in WorldMap.range(g2,c.tileId,2) do
            local t=s.tiles[id]; if Rules.terrains[t.terrain].passable then t.terrain="Tundra"; t.resource=nil; t.improvement=nil; t.road=nil end
            if t.ownerId==nil then t.ownerId=2 end
        end
        c.buildings={"Monument","Granary","Library","Market","Workshop","University"}; c.population=14; c.food=0; c.production=0
    end
    local capital=aiCities[1]
    s.units={{id=s.nextUnit,ownerId=2,kind="Worker",tileId=capital.tileId,hp=50,moves=0,fortified=false,level=0}}; s.nextUnit += 1
    assert(Save.valid(Game.serialize(s)))
    -- Unhappy (-5 or worse) and on Easy, each city makes 1 production: 60 turns for the cheapest wonder is too slow.
    for _, c in aiCities do assert(Game.snapshot(s,2).cityForecasts[tostring(c.id)].production==1,"an AI city makes 1 production") end
    local slow=Game.restore(Game.serialize(s)) :: any
    apply(slow,1,{kind="EndTurn"})
    for _, c in slow.cities do if c.ownerId==2 then assert(Rules.units[c.queue] and Rules.units[c.queue].strength>0,"no wonder it cannot finish: a military unit instead") end end
    -- With 40 production stored in the capital, 20 turns remain there: it races for the earliest wonder, and keeps racing.
    local able=Game.restore(Game.serialize(s)) :: any; cityById(able,capital.id).production=40
    apply(able,1,{kind="EndTurn"})
    assert(cityById(able,capital.id).queue=="HangingGardens","the earliest wonder it can finish")
    apply(able,1,{kind="EndTurn"}); assert(cityById(able,capital.id).queue=="HangingGardens","it keeps racing")
    -- The human completes it first: the AI keeps its production and plans the next wonder it can finish (Colossus:
    -- 70 less 42 stored is 28 turns).
    local mine=firstCity(able,1); mine.queue="HangingGardens"; mine.production=60
    local stored=cityById(able,capital.id).production; assert(stored==42)
    local mark=able.nextEvent-1
    apply(able,1,{kind="EndTurn"})
    local raced=cityById(able,capital.id)
    assert(has(mine.buildings,"HangingGardens") and raced.queue=="Colossus" and raced.production==stored+1,"a lost race re-plans and keeps production")
    local lost=eventsOf(able.events,"WonderLost",mark); assert(#lost==1 and lost[1].ownerId==2 and lost[1].amount==42 and lost[1].cityId==capital.id)
    -- The most productive city races: Hills around the third city lift its production; the others train units.
    local hills=Game.restore(Game.serialize(s)) :: any; local rich=cityById(hills,aiCities[3].id)
    for _, id in WorldMap.range(g2,rich.tileId,2) do local t=hills.tiles[id]; if Rules.terrains[t.terrain].passable then t.terrain="Hills" end end
    apply(hills,1,{kind="EndTurn"})
    for _, c in hills.cities do
        if c.ownerId~=2 then continue end
        local isWonder=Rules.buildings[c.queue]~=nil and Rules.buildings[c.queue].wonder
        assert(isWonder==(c.id==rich.id),"only the productive city races (city "..c.id..": "..c.queue..")")
    end
end

-- 11. Determinism and full AI games: solo games in which the AI races for wonders and both civilizations have golden
--     ages replay identically with and without saves between turns. After every turn no queue sits on a completed
--     wonder and the AI races in at most one city.
do
    local function run(seed: number, resume: boolean): (any,number,number)
        local s: any=Game.new(seed,{humanPlayers=1,radius=10,difficulty="Normal"})
        apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id})
        local wonders,ages=0,0; local seenEvent=s.nextEvent-1
        for turn=1,90 do
            if s.phase~="Playing" then break end
            local view=Game.snapshot(s,1)
            if not s.players[1].research and #view.availableResearch>0 then apply(s,1,{kind="Research",technology=view.availableResearch[1].id}) end
            -- The human races for the first wonder its capital may choose.
            local city=firstCity(s,1)
            if not Rules.buildings[city.queue] or not Rules.buildings[city.queue].wonder then
                for _, id in view.availableProductionByCity[tostring(city.id)] do if Rules.buildings[id] and Rules.buildings[id].wonder then apply(s,1,{kind="SetProduction",cityId=city.id,item=id}); break end end
            end
            apply(s,1,{kind="EndTurn"})
            for _, e in s.events do
                if e.id>seenEvent then
                    if e.kind=="WonderBuilt" then wonders += 1 elseif e.kind=="GoldenAgeStarted" then ages += 1 end
                end
            end
            seenEvent=s.nextEvent-1
            local built={}; for _, c in s.cities do for _, b in c.buildings do if Rules.buildings[b].wonder then assert(not built[b],"once per world"); built[b]=true end end end
            local racing=0
            for _, c in s.cities do
                assert(not built[c.queue],"no queue on a completed wonder")
                if c.ownerId==2 and Rules.buildings[c.queue] and Rules.buildings[c.queue].wonder then racing += 1 end
            end
            assert(racing<=1,"the AI races in one city at a time")
            if resume then s=Game.restore(Game.serialize(s)) end
        end
        return Game.serialize(s),wonders,ages
    end
    local totalWonders,totalAges=0,0
    for _, seed in {3,42} do
        local first,wonders,ages=run(seed,false); local again=run(seed,false); local resumed=run(seed,true)
        assert(equal(first,again) and equal(first,resumed),"wonders and golden ages are deterministic (seed "..seed..")")
        totalWonders += wonders; totalAges += ages
        print(string.format("  seed %d: %d wonders built, %d golden ages, phase %s at turn %d",seed,wonders,ages,first.state.phase,first.state.turn))
    end
    assert(totalWonders>=4 and totalAges>=2,"the replays must include wonders and golden ages")
end

print("base wonders: wonder rules, once-per-world completion and kept production, each wonder's effect, golden-age meter, effects, expiry, threshold growth and pacing, Taj Mahal ages, fog, legacy saves and validation, AI wonder plans and determinism passed")
