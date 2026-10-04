--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original G11a culture territory, tile purchase, projection and migration regressions.
local Game=require("../../src/simulation/BaseGame")
local Save=require("../../src/simulation/BaseSave")
local Map=require("../../src/simulation/WorldMap")
local Rules=require("../../src/simulation/BaseRules")
local I=(Game :: any)._internal
local restores: {(any) -> (any?,string?)}={Game.restore,Save.restore}
local function apply(s: any,actor: number,cmd: any)
    local result=Game.apply(s,actor,cmd); assert(result.ok,result.message)
end
local function fixture(turns: number?): (any,any,any)
    local s: any=Game.new(7919,{humanPlayers=2,radius=8,maxTurns=turns or 120,barbarians=false})
    local map=Map.fromTiles(s.tiles,s.radius)
    for _, t in s.tiles do t.terrain="Plains"; t.resource=nil; t.feature=nil; t.river=nil; t.ownerId=nil; t.improvement=nil end
    local settlers={}; for _, u in s.units do if u.kind=="Settler" then table.insert(settlers,u) end end
    s.units=table.clone(settlers)
    for actor=1,2 do
        local u=settlers[actor]; u.tileId=assert(Map.tileId(map,if actor==1 then 0 else 6,0)); u.moves=2
        s.activePlayerId=actor; apply(s,actor,{kind="FoundCity",unitId=u.id})
    end
    s.activePlayerId=1; s.units={}
    for _, c in s.cities do c.queue="" end
    return s,s.cities[1],map
end
local function view(s: any,c: any): any
    for _, v in Game.snapshot(s,c.ownerId).cities do if v.id==c.id then return v end end; error("missing view")
end
local function step(s: any,actor: number?)
    s.activePlayerId=actor or 1; apply(s,actor or 1,{kind="EndTurn"})
end
local function owned(s: any,actor: number): number
    local count=0; for _, t in s.tiles do if t.ownerId==actor then count+=1 end end; return count
end
local function ring(s: any,c: any,map: any,d: number): {number}
    local ids={}; for _, id in Map.range(map,c.tileId,d) do if Map.distance(map,c.tileId,id)==d then table.insert(ids,id) end end
    table.sort(ids); return ids
end
local function isolate(s: any,c: any,map: any,ids: {number})
    for _, id in ring(s,c,map,2) do s.tiles[id].ownerId=if table.find(ids,id) then nil else 2 end
end
-- Founding has exactly seven tiles. Crossing population three and the following step never claims the second ring.
do
    local s,c,map=fixture(); assert(owned(s,1)==7 and c.borderCulture==0 and c.borderTiles==0)
    c.population=2; c.food=100; step(s); assert(c.population==3 and owned(s,1)==7)
    step(s); assert(owned(s,1)==7)
    local f=Game.snapshot(s,1).cityForecasts[tostring(c.id)]
    assert(f.food==2+3*Rules.terrains.Plains.yields.food-3*Rules.foodPerPopulation,"forecast must not virtually claim radius two")
    for _, id in ring(s,c,map,2) do assert(s.tiles[id].ownerId==nil) end
end
-- Pace uses policy curve; culture still funds policies, and overflow buys at most one tile per step.
for _, turns in {120,80} do
    local s,c=fixture(turns); local v=view(s,c)
    local percent=Game.costPercent(s,"policy")
    assert(v.nextTileCost==math.floor(Rules.borderCultureBase*percent/100+0.5))
    assert(v.borderTurns==math.ceil(v.nextTileCost/(1+Rules.borderBaseRate)))
    local policyCulture=s.players[1].culture
    step(s); assert(c.borderCulture==1+Rules.borderBaseRate and s.players[1].culture==policyCulture+1)
    c.borderCulture=v.nextTileCost+100; local before=owned(s,1)
    step(s); assert(owned(s,1)==before+1 and c.borderTiles==1 and c.borderCulture==100+1+Rules.borderBaseRate)
    local base=math.floor(Rules.borderCultureBase+Rules.borderCultureMultiplier^Rules.borderCultureExponent)
    assert(view(s,c).nextTileCost==math.floor(base*percent/100+0.5))
    step(s); assert(owned(s,1)==before+2 and c.borderTiles==2)
