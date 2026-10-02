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
print("base cities: founding-order names per civilization, exact per-city forecasts for own cities only passed")
