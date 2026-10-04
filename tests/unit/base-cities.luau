--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original fixtures for founding-order city names and the per-city forecast in snapshots.
local Game = require("../../src/simulation/BaseGame")
local Save = require("../../src/simulation/BaseSave")
local WorldMap = require("../../src/simulation/WorldMap")
local Rules = require("../../src/simulation/BaseRules")
local function apply(s: any,owner: number,command: any)
    local result=Game.apply(s,owner,command); assert(result.ok,result.message)
end
local function firstUnit(s: any,owner: number,kind: string): any
    for _, u in s.units do if u.ownerId==owner and u.kind==kind then return u end end; error("missing "..kind)
end
local function cityAt(s: any,tileId: number): any
    for _, c in s.cities do if c.tileId==tileId then return c end end; error("missing city")
end

-- 1. Each civilization names its cities in founding order (capture only changes the owner, never the name).
do
    local s: any=Game.new(41,{humanPlayers=2,radius=8})
    local settler=firstUnit(s,1,"Settler"); local home=settler.tileId
    apply(s,1,{kind="FoundCity",unitId=settler.id}); apply(s,1,{kind="EndTurn"})
    local rival=firstUnit(s,2,"Settler"); local rivalHome=rival.tileId
    apply(s,2,{kind="FoundCity",unitId=rival.id}); apply(s,2,{kind="EndTurn"})
    assert(cityAt(s,home).name=="Sunhaven" and cityAt(s,home).capital,"civilization 1's capital")
    assert(cityAt(s,rivalHome).name=="Ironcliff","civilization 2's capital")
    -- A second settler far from every city founds the next name on the list.
    local graph=WorldMap.fromTiles(s.tiles,s.radius); local used={}
    for _, u in s.units do used[u.tileId]=true end
    local spot
    for _, tile in s.tiles do
        if used[tile.id] or tile.ownerId or not Rules.terrains[tile.terrain].passable then continue end
        local far=true; for _, c in s.cities do if WorldMap.distance(graph,tile.id,c.tileId)<5 then far=false end end
        if far then spot=tile.id; break end
    end
    assert(spot,"no free site")
    local second=firstUnit(s,1,"Worker"); second.kind="Settler"; second.tileId=spot; second.moves=2
    apply(s,1,{kind="FoundCity",unitId=second.id})
    assert(cityAt(s,spot).name=="Brightwater" and not cityAt(s,spot).capital)
    assert(Save.valid(Game.serialize(s)))
    -- Names come from the snapshot unchanged, and only seen rival cities appear.
    local view=Game.snapshot(s,1)
    for _, c in view.cities do assert(c.name~=nil and string.sub(c.name,1,5)~="City ") end
end

-- 2. The forecast is the economy's own calculation: next turn adds exactly the forecast food and production.
do
    for _, seed in {42,43,44,45} do
        local s=Game.new(seed,{radius=6})
        local settler=firstUnit(s,1,"Settler"); local home=settler.tileId
        apply(s,1,{kind="FoundCity",unitId=settler.id})
        local city=cityAt(s,home)
        local view=Game.snapshot(s,1)
        local forecast=view.cityForecasts[tostring(city.id)]
        assert(forecast and forecast.production>0 and forecast.productionTurns and forecast.productionTurns>=1,"forecast for the new city")
        local food,production,population=city.food,city.production,city.population
        apply(s,1,{kind="EndTurn"})
        if city.population==population then assert(city.food-food==math.max(forecast.food,-food),"food forecast matches seed "..seed) end
        local cost=view.productionCosts[city.queue]
        if production+forecast.production<cost then assert(city.production-production==forecast.production,"production forecast matches seed "..seed) end
        if forecast.growthTurns then assert(forecast.food>0) end
        -- Rival cities never get a forecast.
        for id in Game.snapshot(s,1).cityForecasts do local c=nil; for _, other in s.cities do if tostring(other.id)==id then c=other end end; assert(c and c.ownerId==1) end
    end