end
-- Natural yield order, projected strategic resources without technology, improvement exclusion and low-id ties.
do
    local s,c,map=fixture(); local ids=ring(s,c,map,2); local a,b=ids[1],ids[2]; isolate(s,c,map,{a,b})
    s.tiles[a].terrain="Tundra"; s.tiles[b].terrain="Grassland"
    assert(view(s,c).nextBorderTile==b,"yield score")
    s.tiles[a].terrain="Plains"; s.tiles[b].terrain="Plains"
    assert(view(s,c).nextBorderTile==a,"low tile id tie")
    s.tiles[b].improvement="Farm"; assert(view(s,c).nextBorderTile==a,"improvements are ignored")
    s.tiles[b].resource="Iron"; assert(view(s,c).nextBorderTile==b,"projected strategic resource is preferred without reveal technology")
    table.insert(s.players[1].technologies,"Mining"); table.insert(s.players[1].technologies,"BronzeWorking")
    assert(view(s,c).nextBorderTile==b,"revealed strategic bonus")
    s.tiles[a].resource="Gold"; assert(view(s,c).nextBorderTile==a,"luxury beats strategic")
    s.tiles[a].resource="Wheat"; s.tiles[b].resource=nil; assert(view(s,c).nextBorderTile==a,"bonus resource")