end
-- Ends the actor's turn and asserts every own city changed exactly as the snapshot forecast said:
-- growth iff growthTurns==1, completion iff productionTurns==1, never while productionBlocked.
-- Returns whether a city of population 3+ still has unowned tiles in its work radius.
local function endTurnMatchesForecast(s: any,actor: number): boolean
    local graph=WorldMap.fromTiles(s.tiles,s.radius)
    local view=Game.snapshot(s,actor); local before={}; local pending=false
    for _, c in s.cities do
        if c.ownerId~=actor then continue end
        before[c.id]={food=c.food,production=c.production,population=c.population,queue=c.queue,forecast=view.cityForecasts[tostring(c.id)]}
        if c.population>=3 then for _, id in WorldMap.range(graph,c.tileId,Rules.cityWorkRadius) do if not s.tiles[id].ownerId then pending=true end end end
    end
    apply(s,actor,{kind="EndTurn"})
    for _, c in s.cities do
        local b=before[c.id]; if not b or c.ownerId~=actor then continue end
        local f=b.forecast; local growAt=Rules.growthBase+b.population*Rules.growthPerPopulation
        if f.growthTurns==1 then assert(c.population==b.population+1 and c.food==b.food+f.food-growAt,"forecast growth")
        elseif b.food+f.food<0 then assert(c.food==0,"forecast starvation")
        else assert(c.population==b.population and c.food==b.food+f.food,"forecast food "..c.food.." vs "..b.food.."+"..f.food) end
        if f.productionBlocked then assert(f.productionTurns==nil,"a blocked queue has no completion estimate") end
        if f.productionTurns==1 then assert(c.production==b.production+f.production-Rules.productionCosts[b.queue],"forecast completion")
        else assert(c.production==b.production+f.production,"forecast production "..c.production.." vs "..b.production.."+"..f.production) end
    end
    return pending
end

-- 3. Seed 2, two humans, radius 6: forecasts stay exact as population and culture borders grow.
do
    local s: any=Game.new(2,{humanPlayers=2,radius=6})
    for actor=1,2 do
        local settler=firstUnit(s,actor,"Settler"); apply(s,actor,{kind="FoundCity",unitId=settler.id})
        for _, c in s.cities do if c.ownerId==actor then apply(s,actor,{kind="SetCityFocus",cityId=c.id,focus="Food"}) end end
        apply(s,actor,{kind="EndTurn"})
    end
    local pendingChecks=0
    for _=1,40 do
        for actor=1,2 do
            local owners={}; for _, t in s.tiles do owners[t.id]=t.ownerId end
            Game.snapshot(s,actor)
            for _, t in s.tiles do assert(t.ownerId==owners[t.id],"the forecast never claims tiles in the state") end
            if endTurnMatchesForecast(s,actor) then pendingChecks += 1 end
        end
    end
    assert(pendingChecks>0,"the replay reached a population-3 city with territory still to claim")
end

-- Fixture helpers: a single-human game whose capital sits far from the rival, with its surroundings reset.
local function fixture(seed: number): (any, any, any)
    local s: any=Game.new(seed,{radius=8})
    local settler=firstUnit(s,1,"Settler"); local home=settler.tileId
    apply(s,1,{kind="FoundCity",unitId=settler.id})
    return s,cityAt(s,home),WorldMap.fromTiles(s.tiles,s.radius)
end
local function rival(s: any): any for _, c in s.cities do if c.ownerId==2 then return c end end; error("missing rival") end
local function plain(tile: any, terrain: string, ownerId: number?)
    tile.terrain=terrain; tile.resource=nil; tile.improvement=nil; tile.road=nil; tile.feature=nil; tile.river=nil; tile.ownerId=ownerId
end

-- 4. Constructed expansion: a population-3 city whose only owned tiles are Tundra and whose unclaimed outer ring
-- is Grassland. Population cannot work or claim that unowned ring; culture is still below its threshold.
do
    local s,city,graph=fixture(42)
    assert(WorldMap.distance(graph,city.tileId,rival(s).tileId)>=5,"fixture capital is far from the rival")
    city.population=3
    for _, id in WorldMap.range(graph,city.tileId,2) do
        if id==city.tileId then continue end
        plain(s.tiles[id],if WorldMap.distance(graph,city.tileId,id)==1 then "Tundra" else "Grassland",if WorldMap.distance(graph,city.tileId,id)==1 then 1 else nil)
    end
    local forecast=Game.snapshot(s,1).cityForecasts[tostring(city.id)]
    assert(forecast.food==-1 and forecast.production==2,"forecast excludes the unowned ring: "..forecast.food.."/"..forecast.production)
    for _, id in WorldMap.range(graph,city.tileId,2) do if WorldMap.distance(graph,city.tileId,id)==2 then assert(s.tiles[id].ownerId==nil,"snapshot leaves the ring unclaimed") end end
    endTurnMatchesForecast(s,1)
    for _, id in WorldMap.range(graph,city.tileId,2) do if WorldMap.distance(graph,city.tileId,id)==2 then assert(s.tiles[id].ownerId==nil,"population did not claim the ring") end end
end

-- 5. Two own cities compete for owned tiles in id order. An unowned tile stays unavailable without culture.
do
    local s,first,graph=fixture(43)
    local far=rival(s).tileId
    local spot,shared,unclaimed
    for _, tile in s.tiles do
        if WorldMap.distance(graph,first.tileId,tile.id)~=3 or WorldMap.distance(graph,far,tile.id)<6 or not Rules.terrains[tile.terrain].passable then continue end
        local both={}
        for _, id in WorldMap.range(graph,tile.id,2) do if WorldMap.distance(graph,first.tileId,id)==2 then table.insert(both,id) end end
        local near,outer
        for _, id in both do if WorldMap.distance(graph,tile.id,id)==1 then near=near or id elseif WorldMap.distance(graph,tile.id,id)==2 then outer=outer or id end end
        if near and outer then spot,shared,unclaimed=tile.id,near,outer; break end
    end
    assert(spot and shared and unclaimed,"a second site sharing tiles with the capital")
    local worker=firstUnit(s,1,"Worker"); worker.kind="Settler"; worker.tileId=spot; worker.moves=2
    apply(s,1,{kind="FoundCity",unitId=worker.id})
    local second=cityAt(s,spot); assert(second.id>first.id)
    for _, c in ({first,second} :: {any}) do
        for _, id in WorldMap.range(graph,c.tileId,2) do
            if id==first.tileId or id==second.tileId then continue end
            local tile=s.tiles[id]; plain(tile,"Tundra",if tile.ownerId==1 then 1 else nil)
        end
    end
    -- `shared` is next to the newer city (owned since its founding); `unclaimed` is two tiles from both.
    local farm=s.tiles[shared]; plain(farm,"Grassland",1); farm.resource="Wheat"; farm.improvement="Farm"
    plain(s.tiles[unclaimed],"Grassland",nil)
    first.population=3; second.population=2
    local view=Game.snapshot(s,1)
    local older,newer=view.cityForecasts[tostring(first.id)],view.cityForecasts[tostring(second.id)]
    -- Older city (population 3, happiness 0): centre 2 + Farm 5 + claimed Grassland 3 + Tundra 1 - 6 food.
    assert(older.food==3,"older city works the shared Farm but no claim: "..older.food)
    -- Newer city (population 2): centre 2 + two Tundra - 4 food; the Farm and the claimed tile are taken.
    assert(newer.food==0,"newer city loses the contested tiles: "..newer.food)
    assert(s.tiles[unclaimed].ownerId==nil)
    endTurnMatchesForecast(s,1)
    assert(s.tiles[unclaimed].ownerId==nil,"population never claims territory")
end

-- 6. A saved game whose deployment tiles are all occupied: the queue is complete in cost but cannot finish, so
-- the forecast reports productionBlocked="NoSpace" without a completion estimate, and EndTurn produces nothing.
-- An unavailable item reports "NotAvailable". Freeing one tile restores the exact one-turn estimate.
do
    local s,city,graph=fixture(44)
    city.queue="Warrior"; city.production=Rules.productionCosts.Warrior
    local occupied={}; for _, u in s.units do occupied[u.tileId]=true end
    for _, id in WorldMap.range(graph,city.tileId,1) do
        if occupied[id] or not Rules.terrains[s.tiles[id].terrain].passable then continue end
        table.insert(s.units,{id=s.nextUnit,ownerId=1,kind="Worker",tileId=id,hp=50,moves=0,fortified=false,level=0}); s.nextUnit += 1
    end
    local restored=assert(Game.restore(Game.serialize(s))); s=restored
    for _, c in s.cities do if c.id==city.id then city=c end end
    local forecast=Game.snapshot(s,1).cityForecasts[tostring(city.id)]
    assert(forecast.productionBlocked=="NoSpace" and forecast.productionTurns==nil,"occupied deployment tiles block the Warrior")
    local warriors=0; for _, u in s.units do if u.ownerId==1 and u.kind=="Warrior" then warriors += 1 end end
    endTurnMatchesForecast(s,1)
    local after=0; for _, u in s.units do if u.ownerId==1 and u.kind=="Warrior" then after += 1 end end
    assert(after==warriors,"nothing was produced")
    -- A building never needs deployment space; an item without its technology is unavailable.
    city.queue="Swordsman"
    forecast=Game.snapshot(s,1).cityForecasts[tostring(city.id)]
    assert(forecast.productionBlocked=="NotAvailable" and forecast.productionTurns==nil,"missing technology blocks the Swordsman")
    city.queue="Monument"
    forecast=Game.snapshot(s,1).cityForecasts[tostring(city.id)]
    assert(forecast.productionBlocked==nil and forecast.productionTurns==1,"Monument completes despite the occupied tiles")
    -- Free one deployment tile: the Warrior is completable again and finishes exactly as forecast.
    city.queue="Warrior"
    for i=#s.units,1,-1 do local u=s.units[i]; if u.ownerId==1 and u.kind=="Worker" and WorldMap.distance(graph,u.tileId,city.tileId)==1 then table.remove(s.units,i); break end end
    forecast=Game.snapshot(s,1).cityForecasts[tostring(city.id)]
    assert(forecast.productionBlocked==nil and forecast.productionTurns==1,"freed tile restores the estimate")
    endTurnMatchesForecast(s,1)
    local finished=0; for _, u in s.units do if u.ownerId==1 and u.kind=="Warrior" then finished += 1 end end
    assert(finished==warriors+1,"the Warrior was produced")