end
-- Adjacency, the radius-three limit, distance penalty, fogged resources, and impassable candidates.
do
    local s,c,map=fixture(); local outer=ring(s,c,map,3); local target=outer[1]
    for _, row in view(s,c).buyableTiles do assert(row.tileId~=target,"detached third ring") end
    local bridge=nil; for _, id in map.neighbors[target] do if Map.distance(map,c.tileId,id)==2 then bridge=id; break end end
    assert(bridge); s.tiles[bridge].ownerId=1
    local listed={}; for _, row in view(s,c).buyableTiles do listed[row.tileId]=true; assert(Map.distance(map,c.tileId,row.tileId)<=3) end
    assert(listed[target],"adjacent third ring is legal")
    s.tiles[target].ownerId=1 -- A third-ring bridge makes fourth-ring tiles adjacent, but still out of range.
    for _, row in view(s,c).buyableTiles do assert(Map.distance(map,c.tileId,row.tileId)<=3,"adjacent fourth ring is forbidden") end
    s.tiles[target].ownerId=nil
    for _, id in ring(s,c,map,4) do assert(not listed[id],"fourth ring is forbidden") end
    for _, id in ring(s,c,map,2) do s.tiles[id].ownerId=2 end
    s.tiles[bridge].ownerId=1
    -- All candidates now have equal natural yields at distance three, so a fogged luxury cannot break the tie.
    local v=view(s,c); local first=v.buyableTiles[1].tileId; local last=v.buyableTiles[#v.buyableTiles].tileId
    s.players[1].explored=Map.range(map,c.tileId,2)
    s.tiles[last].resource="Gold"; assert(view(s,c).nextBorderTile==first,"unexplored resource is ignored")
    table.insert(s.players[1].explored,last)
    assert(view(s,c).nextBorderTile==last,"explored resource outside current sight is preferred")
    local a=ring(s,c,map,2)[1]; s.tiles[a].ownerId=nil; s.tiles[a].terrain="Mountain"
    local hasMountain=false; for _, row in view(s,c).buyableTiles do if row.tileId==a then hasMountain=true end end
    assert(hasMountain,"mountains may be owned")
    s.tiles[a].terrain="Plains"; assert(view(s,c).nextBorderTile==a,"distance penalty favours equal-yield closer tile")
    s.tiles[a].terrain="Water"; local hasWater=false
    for _, row in view(s,c).buyableTiles do if row.tileId==a then hasWater=true end end
    assert(hasWater,"water may be owned")
end
-- Production can discover a resource before actual acquisition. Forecasts use only current projected knowledge:
-- new exploration may change the actual choice, without leaking unexplored resources through later city yields.
do
    local s,c,map=fixture(); local site=assert(Map.tileId(map,0,4))
    table.insert(s.units,{id=s.nextUnit,ownerId=1,kind="Settler",tileId=site,hp=50,moves=2,fortified=false,level=0}); s.nextUnit+=1
    apply(s,1,{kind="FoundCity",unitId=s.units[1].id}); s.units={}
    local later=s.cities[3]; later.population=3; later.queue=""
    local shared=assert(Map.tileId(map,0,2)); local luxury=assert(Map.tileId(map,3,0)); local bridge=assert(Map.tileId(map,2,0)); local spawn=assert(Map.tileId(map,1,0))
    isolate(s,c,map,{shared}); s.tiles[bridge].ownerId=1
    s.tiles[shared].terrain="Grassland"; s.tiles[shared].resource="Wheat"; s.tiles[luxury].resource="Gold"
    for _, id in Map.range(map,c.tileId,1) do
        if id==spawn then continue end
        table.insert(s.units,{id=s.nextUnit,ownerId=1,kind="Worker",tileId=id,hp=50,moves=0,fortified=false,level=0}); s.nextUnit+=1
    end
    c.queue="Warrior"; c.production=1000; c.borderCulture=view(s,c).nextTileCost
    assert(view(s,c).nextBorderTile==shared,"current preview uses current resource sight")
    local forecast=Game.snapshot(s,1).cityForecasts[tostring(later.id)]
    local expected=2+3*Rules.terrains.Plains.yields.food-3*Rules.foodPerPopulation
    assert(forecast.food==expected+2,"forecast culture selection cannot read an unexplored resource")
    local before=later.food; step(s)
    assert(s.tiles[luxury].ownerId==1 and s.tiles[shared].ownerId==nil and later.food-before==expected,"culture uses new unit sight after production")
end
local function equal(a: any,b: any): boolean
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in a do if not equal(v,b[k]) then return false end end
    for k in b do if a[k]==nil then return false end end
    return true
end
local function fogFixture(): (any,any,any,number)
    local s,c,map=fixture(); local target=assert(Map.tileId(map,3,0)); local bridge=assert(Map.tileId(map,2,0))
    isolate(s,c,map,{bridge}); s.tiles[bridge].ownerId=1
    s.tiles[target].resource="Gold"; table.insert(s.players[1].explored,target)
    assert(not Game.snapshot(s,1).tiles[target].visible and view(s,c).nextBorderTile==target)
    s.barbarians={nextCamp=1,camps={}}
    return s,c,map,target
end
local function blocker(s: any,target: number,kind: string)
    if kind=="camp" then s.barbarians={nextCamp=2,camps={{id=1,tileId=target,founded=1,lastSpawn=1}}}
    elseif kind=="city" then s.cities[2].tileId=target
    else table.insert(s.units,{id=s.nextUnit,ownerId=2,kind="Worker",tileId=target,hp=50,moves=2,fortified=false,level=0}); s.nextUnit+=1 end
end
-- Hidden blockers never affect any snapshot field (including menus, countdowns or later-city forecasts), nor
-- culture choice. Visible blockers change both the menu and actual selection. Acquisition keeps blockers in place.
for _, kind in {"unit","camp","city"} do
    local s,c,map,target=fogFixture(); local before=Game.snapshot(s,1)
    blocker(s,target,kind)
    assert(equal(before,Game.snapshot(s,1)),"snapshots differ only in hidden "..kind)
    c.borderCulture=view(s,c).nextTileCost; step(s)
    assert(s.tiles[target].ownerId==1,"hidden "..kind.." does not change culture choice")
    if kind=="unit" then assert(s.units[1].tileId==target)
    elseif kind=="camp" then assert(s.barbarians.camps[1].tileId==target)
    else assert(s.cities[2].tileId==target) end
    s,c,map,target=fogFixture(); blocker(s,target,kind)
    table.insert(s.units,{id=s.nextUnit,ownerId=1,kind="Worker",tileId=assert(Map.tileId(map,1,0)),hp=50,moves=0,fortified=false,level=0}); s.nextUnit+=1
    assert(Game.snapshot(s,1).tiles[target].visible)
    local v=view(s,c); assert(v.nextBorderTile~=target,"visible blocker changes best tile")
    for _, row in v.buyableTiles do assert(row.tileId~=target,"visible blocker removes candidate") end
    local refused=Game.apply(s,1,{kind="BuyTile",cityId=c.id,tileId=target}); assert(not refused.ok)
    c.borderCulture=v.nextTileCost; step(s); assert(s.tiles[target].ownerId==nil,"visible blocker changes culture choice")
end
-- Buying around a hidden peaceful unit succeeds. Territory restrictions apply to entry, so it can leave normally.
do
    local s,c,map,target=fogFixture(); blocker(s,target,"unit"); s.players[1].gold=1000
    apply(s,1,{kind="BuyTile",cityId=c.id,tileId=target})
    local u=s.units[1]; assert(u.tileId==target and s.tiles[target].ownerId==1 and s.diplomacy.status=="Peace")
    local exit=assert(Map.tileId(map,4,0)); s.activePlayerId=2
    assert(table.find(Game.snapshot(s,2).legalMoves[tostring(u.id)],exit),"unit can leave peaceful foreign land")
    apply(s,2,{kind="MoveUnit",unitId=u.id,tileId=exit}); assert(u.tileId==exit)
    local refused=Game.apply(s,2,{kind="MoveUnit",unitId=u.id,tileId=target})
    assert(not refused.ok,"entering peaceful foreign land remains forbidden")
end
-- Hidden ownership follows the projection (ownerId only in current sight). Apply skips owned candidates silently;
-- purchase uses the identical generic refusal as any other non-candidate, without consuming gold or culture.
do
    local s,c,_,target=fogFixture(); local before=Game.snapshot(s,1)
    s.tiles[target].ownerId=2; assert(equal(before,Game.snapshot(s,1)),"unseen ownership must follow projection")
    s.players[1].gold=1000; local gold=s.players[1].gold; local revision=s.revision
    local refused=Game.apply(s,1,{kind="BuyTile",cityId=c.id,tileId=target})
    local cmd: any={kind="BuyTile",cityId=c.id,tileId=c.tileId}; local generic=Game.apply(s,1,cmd)
    assert(not refused.ok and refused.message==generic.message and s.players[1].gold==gold and s.revision==revision)
    local nextChoice=nil; s.tiles[target].ownerId=nil; s.tiles[target].resource=nil
    nextChoice=view(s,c).nextBorderTile; assert(nextChoice~=target)
    s.tiles[target].resource="Gold"; s.tiles[target].ownerId=2; c.borderCulture=view(s,c).nextTileCost
    step(s); assert(s.tiles[target].ownerId==2 and s.tiles[nextChoice].ownerId==1,"silently skip owned best candidate")
    local count=0; for _, e in s.events do if e.kind=="BorderGrowth" then count+=1; assert(e.tileId==nextChoice) end end
    assert(count==1,"no skipped-candidate event")
end
-- Foreign units, foreign city (even with a raw unowned tile), and barbarian camps are excluded.
do
    local s,c,map=fixture(); local ids=ring(s,c,map,2); local a,b,d=ids[1],ids[2],ids[3]
    table.insert(s.units,{id=s.nextUnit,ownerId=2,kind="Worker",tileId=a,hp=50,moves=0,fortified=false,level=0}); s.nextUnit+=1
    local rival=s.cities[2]; rival.tileId=b
    s.barbarians={nextCamp=2,camps={{id=1,tileId=d,founded=1,lastSpawn=1}}}
    for _, row in view(s,c).buyableTiles do assert(row.tileId~=a and row.tileId~=b and row.tileId~=d,"foreign blocker") end
    s.units[1].ownerId=1; local found=false; for _, row in view(s,c).buyableTiles do if row.tileId==a then found=true end end; assert(found,"own units allow acquisition")
end
-- BuyTile success and every refusal, without mutation on refusal. Events stay private even in rival sight.
do
    local s,c,map=fixture(80); local tile=ring(s,c,map,2)[1]; local row=view(s,c).buyableTiles[1]
    assert(row.tileId==tile and row.cost==math.floor(Rules.borderBuyBase*Game.costPercent(s,"production")/100+0.5))
    c.borderCulture=7; s.players[1].gold=row.cost
    local function rejects(actor: number,cmd: any,part: string)
        local revision=s.revision; local gold=s.players[1].gold; local count=c.borderTiles
        local result=Game.apply(s,actor,cmd); assert(not result.ok and string.find(result.message,part,1,true))
        assert(s.revision==revision and s.players[1].gold==gold and c.borderTiles==count)
    end
    rejects(2,{kind="BuyTile",cityId=c.id,tileId=tile},"turn")
    rejects(1,{kind="BuyTile",cityId=s.cities[2].id,tileId=tile},"your city")
    rejects(1,{kind="BuyTile",cityId=c.id,tileId=c.tileId},"unowned adjacent")
    rejects(1,{kind="BuyTile",cityId=c.id,tileId=0/0},"unowned adjacent")
    s.players[1].gold=row.cost-1; rejects(1,{kind="BuyTile",cityId=c.id,tileId=tile},"gold")
    s.players[1].gold=row.cost; apply(s,1,{kind="BuyTile",cityId=c.id,tileId=tile})
    assert(s.players[1].gold==0 and s.tiles[tile].ownerId==1 and c.borderTiles==1 and c.borderCulture==7)
    local e=s.events[#s.events]; assert(e.kind=="BorderGrowth" and e.tileId==tile and e.ownerId==1 and e.cityId==c.id and e.amount==row.cost)
    local restored=assert(Game.restore(Game.serialize(s)))
    assert(restored.cities[1].borderCulture==7 and restored.cities[1].borderTiles==1 and restored.events[#restored.events].kind=="BorderGrowth","purchased border save roundtrip")
    s.cities[2].tileId=tile
    for _, event in Game.snapshot(s,2).events do assert(event.id~=e.id,"owner-private event even in sight") end
    for _, rival in Game.snapshot(s,2).cities do if rival.id==c.id then
        for _, key in {"borderCulture","nextTileCost","borderTurns","buyableTiles","nextBorderTile","borderTiles"} do assert((rival :: any)[key]==nil) end
    end end
end
-- Distance prices round the base first, use production pace, and purchases increase subsequent prices.
do
    local s,c,map=fixture(80); c.borderTiles=3
    local inner=ring(s,c,map,1)[1]; s.tiles[inner].ownerId=nil
    local outer=ring(s,c,map,3)[1]
    for _, id in map.neighbors[outer] do if Map.distance(map,c.tileId,id)==2 then s.tiles[id].ownerId=1; break end end
    local prices={}; for _, row in view(s,c).buyableTiles do prices[row.tileId]=row.cost end
    local base=Rules.borderBuyBase+3*Rules.borderBuyPerTile; local percent=Game.costPercent(s,"production")
    assert(prices[inner]==math.floor(math.floor(base*0.75)*percent/100+0.5))
    assert(prices[outer]==math.floor(math.floor(base*1.5)*percent/100+0.5))
    s.players[1].gold=1000; apply(s,1,{kind="BuyTile",cityId=c.id,tileId=outer})
    local expected=math.floor(math.floor(Rules.borderCultureBase+(4*Rules.borderCultureMultiplier)^Rules.borderCultureExponent)*Game.costPercent(s,"policy")/100+0.5)
    assert(view(s,c).nextTileCost==expected,"purchases escalate culture cost")
end
-- Sorted detached menu, no-candidate cap/countdown, capture keeps stored culture and count.
do
    local s,c,map=fixture(); local v=view(s,c); local last=0
    for _, row in v.buyableTiles do assert(row.tileId>last); last=row.tileId end
    v.buyableTiles[1].cost=9999; assert(view(s,c).buyableTiles[1].cost~=9999)
    for _, id in Map.range(map,c.tileId,3) do s.tiles[id].ownerId=1 end
    for _, id in ring(s,c,map,2) do
        table.insert(s.units,{id=s.nextUnit,ownerId=1,kind="Worker",tileId=id,hp=50,moves=0,fortified=false,level=0}); s.nextUnit+=1
    end
    c.borderCulture=1000; local cost=view(s,c).nextTileCost; step(s)
    v=view(s,c); assert(c.borderCulture==cost and c.borderTiles==0 and v.borderTurns==nil and v.nextBorderTile==nil and #v.buyableTiles==0)
end
-- Legacy allocation ties use city id, not city array order; both restore paths and sphere topology migrate.
do
    local s,c,map=fixture()
    local tile=assert(Map.tileId(map,3,0))
    table.insert(s.units,{id=s.nextUnit,ownerId=1,kind="Settler",tileId=tile,hp=50,moves=2,fortified=false,level=0}); s.nextUnit+=1
    apply(s,1,{kind="FoundCity",unitId=s.units[1].id})
    for _, city in s.cities do
        if city.ownerId~=1 then continue end
        for _, id in Map.range(map,city.tileId,3) do if id~=s.cities[2].tileId then s.tiles[id].ownerId=1 end end
    end
    local expected: {[number]: number}={}; local ties=0
    for _, t in s.tiles do
        if t.ownerId~=1 then continue end
        local a,b=Map.distance(map,c.tileId,t.id),Map.distance(map,s.cities[3].tileId,t.id)
        if math.min(a,b)>3 then continue end
        local id=if a<=b then c.id else s.cities[3].id
        expected[id]=(expected[id] or 0)+1; if a==b then ties+=1 end
    end
    assert(ties>0)
    for _, city in s.cities do city.borderCulture=nil; city.borderTiles=nil end
    s.cities[1],s.cities[3]=s.cities[3],s.cities[1]
    for _, restore in restores do
        local loaded=assert(restore(Game.serialize(s)))
        for _, city in loaded.cities do if city.ownerId==1 then assert(city.borderTiles==math.max(0,expected[city.id]-7),"nearest own city and id tie") end end
    end
    local globe: any=Game.new(7919,{mapShape="Sphere",frequency=3,barbarians=false})
    for _, u in globe.units do if u.ownerId==1 and u.kind=="Settler" then apply(globe,1,{kind="FoundCity",unitId=u.id}); break end end
    globe.units={}; local graph=Map.fromSphereTiles(globe.tiles,globe.frequency); local home=globe.cities[2]
    local count=0
    for _, id in Map.range(graph,home.tileId,2) do if id~=globe.cities[1].tileId then globe.tiles[id].ownerId=1; count+=1 end end
    home.borderCulture=nil; home.borderTiles=nil
    for _, restore in restores do
        local loaded=assert(restore(Game.serialize(globe))); assert(loaded.cities[2].borderTiles==math.max(0,count-7))
    end
end
-- Current round trips, absent fields migrate in both APIs without touching tiles, and malformed fields fail validation.
do
    local s,c,map=fixture(); c.borderCulture=7.5; c.borderTiles=2
    local saved=Game.serialize(s)
    for _, restore in restores do
        local restored=assert(restore(saved)); assert(restored.cities[1].borderCulture==7.5 and restored.cities[1].borderTiles==2)
    end
    for _, id in Map.range(map,c.tileId,2) do s.tiles[id].ownerId=1 end
    c.borderCulture=nil; c.borderTiles=nil; saved=Game.serialize(s)
    for _, restore in restores do
        local restored=assert(restore(saved)); assert(restored.cities[1].borderCulture==0 and restored.cities[1].borderTiles==12)
        for id,tile in s.tiles do assert(restored.tiles[id].ownerId==tile.ownerId) end
    end
    assert(saved.state.cities[1].borderCulture==nil,"restore does not mutate input")
    for _, restore in restores do
        local partial=Game.serialize(s); partial.state.cities[1].borderCulture=7.5
        local loaded=assert(restore(partial)); assert(loaded.cities[1].borderCulture==7.5 and loaded.cities[1].borderTiles==12)
        partial=Game.serialize(s); partial.state.cities[1].borderTiles=2
        loaded=assert(restore(partial)); assert(loaded.cities[1].borderCulture==0 and loaded.cities[1].borderTiles==2)
    end
    for _, key in {"borderCulture","borderTiles"} do
        for _, bad in {"bad",false,-1,math.huge,0/0,1000000001} do
            local raw=Game.serialize(s); raw.state.cities[1][key]=bad; assert(not Save.valid(raw),"bad "..key)
        end
    end
    local raw=Game.serialize(s); raw.state.cities[1].borderTiles=0.5; assert(not Save.valid(raw))
end
-- Internal harness executes the full AI in both seats and two-AI games, with identical geography after seat swap.
if I then
    -- The AI purchase helper uses the same observer rule in both seats, including explored strategic resources.
    for owner=1,2 do for _, kind in {"unit","camp"} do for _, inSight in {false,true} do
        local s,c,map,target=fogFixture()
        if owner==2 then
            for _, p in s.players do p.id=3-p.id end; s.players[1],s.players[2]=s.players[2],s.players[1]
            for _, city in s.cities do city.ownerId=3-city.ownerId; city.originalOwnerId=3-city.originalOwnerId end
            for _, t in s.tiles do if t.ownerId then t.ownerId=3-t.ownerId end end
        end
        s.tiles[target].resource="Iron"; blocker(s,target,kind)
        if kind=="unit" then s.units[1].ownerId=3-owner end
        if inSight then
            table.insert(s.units,{id=s.nextUnit,ownerId=owner,kind="Worker",tileId=assert(Map.tileId(map,1,0)),hp=50,moves=0,fortified=false,level=0}); s.nextUnit+=1
        end
        s.players[owner].gold=1000; I.aiBuyTile(s,owner)
        assert(s.tiles[target].ownerId==(if inSight then nil else owner),"AI observer blockers and projected strategic resource")
        if kind=="camp" and not inSight then
            assert(I.campSpawn(s,s.barbarians.camps[1]),"owned camp still spawns")
            assert(s.units[1].ownerId==Rules.barbarians.ownerId and s.units[1].tileId==target)
        end
    end end end
    local function aiCase(owner: number,gold: number): (number,number)
        local s,c,map=fixture(); if owner==2 then
            for _, p in s.players do p.id=3-p.id end; s.players[1],s.players[2]=s.players[2],s.players[1]
            for _, city in s.cities do city.ownerId=3-city.ownerId; city.originalOwnerId=3-city.originalOwnerId end
            for _, t in s.tiles do if t.ownerId then t.ownerId=3-t.ownerId end end
        end
        for _, p in s.players do p.human=false end
        local ids=ring(s,c,map,2); s.tiles[ids[1]].resource="Gold"; s.tiles[ids[2]].resource="Gold"
        s.players[owner].gold=gold; I.ai(s,owner)
        local count=0; local tile=0; for _, e in s.events do if e.kind=="BorderGrowth" and e.ownerId==owner then count+=1; tile=e.tileId end end
        assert(count==(if gold>=Rules.borderBuyBase+60 then 1 else 0),"AI purchase reserve and one tile limit")
        if count>0 then assert(tile==ids[1] and c.borderCulture==0 and c.borderTiles==1) end
        return tile,s.players[owner].gold
    end
    for _, gold in {Rules.borderBuyBase+59,Rules.borderBuyBase+60,1000} do
        local a,g1=aiCase(1,gold); local b,g2=aiCase(2,gold); assert(a==b and g1==g2,"seat symmetry")
    end
    local s,c,map=fixture(); for _, p in s.players do p.human=false; p.gold=1000 end
    local a=ring(s,c,map,2)[1]; local b=ring(s,s.cities[2],map,2)[1]
    s.tiles[a].resource="Gold"; s.tiles[b].resource="Gold"
    I.ai(s,1); I.ai(s,2); assert(s.tiles[a].ownerId==1 and s.tiles[b].ownerId==2,"each AI empire may buy once")
    s,c,map=fixture()
    local tile=assert(Map.tileId(map,0,4))
    table.insert(s.units,{id=s.nextUnit,ownerId=1,kind="Settler",tileId=tile,hp=50,moves=2,fortified=false,level=0}); s.nextUnit+=1
    apply(s,1,{kind="FoundCity",unitId=s.units[1].id}); s.units={}
    local second=s.cities[3]; second.queue=""
    a=ring(s,c,map,2)[1]; b=ring(s,second,map,2)[1]
    s.tiles[a].resource="Spices"; s.tiles[b].resource="Gold"
    for _, p in s.players do p.human=false end
    s.players[1].gold=1000; I.ai(s,1)
    assert(s.tiles[a].ownerId==nil and s.tiles[b].ownerId==1 and c.borderTiles==0 and second.borderTiles==1,"highest resource score across cities")
end
print("culture borders, purchases, views and saves passed"..(if I then " (including two AI seats)" else ""))