end

-- 7. Within one step an earlier city's completion uses up what a later city needs. One improved Iron supplies two Iron
-- (G7 quantities) and a Swordsman already uses one; with both cities finishing a Swordsman, only the older city's
-- completes; the newer city's queue is reported unavailable.
do
    local s,first,graph=fixture(45)
    local far=rival(s).tileId
    local spot
    for _, tile in s.tiles do
        if WorldMap.distance(graph,first.tileId,tile.id)==3 and WorldMap.distance(graph,far,tile.id)>=6 and Rules.terrains[tile.terrain].passable then spot=tile.id; break end
    end
    assert(spot,"a second site")
    local worker=firstUnit(s,1,"Worker"); worker.kind="Settler"; worker.tileId=spot; worker.moves=2
    apply(s,1,{kind="FoundCity",unitId=worker.id})
    local second=cityAt(s,spot)
    local player=s.players[1]
    for _, id in {"Mining","BronzeWorking","IronWorking"} do table.insert(player.technologies,id) end
    local mine: any=nil
    for _, id in WorldMap.range(graph,first.tileId,1) do if id~=first.tileId then mine=s.tiles[id]; break end end
    plain(mine,"Hills",1); mine.resource="Iron"; mine.improvement="Mine"
    table.insert(s.units,{id=s.nextUnit,ownerId=1,kind="Swordsman",tileId=first.tileId,hp=100,moves=0,fortified=false,level=0}); s.nextUnit += 1
    assert(Game.snapshot(s,1).strategic.Iron.have==2 and Game.snapshot(s,1).strategic.Iron.used==1,"one Iron left")
    for _, c in ({first,second} :: {any}) do c.queue="Swordsman"; c.production=Rules.productionCosts.Swordsman end
    local view=Game.snapshot(s,1)
    local older,newer=view.cityForecasts[tostring(first.id)],view.cityForecasts[tostring(second.id)]
    assert(older.productionTurns==1 and older.productionBlocked==nil,"older city completes the Swordsman")
    assert(newer.productionBlocked=="NotAvailable" and newer.productionTurns==nil,"the older city's Swordsman uses the only Iron")
    endTurnMatchesForecast(s,1)
    local swordsmen=0; for _, u in s.units do if u.ownerId==1 and u.kind=="Swordsman" then swordsmen += 1 end end
    assert(swordsmen==2,"exactly one more Swordsman")
end
-- 8. The global unit cap never leaks unseen rival units. Two saved games differ only by one rival Worker the actor
-- cannot see (167 vs 168 units; the cap is 169) and both own cities finish a Warrior this step. The actor's whole
-- snapshot, forecasts included, is identical. The forecast counts earlier own completions only against units the
-- actor can see, so in the 168 game the newer city's Warrior is stopped by the cap (the documented exception).
local function sameValue(a: any, b: any, path: string)
    if type(a)~="table" or type(b)~="table" then assert(a==b,"snapshots differ at "..path); return end
    for key, value in a do sameValue(value,b[key],path.."."..tostring(key)) end
    for key in b do assert(a[key]~=nil,"snapshots differ at "..path.."."..tostring(key)) end
end
local function twoCities(seed: number): (any, any, any, any)
    local s: any=Game.new(seed,{radius=12})
    local settler=firstUnit(s,1,"Settler"); local home=settler.tileId
    apply(s,1,{kind="FoundCity",unitId=settler.id})
    local first=cityAt(s,home); local graph=WorldMap.fromTiles(s.tiles,s.radius); local far=rival(s).tileId
    local spot
    for _, tile in s.tiles do
        if WorldMap.distance(graph,first.tileId,tile.id)==3 and WorldMap.distance(graph,far,tile.id)>=6 and Rules.terrains[tile.terrain].passable and not tile.ownerId then spot=tile.id; break end
    end
    assert(spot,"a second site")
    local worker=firstUnit(s,1,"Worker"); worker.kind="Settler"; worker.tileId=spot; worker.moves=2
    apply(s,1,{kind="FoundCity",unitId=worker.id})
    local second=cityAt(s,spot)
    for _, c in ({first,second} :: {any}) do c.queue="Warrior"; c.production=Rules.productionCosts.Warrior end
    return s,first,second,graph
end
-- Free passable tiles away from both cities' deployment tiles; `hidden` keeps only tiles the actor cannot see.
local function fill(s: any, graph: any, cities: {any}, owner: number, total: number, hidden: boolean)
    local seen={}; for _, tile in Game.snapshot(s,1).tiles do seen[tile.id]=tile.visible end
    local used={}; for _, u in s.units do used[u.tileId]=true end; for _, c in s.cities do used[c.tileId]=true end
    for _, tile in s.tiles do
        if #s.units>=total then break end
        local near=false; for _, c in cities do if WorldMap.distance(graph,c.tileId,tile.id)<=2 then near=true end end
        if used[tile.id] or near or tile.ownerId or not Rules.terrains[tile.terrain].passable or (hidden and seen[tile.id]) then continue end
        table.insert(s.units,{id=s.nextUnit,ownerId=owner,kind="Worker",tileId=tile.id,hp=50,moves=0,fortified=false,level=0}); s.nextUnit += 1
        used[tile.id]=true
    end
    assert(#s.units==total,"filled to "..total)
end
do
    local s,first,second,graph=twoCities(46)
    fill(s,graph,{first,second},2,167,true)
    local lower=assert(Game.restore(Game.serialize(s)))
    fill(s,graph,{first,second},2,168,true)
    local higher=assert(Game.restore(Game.serialize(s)))
    assert(#lower.units==167 and #higher.units==168)
    local a,b=Game.snapshot(lower,1),Game.snapshot(higher,1)
    sameValue(a,b,"view")
    for _, c in ({first,second} :: {any}) do
        local f=a.cityForecasts[tostring(c.id)]
        assert(f.productionTurns==1 and f.productionBlocked==nil,"both Warriors are forecast to finish")
    end
    endTurnMatchesForecast(lower,1)
    local warriors=function(state: any): number local n=0; for _, u in state.units do if u.ownerId==1 and u.kind=="Warrior" then n += 1 end end; return n end
    local before=warriors(higher)
    apply(higher,1,{kind="EndTurn"})
    assert(warriors(higher)==before+1,"in the 168 game the unseen Worker lets the cap stop the newer city's Warrior")
end
-- When the units the actor can see already reach the cap with the earlier completion, the block is certain and reported.
do
    local s,first,second,graph=twoCities(46)
    fill(s,graph,{first,second},1,168,false)
    local view=Game.snapshot(s,1)
    local older,newer=view.cityForecasts[tostring(first.id)],view.cityForecasts[tostring(second.id)]
    assert(older.productionTurns==1 and older.productionBlocked==nil,"older city takes the last unit slot")
    assert(newer.productionBlocked=="NotAvailable" and newer.productionTurns==nil,"newer city is stopped by the cap")
    endTurnMatchesForecast(s,1)
end

-- 9. Population three cannot acquire an unowned Iron Mine or make a Swordsman available.
do
    local s,city,graph=fixture(47)
    city.population=3
    for _, id in {"Mining","BronzeWorking","IronWorking"} do table.insert(s.players[1].technologies,id) end
    local mine: any=nil
    for _, id in WorldMap.range(graph,city.tileId,2) do
        local tile=s.tiles[id]
        if tile.resource=="Iron" then tile.resource=nil end
        if WorldMap.distance(graph,city.tileId,id)==2 and not tile.ownerId and not mine then mine=tile end
    end
    assert(mine,"an unowned tile two steps out")
    plain(mine,"Hills",nil); mine.resource="Iron"; mine.improvement="Mine"
    city.queue="Swordsman"; city.production=Rules.productionCosts.Swordsman
    local forecast=Game.snapshot(s,1).cityForecasts[tostring(city.id)]
    assert(forecast.productionTurns==nil and forecast.productionBlocked=="NotAvailable","unowned Iron cannot make the Swordsman available")
    assert(mine.ownerId==nil,"the snapshot does not claim the mine")
    endTurnMatchesForecast(s,1)
    local swordsmen=0; for _, u in s.units do if u.ownerId==1 and u.kind=="Swordsman" then swordsmen += 1 end end
    assert(swordsmen==0 and mine.ownerId==nil,"population never acquires the mine")
end
print("base cities: founding-order names per civilization, exact per-city forecasts for own cities only passed")
