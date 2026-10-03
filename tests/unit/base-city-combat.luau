--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original fixtures for G6 city combat: city combat strength (population, era, Walls, garrison), the once-per-round
-- CityRangedStrike and its validation, exact strike previews, kills and events, experience, the Catapult's siege
-- bonus, captured cities, the AI's strikes, fog-safe snapshot fields, saves written before city strikes and
-- deterministic replays.
local Game = require("../../src/simulation/BaseGame")
local Save = require("../../src/simulation/BaseSave")
local WorldMap = require("../../src/simulation/WorldMap")
local Rules = require("../../src/simulation/BaseRules")
local function equal(a: any,b: any): boolean
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in a do if not equal(v,b[k]) then return false end end
    for k in b do if a[k]==nil then return false end end; return true
end
local function apply(s: any,owner: number,command: any)
    local result=Game.apply(s,owner,command); assert(result.ok,result.message)
end
local function rejected(s: any,owner: number,command: any,label: string,message: string?): string
    local before=Game.serialize(s)
    local result=Game.apply(s,owner,command)
    assert(not result.ok,label.." was accepted")
    assert(equal(before,Game.serialize(s)),label.." changed the state")
    if message then assert(result.message==message,label..": unexpected message "..result.message) end
    return result.message
end
local function firstUnit(s: any,owner: number,kind: string): any
    for _, u in s.units do if u.ownerId==owner and u.kind==kind then return u end end; error("missing "..kind)
end
local function firstCity(s: any,owner: number): any
    for _, c in s.cities do if c.ownerId==owner then return c end end; error("missing city")
end
local function unitById(s: any,id: number): any
    for _, u in s.units do if u.id==id then return u end end; return nil
end
local function viewCity(view: any,id: number): any
    for _, c in view.cities do if c.id==id then return c end end; return nil
end
local function lastEvent(s: any,kind: string): any
    local found: any=nil; for _, e in s.events do if e.kind==kind then found=e end end; return found
end
local function countEvents(events: {any},kind: string): number
    local n=0; for _, e in events do if e.kind==kind then n += 1 end end; return n
end
local function founded(seed: number,radius: number?): any
    local s=Game.new(seed,{humanPlayers=2,radius=radius or 8})
    -- These fixtures pin earlier rules on bare terrain: terrain features and rivers (G4) are removed from the whole map.
    for _, t in s.tiles do t.feature=nil; t.river=nil end
    apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id}); apply(s,1,{kind="EndTurn"})
    apply(s,2,{kind="FoundCity",unitId=firstUnit(s,2,"Settler").id}); apply(s,2,{kind="EndTurn"}); return s
end
local function clear(s: any,id: number,terrain: string?)
    local t=s.tiles[id]; t.terrain=terrain or "Plains"; t.resource=nil; t.improvement=nil; t.road=nil
end
local function place(s: any,owner: number,kind: string,tileId: number,hp: number?): any
    local u={id=s.nextUnit,ownerId=owner,kind=kind,tileId=tileId,hp=hp or Rules.units[kind].hp,moves=Rules.units[kind].moves,fortified=false,level=0}
    table.insert(s.units,u); s.nextUnit += 1; return u
end
-- Tiles at exactly `d` hexes from `center`, sorted, excluding city tiles.
local function shell(s: any,graph: any,center: number,d: number): {number}
    local cityTiles={}; for _, c in s.cities do cityTiles[c.tileId]=true end
    local ids={}
    for _, t in s.tiles do if not cityTiles[t.id] and WorldMap.distance(graph,t.id,center)==d then table.insert(ids,t.id) end end
    table.sort(ids); return ids
end

-- The arena: a two-human war on player 1's turn with every unit removed. Player 1's capital has its hexes at distance
-- 1, 2 and 3 cleared to Plains; tests place exactly the units they need.
local base=founded(71); apply(base,1,{kind="DeclareWar",targetId=2})
base.units={}
local graph=WorldMap.fromTiles(base.tiles,base.radius)
local home=firstCity(base,1); local rival=firstCity(base,2)
local ring1,ring2,ring3=shell(base,graph,home.tileId,1),shell(base,graph,home.tileId,2),shell(base,graph,home.tileId,3)
assert(#ring1==6 and #ring2>=8 and #ring3>=8,"player 1's capital needs room around it")
for _, list in {ring1,ring2,ring3} do for _, id in list do clear(base,id) end end
clear(base,home.tileId)
home.population=1; home.buildings={}; home.hp=Rules.cityHp
assert(Save.valid(Game.serialize(base)),"the arena is a valid state")
local baseSave=Game.serialize(base)
local function fresh(): any local s: any=Game.restore(baseSave); assert(s); return s end

-- Independent statement of city combat (numbers written out, not read from the rules).
local function referenceStrength(population: number,technologies: number,walls: boolean,garrisonKind: string?): number
    local era=1+technologies//4
    local garrison=0
    if garrisonKind and Rules.units[garrisonKind].strength>0 then garrison=math.floor(Rules.units[garrisonKind].strength*25/100) end
    return 14+population+3*(era-1)+(if walls then 8 else 0)+garrison
end
local function referenceDamage(strength: number,kind: string,hp: number,terrain: string,fortified: boolean,cover: boolean): number
    local ranged=math.floor(strength*60/100)
    local percent=(if terrain=="Hills" or terrain=="Forest" then 25 else 0)+(if fortified then 50 else 0)+(if cover then 33 else 0)
    local defense=math.max(3,Rules.units[kind].strength)*(100+percent)/100*(0.5+hp/200)
    return math.clamp(math.floor(30*math.max(1,ranged)/math.max(1,defense)+0.5),8,65)
end

-- 1. Rules: the city-combat numbers and the Catapult's siege bonus.
do
    assert(Rules.cityBaseStrength==14 and Rules.cityStrengthPerEra==3 and Rules.garrisonPercent==25 and Rules.cityStrikeRange==2 and Rules.cityStrikePercent==60)
    for id, rule in Rules.units do assert(rule.siegePercent==(if id=="Catapult" then 50 else 0),id.." siege percentage") end
    local rules=Game.getRules(); assert(rules.cityStrikeRange==2 and rules.units.Catapult.siegePercent==50)
    rules.units.Catapult.siegePercent=99; assert(Game.getRules().units.Catapult.siegePercent==50,"getRules is detached")
end

-- 2. City combat strength: population, era, Walls and a military garrison; the snapshot reports it for own cities.
do
    local cases=0
    for _, population in {1,4,9} do
        for _, technologies in {0,4,9,16} do
            for _, walls in {false,true} do
                for _, garrisonKind in {"None","Warrior","Scout","Worker","Archer","Rifleman"} do
                    -- Archer and Rifleman need their technologies, so they appear only with all sixteen.
                    if (garrisonKind=="Archer" or garrisonKind=="Rifleman") and technologies<16 then continue end
                    local s=fresh(); local city=firstCity(s,1)
                    city.population=population; city.buildings=if walls then {"Walls"} else {}
                    s.players[1].technologies=table.move(Rules.technologyOrder,1,technologies,1,{})
                    if garrisonKind~="None" then place(s,1,garrisonKind,city.tileId) end
                    assert(Save.valid(Game.serialize(s)),"strength fixture must be valid")
                    local view=viewCity(Game.snapshot(s,1),city.id)
                    local expected=referenceStrength(population,technologies,walls,if garrisonKind=="None" then nil else garrisonKind)
                    assert(view.strength==expected,"strength "..view.strength.." vs "..expected)
                    assert(view.rangedStrength==math.floor(expected*60/100),"ranged strength is 60% rounded down")
                    cases += 1
                end
            end
        end
    end
    assert(cases==3*4*2*4+3*2*2,"cases "..cases)
    -- Concrete values: a new size-1 city strikes with 9; Walls, a Warrior garrison and the fifth era bring it to 22.
    local s=fresh(); local view=viewCity(Game.snapshot(s,1),home.id); assert(view.strength==15 and view.rangedStrength==9)
    firstCity(s,1).buildings={"Walls"}; place(s,1,"Warrior",home.tileId); s.players[1].technologies=table.clone(Rules.technologyOrder)
    view=viewCity(Game.snapshot(s,1),home.id); assert(view.strength==15+8+2+12 and view.rangedStrength==22)
    -- Garrison shares: Scout 1, Warrior 2, Archer 1 (its melee strength 5), Rifleman 10; a civilian adds nothing.
end

-- 3. A strike: exact damage against the reference, equal to the query and snapshot previews; the city takes no damage
--    and the garrison keeps its movement; one strike per round.
local function strikeCase(setup: any): (any,any,any)
    local s=fresh(); local city=firstCity(s,1)
    city.population=setup.population or 1; city.buildings=if setup.walls then {"Walls"} else {}
    s.players[1].technologies=table.move(Rules.technologyOrder,1,setup.technologies or 0,1,{})
    s.players[2].technologies=table.clone(Rules.technologyOrder)
    local garrison=if setup.garrison then place(s,1,setup.garrison,city.tileId) else nil
    local tileId=(if setup.distance==1 then ring1 else ring2)[setup.slot or 1]
    clear(s,tileId,setup.terrain)
    local kind=setup.kind or "Warrior"
    local target=place(s,2,kind,tileId,setup.hp)
    target.fortified=setup.fortified==true and Rules.units[kind].strength>0
    if setup.cover then target.promotions={"Cover1"}; target.level=1; target.xp=10 end
    assert(Save.valid(Game.serialize(s)),"strike fixture must be valid")
    local before=Game.serialize(s)
    local preview,reason=Game.previewCityStrike(s,1,city.id,target.id); assert(preview,reason)
    assert(equal(before,Game.serialize(s)),"a preview must not mutate the state")
    local view=Game.snapshot(s,1); local cv=viewCity(view,city.id)
    assert(cv.strikeReady and cv.canStrike and equal(cv.strikeTargets,{target.id}),"the target is listed")
    local listed=view.cityStrikePreviews[tostring(city.id)]
    assert(#listed==1 and equal(listed[1],preview),"the snapshot preview equals the query")
    assert(preview.exact and preview.received==0 and preview.cityId==city.id and preview.unitId==target.id and preview.tileId==tileId and preview.defenderHp==target.hp)
    assert(preview.rangedStrength==cv.rangedStrength)
    local expected=referenceDamage(cv.strength,kind,target.hp,setup.terrain or "Plains",target.fortified,setup.cover==true)
    assert(preview.dealt==expected,"preview "..preview.dealt.." vs reference "..expected)
    local cityHp,hp,revision=city.hp,target.hp,s.revision
    local garrisonMoves=if garrison then garrison.moves else nil
    apply(s,1,{kind="CityRangedStrike",cityId=city.id,targetUnitId=target.id})
    assert(s.revision==revision+1 and city.hp==cityHp,"one revision; the city takes no damage")
    if garrison then assert(garrison.moves==garrisonMoves and garrison.hp==Rules.units[garrison.kind].hp,"the garrison is untouched") end
    local e=lastEvent(s,"CityStrike")
    assert(e and e.cityId==city.id and e.unitId==target.id and e.tileId==tileId and e.ownerId==1 and e.amount==expected and e.unitKind==kind)
    local after=unitById(s,target.id)
    if hp-expected<=0 then assert(after==nil and preview.defenderDefeated=="Yes") else assert(after.hp==hp-expected and preview.defenderDefeated=="No") end
    -- One strike per round.
    cv=viewCity(Game.snapshot(s,1),city.id)
    assert(not cv.strikeReady and not cv.canStrike and #cv.strikeTargets==0 and #Game.snapshot(s,1).cityStrikePreviews[tostring(city.id)]==0)
    if after then
        rejected(s,1,{kind="CityRangedStrike",cityId=city.id,targetUnitId=target.id},"a second strike this round","This city has used its strike this round.")
        local none,message=Game.previewCityStrike(s,1,city.id,target.id); assert(none==nil and message=="This city has used its strike this round.")
    end
    assert(Save.valid(Game.serialize(s)))
    return s,preview,after
end
do
    -- Worked examples: a new size-1 city (ranged 9) against a full Warrior on Plains deals 27; with Walls (ranged 13)
    -- 39; fortified on Hills 15; at range 1 and range 2 alike.
    local _,p=strikeCase({}); assert(p.dealt==27)
    _,p=strikeCase({distance=1}); assert(p.dealt==27)
    _,p=strikeCase({walls=true}); assert(p.dealt==39)
    _,p=strikeCase({terrain="Hills",fortified=true}); assert(p.dealt==15)
    -- Cover I counts against a city strike (it is a ranged strike).
    local _,covered=strikeCase({cover=true}); assert(covered.dealt<27)
    -- A sweep over the city's strength and the target's kind, health, terrain, fortification and Cover.
    local kinds={"Warrior","Archer","Pikeman","Rifleman","Worker","Settler","Knight","Catapult"}
    local terrains={"Plains","Hills","Forest","Grassland"}
    local kills,cases=0,0
    for i=0,95 do
        local kind=kinds[i%#kinds+1]
        local garrison=({"None","Warrior","Scout","Warrior"})[(i//2)%4+1]
        local setup={kind=kind,population=1+(i*7)%9,technologies=(i*5)%17,walls=(i//3)%2==1,garrison=if garrison=="None" then nil else garrison,
            distance=1+(i//5)%2,slot=1+(i%6),terrain=terrains[(i//7)%#terrains+1],hp=math.max(1,Rules.units[kind].hp-((i*23)%90)),
            fortified=(i//4)%2==1,cover=Rules.units[kind].strength>0 and (i//11)%2==1}
        local _,_,after=strikeCase(setup)
        if not after then kills += 1 end
        cases += 1
    end
    assert(cases==96 and kills>0 and kills<cases,"the sweep covers kills and survivals ("..kills..")")
end

-- 4. Kills, events and experience: the target gains a ranged defender's experience, a civilian gains none, a killed
--    unit raises a loser-owned UnitLost with cause CityStrike; the strike event is visible to the target's owner.
do
    local s,_,after=strikeCase({})
    assert(after.xp==Rules.experience.rangedDefense,"a struck military unit gains 2 experience")
    local seen=Game.snapshot(s,2).events; assert(countEvents(seen,"CityStrike")==1,"the target's owner sees the strike")
    local _,_,worker=strikeCase({kind="Worker",hp=50}); assert(worker==nil,"a full-health worker dies to a size-1 city")
    local s2,_,survivor=strikeCase({kind="Rifleman",hp=100,fortified=true,terrain="Hills"})
    assert(survivor and survivor.xp==2,"a fortified Rifleman on Hills survives and gains experience")
    for _, u in s2.units do if u.ownerId==1 then assert(u.xp==nil,"cities give their owner's units nothing") end end
    local killed,kp=strikeCase({hp=5})
    local lost=lastEvent(killed,"UnitLost")
    assert(kp.defenderDefeated=="Yes" and lost and lost.ownerId==2 and lost.cause=="CityStrike" and lost.byOwnerId==1 and lost.unitKind=="Warrior" and lost.amount==kp.dealt)
    -- The loser sees its UnitLost even when the dead unit was its only eye on the tile.
    local losses=0; for _, e in Game.snapshot(killed,2).events do if e.kind=="UnitLost" and e.cause=="CityStrike" then losses += 1 end end
    assert(losses==1)
    assert(Save.valid(Game.serialize(killed)))
    local restored: any=Game.restore(Game.serialize(killed)); assert(restored and equal(Game.serialize(restored),Game.serialize(killed)))
end

-- 5. Validation: every rejected command leaves the state unchanged, and hidden, missing, friendly, out-of-range and
--    peaceful targets share one message.
do
    local s=fresh(); local city=firstCity(s,1)
    local target=place(s,2,"Warrior",ring2[1]); local friend=place(s,1,"Warrior",ring1[1]); local far=place(s,2,"Warrior",ring3[1])
    local hidden: any=nil
    for _, t in s.tiles do
        local ok=Rules.terrains[t.terrain].passable
        for _, c in s.cities do if WorldMap.distance(graph,t.id,c.tileId)<=3 then ok=false end end
        for _, u in s.units do if WorldMap.distance(graph,t.id,u.tileId)<=3 then ok=false end end
        if ok then hidden=place(s,2,"Warrior",t.id); break end
    end
    assert(hidden,"a unit out of sight")
    assert(Save.valid(Game.serialize(s)))
    local view=viewCity(Game.snapshot(s,1),city.id); assert(equal(view.strikeTargets,{target.id}),"only the enemy in range")
    local generic="Choose a visible enemy unit within the city's range."
    rejected(s,1,{kind="CityRangedStrike",cityId=city.id,targetUnitId=far.id},"three hexes away",generic)
    rejected(s,1,{kind="CityRangedStrike",cityId=city.id,targetUnitId=hidden.id},"a hidden unit",generic)
    rejected(s,1,{kind="CityRangedStrike",cityId=city.id,targetUnitId=999999},"a missing unit",generic)
    rejected(s,1,{kind="CityRangedStrike",cityId=city.id,targetUnitId=friend.id},"an own unit",generic)
    rejected(s,1,{kind="CityRangedStrike",cityId=rival.id,targetUnitId=friend.id},"the rival's city","Select your city.")
    rejected(s,1,{kind="CityRangedStrike",cityId=999,targetUnitId=target.id},"a missing city","Select your city.")
    rejected(s,2,{kind="CityRangedStrike",cityId=rival.id,targetUnitId=friend.id},"out of turn","Wait for your civilization's turn.")
    rejected(s,1,{kind="CityRangedStrike",cityId=city.id},"a missing target","Missing command field.")
    rejected(s,1,{kind="CityRangedStrike",cityId=city.id,targetUnitId=target.id,tileId=target.tileId},"an extra field","Invalid command fields.")
    rejected(s,1,{kind="CityRangedStrike",cityId=city.id,targetUnitId=1.5},"a fractional target","Invalid unit identifier.")
    rejected(s,1,{kind="CityRangedStrike",cityId=city.id,targetUnitId=tostring(target.id)},"a text target","Invalid unit identifier.")
    rejected(s,1,{kind="CityRangedStrike",cityId=-1,targetUnitId=target.id},"a negative city","Invalid city identifier.")
    rejected(s,1,{kind="CityRangedStrike",unitId=target.id,targetUnitId=target.id},"a unit instead of a city","Invalid command fields.")
    -- The query answers the same messages and never mutates.
    for _, id in {far.id,hidden.id,999999,friend.id} do
        local none,message=Game.previewCityStrike(s,1,city.id,id); assert(none==nil and message==generic)
    end
    local none,message=Game.previewCityStrike(s,1,rival.id,target.id); assert(none==nil and message=="Select your city.")
    -- A hidden unit and a missing id cannot be told apart, and moving the hidden unit out of the world changes nothing.
    local without=Game.restore(Game.serialize(s)) :: any
    for i,u in without.units do if u.id==hidden.id then table.remove(without.units,i); break end end
    assert(equal(Game.snapshot(without,1).cityStrikePreviews,Game.snapshot(s,1).cityStrikePreviews))
    -- Peace: no targets and a rejected strike.
    local peace=Game.restore(Game.serialize(s)) :: any; peace.diplomacy.status="Peace"; peace.diplomacy.peaceUntil=peace.turn+8
    assert(Save.valid(Game.serialize(peace)))
    local pv=viewCity(Game.snapshot(peace,1),city.id); assert(pv.strikeReady and not pv.canStrike and #pv.strikeTargets==0)
    rejected(peace,1,{kind="CityRangedStrike",cityId=city.id,targetUnitId=target.id},"at peace",generic)
    -- A unit inside a city is never a target (only a hand-made state can bring one within range).
    local inside=Game.restore(Game.serialize(s)) :: any
    local other=firstCity(inside,2); local oldTile=other.tileId
    inside.tiles[ring2[1]].ownerId=2; other.tileId=ring2[1]; inside.tiles[oldTile].ownerId=nil
    assert(Save.valid(Game.serialize(inside)),"hand-made state with a city two hexes away")
    rejected(inside,1,{kind="CityRangedStrike",cityId=city.id,targetUnitId=target.id},"a unit in a city",generic)
    assert(#viewCity(Game.snapshot(inside,1),city.id).strikeTargets==0)
end

-- 6. Rounds: the strike returns next round; each civilization's cities strike on its own turn; a city founded during a
--    war strikes at once; a captured city cannot strike in the round of its capture.
do
    local s=fresh(); local city=firstCity(s,1)
    local enemy=place(s,2,"Warrior",ring2[1]); local own=place(s,1,"Warrior",ring2[2])
    -- Player 2's capital must reach player 1's unit for the second half; move it within range of its capital.
    local rivalRing=shell(s,graph,rival.tileId,2); local spot: number?=nil
    for _, id in rivalRing do
        local free=Rules.terrains[s.tiles[id].terrain].passable
        for _, u in s.units do if u.tileId==id then free=false end end
        if free then spot=id; break end
    end
    assert(spot); own.tileId=spot :: number
    assert(Save.valid(Game.serialize(s)))
    local turn=s.turn
    apply(s,1,{kind="CityRangedStrike",cityId=city.id,targetUnitId=enemy.id}); assert(city.strikeTurn==turn)
    apply(s,1,{kind="EndTurn"})
    -- Player 2's turn in the same round: its own city is ready; player 1's projection shows its city spent but no actions.
    local v2=viewCity(Game.snapshot(s,2),rival.id); assert(v2.strikeReady and v2.canStrike and equal(v2.strikeTargets,{own.id}))
    local v1=viewCity(Game.snapshot(s,1),city.id); assert(not v1.strikeReady and not v1.canStrike and #v1.strikeTargets==0)
    apply(s,2,{kind="CityRangedStrike",cityId=rival.id,targetUnitId=own.id}); assert(firstCity(s,2).strikeTurn==turn)
    apply(s,2,{kind="EndTurn"}); assert(s.turn==turn+1)
    v1=viewCity(Game.snapshot(s,1),city.id); assert(v1.strikeReady and v1.canStrike,"the strike returns in the next round")
    -- Out of turn the owner sees readiness but no actions; the query ignores turn ownership.
    local out=viewCity(Game.snapshot(s,2),rival.id); assert(out.strikeReady and not out.canStrike and #out.strikeTargets==0)
    assert(#Game.snapshot(s,2).cityStrikePreviews[tostring(rival.id)]==0)
    assert(Game.previewCityStrike(s,2,rival.id,own.id),"the query ignores turn ownership")
    -- A city founded during a war may strike at once.
    local t=fresh(); local site: number?=nil
    for _, id in ring3 do
        local ok=t.tiles[id].ownerId~=2; for _, c in t.cities do if WorldMap.distance(graph,id,c.tileId)<3 then ok=false end end
        if ok then site=id; break end
    end
    assert(site,"a free city site three hexes away")
    local settler=place(t,1,"Settler",site :: number); local foe: number?=nil
    for _, id in graph.neighbors[site :: number] do
        local ok=WorldMap.distance(graph,id,home.tileId)>=3 and Rules.terrains[t.tiles[id].terrain].passable
        for _, c in t.cities do if c.tileId==id then ok=false end end
        if ok then foe=id; break end
    end
    assert(foe); clear(t,foe :: number); local intruder=place(t,2,"Warrior",foe :: number)
    apply(t,1,{kind="FoundCity",unitId=settler.id})
    local newCity=t.cities[#t.cities]; assert(newCity.tileId==site and newCity.strikeTurn==nil)
    local nv=viewCity(Game.snapshot(t,1),newCity.id); assert(nv.canStrike and table.find(nv.strikeTargets,intruder.id))
    apply(t,1,{kind="CityRangedStrike",cityId=newCity.id,targetUnitId=intruder.id})
    -- Capture: player 1 takes a second rival city; it cannot strike this round, and can in the next.
    local c=fresh(); local cityTile: number?=nil
    for _, id in shell(c,graph,rival.tileId,3) do
        local ok=Rules.terrains[c.tiles[id].terrain].passable and WorldMap.distance(graph,id,home.tileId)>=3
        if ok then cityTile=id; break end
    end
    assert(cityTile); clear(c,cityTile :: number); c.tiles[cityTile :: number].ownerId=2
    local second: any={id=c.nextCity,ownerId=2,originalOwnerId=2,capital=false,tileId=cityTile :: number,name="Fixture",population=2,food=0,production=0,queue="Warrior",hp=1,buildings={},focus="Balanced"}
    table.insert(c.cities,second); c.nextCity += 1
    local approach: number?=nil
    for _, id in graph.neighbors[cityTile :: number] do
        local ok=Rules.terrains[c.tiles[id].terrain].passable; for _, other in c.cities do if other.tileId==id then ok=false end end
        if ok then approach=id; break end
    end
    assert(approach); clear(c,approach :: number)
    local attacker=place(c,1,"Swordsman",approach :: number); c.players[1].technologies=table.clone(Rules.technologyOrder)
    local victim: number?=nil
    for _, id in graph.neighbors[approach :: number] do
        local ok=Rules.terrains[c.tiles[id].terrain].passable and WorldMap.distance(graph,id,cityTile :: number)<=2
        for _, other in c.cities do if other.tileId==id then ok=false end end
        for _, u in c.units do if u.tileId==id then ok=false end end
        if ok then victim=id; break end
    end
    assert(victim); local bystander=place(c,2,"Warrior",victim :: number)
    assert(Save.valid(Game.serialize(c)),"capture fixture must be valid")
    apply(c,1,{kind="MoveUnit",unitId=attacker.id,tileId=cityTile :: number})
    assert(second.ownerId==1 and second.strikeTurn==c.turn and c.phase=="Playing","captured, and its strike counts as used")
    local cv=viewCity(Game.snapshot(c,1),second.id); assert(not cv.strikeReady and not cv.canStrike)
    rejected(c,1,{kind="CityRangedStrike",cityId=second.id,targetUnitId=bystander.id},"a city captured this round","This city has used its strike this round.")
    assert(Save.valid(Game.serialize(c)))
    apply(c,1,{kind="EndTurn"}); apply(c,2,{kind="EndTurn"})
    local following=viewCity(Game.snapshot(c,1),second.id)
    assert(following.strikeReady and following.canStrike and table.find(following.strikeTargets,bystander.id),"the captured city strikes next round")
    apply(c,1,{kind="CityRangedStrike",cityId=second.id,targetUnitId=bystander.id})
end

-- 7. Siege: the Catapult adds 50% against a city tile (undefended or garrisoned); other units and unit targets are
--    unchanged; previews still bracket the applied result.
do
    local function siegeSetup(attackerKind: string,garrison: boolean): (any,any,number)
        local s=fresh(); s.players[1].technologies=table.clone(Rules.technologyOrder)
        local target=firstCity(s,2); target.buildings={}; target.hp=150; clear(s,target.tileId)
        local from: number?=nil
        for _, id in shell(s,graph,target.tileId,2) do
            local ok=Rules.terrains[s.tiles[id].terrain].passable and WorldMap.distance(graph,id,home.tileId)>=2
            if ok then from=id; break end
        end
        assert(from); clear(s,from :: number)
        local attacker=place(s,1,attackerKind,from :: number)
        if garrison then place(s,2,"Warrior",target.tileId) end
        assert(Save.valid(Game.serialize(s)))
        return s,attacker,target.tileId
    end
    local function cityDefense(s: any): number
        local target=firstCity(s,2); return (14+target.population)*(100+0)/100
    end
    for _, kind in {"Catapult","Archer"} do
        local s,attacker,tileId=siegeSetup(kind,false)
        local preview=Game.previewAttack(s,1,attacker.id,tileId); assert(preview and preview.target=="City" and preview.hiddenDefense)
        local rule=Rules.units[kind]; local percent=if kind=="Catapult" then 50 else 0
        local attack=rule.rangedStrength*(0.5+rule.hp/200)*(100+percent)/100
        assert(preview.dealtMax==math.clamp(math.floor(30*attack/cityDefense(s)+0.5),8,65),kind.." against an undefended city")
        local hp=firstCity(s,2).hp
        apply(s,1,{kind="RangedAttack",unitId=attacker.id,tileId=tileId})
        local dealt=hp-firstCity(s,2).hp; assert(dealt>=preview.dealtMin and dealt<=preview.dealtMax)
        local g,gAttacker,gTile=siegeSetup(kind,true)
        local gp=Game.previewAttack(g,1,gAttacker.id,gTile); assert(gp and gp.target=="Unit" and gp.hiddenDefense)
        local defense=10*(100+0)/100*(0.5+100/200)
        assert(gp.dealtMax==math.clamp(math.floor(30*attack/defense+0.5),8,65),kind.." against a garrisoned city")
    end
    -- The bonus is 50% exactly: 22 ranged, full health, size-1 city on Plains: 30 x 22 x 0.825 x 1.5 / 15 = 54.
    local s,attacker,tileId=siegeSetup("Catapult",false); firstCity(s,2).population=1
    assert((Game.previewAttack(s,1,attacker.id,tileId) :: any).dealtMax==54)
end

-- 8. The AI strikes from each ready city: a kill first, a military unit over a civilian, then the target left weakest;
--    never at peace; one strike per city per round; deterministic.
do
    local function solo(): (any,any)
        local s: any=Game.new(81,{humanPlayers=1,radius=8})
        apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id})
        apply(s,1,{kind="DeclareWar",targetId=2})
        for i=#s.units,1,-1 do if s.units[i].ownerId==2 then table.remove(s.units,i) end end
        local g=WorldMap.fromTiles(s.tiles,s.radius); local capital=firstCity(s,2)
        local near=shell(s,g,capital.tileId,2)
        local free={}
        for _, id in near do
            local ok=WorldMap.distance(g,id,firstCity(s,1).tileId)>=3
            for _, u in s.units do if u.tileId==id then ok=false end end
            if ok then clear(s,id); table.insert(free,id) end
        end
        assert(#free>=3,"room around the AI capital")
        return s,free
    end
    local function run(setup: (any,{number})->()): any
        local s,free=solo(); setup(s,free); assert(Save.valid(Game.serialize(s)),"AI fixture must be valid")
        apply(s,1,{kind="EndTurn"}); return s
    end
    -- A healthy Warrior (lower id) and a wounded one: the wounded one dies.
    local healthy,wounded=0,0
    local s=run(function(t,free) healthy=place(t,1,"Warrior",free[1]).id; wounded=place(t,1,"Warrior",free[2],15).id end)
    assert(unitById(s,wounded)==nil and unitById(s,healthy).hp==100,"the kill comes first")
    local e=lastEvent(s,"CityStrike"); assert(e and e.ownerId==2 and e.unitId==wounded and countEvents(s.events,"CityStrike")==1)
    local lost=lastEvent(s,"UnitLost"); assert(lost and lost.ownerId==1 and lost.cause=="CityStrike" and lost.byOwnerId==2)
    -- Two kills on offer: the military unit before the worker (lower id).
    local worker,soldier=0,0
    s=run(function(t,free) worker=place(t,1,"Worker",free[1]).id; soldier=place(t,1,"Warrior",free[2],10).id end)
    assert(unitById(s,soldier)==nil and unitById(s,worker)~=nil,"a military kill before a civilian kill")
    -- No kill: the target left with fewer hit points (open ground rather than fortified on Hills, despite the lower id).
    local sheltered,exposed=0,0
    s=run(function(t,free)
        clear(t,free[1],"Hills"); local a=place(t,1,"Warrior",free[1]); a.fortified=true; a.moves=0; sheltered=a.id
        exposed=place(t,1,"Warrior",free[2]).id
    end)
    e=lastEvent(s,"CityStrike"); assert(e and e.unitId==exposed and countEvents(s.events,"CityStrike")==1,"the exposed unit is struck")
    assert(unitById(s,sheltered) and unitById(s,exposed),"neither dies")
    -- At peace the AI never strikes.
    s=run(function(t,free) t.diplomacy.status="Peace"; t.diplomacy.peaceUntil=t.turn+8; place(t,1,"Warrior",free[1],15) end)
    assert(countEvents(s.events,"CityStrike")==0,"no strike at peace")
    -- Deterministic: the same setup gives the same state.
    local function setup(t: any,free: {number}) place(t,1,"Warrior",free[1],60); place(t,1,"Scout",free[2]); place(t,1,"Worker",free[3]) end
    local once=run(setup); assert(countEvents(once.events,"CityStrike")==1)
    assert(equal(Game.serialize(once),Game.serialize(run(setup))),"AI strikes are deterministic")
end

-- 9. Fog: a rival city shows none of the city-combat fields; previews exist only for the actor's own cities.
do
    local s=fresh(); local watcher=place(s,2,"Warrior",ring2[1])
    assert(Save.valid(Game.serialize(s)))
    local view=Game.snapshot(s,2); local seenCity=viewCity(view,home.id)
    assert(seenCity,"player 2 sees player 1's capital")
    for _, key in {"strength","rangedStrength","strikeReady","canStrike","strikeTargets","strikeTurn","buildings"} do assert(seenCity[key]==nil,"rival city leaks "..key) end
    assert(view.cityStrikePreviews[tostring(home.id)]==nil,"no preview list for a rival city")
    for key in view.cityStrikePreviews do assert(firstCity(s,2).id==tonumber(key),"only own cities") end
    -- The striking city's own view hides the stored field and shows the derived ones.
    apply(s,1,{kind="CityRangedStrike",cityId=home.id,targetUnitId=watcher.id})
    local own=viewCity(Game.snapshot(s,1),home.id); assert(own.strikeTurn==nil and own.strikeReady==false)
    -- The rival's view of the city never carries buildings or strength (its unit's lost hit points are its only clue).
    local after=viewCity(Game.snapshot(s,2),home.id); assert(after.strength==nil and after.buildings==nil)
end

-- 10. Saves: a pre-G6 save restores unchanged and gains no field without strikes; strikeTurn, the CityStrike event,
--     its cityId and the CityStrike cause are validated.
do
    local map=WorldMap.generate(124,3)
    -- A save written before G4 has no features or rivers.
    for _, t in map.tiles do t.feature=nil; t.river=nil end
    local function at(x: number,y: number): number return WorldMap.tileId(map,x,y) :: number end
    local hub,west=at(0,0),at(-2,0); assert(WorldMap.distance(map,hub,west)==2)
    local rivalTile: number=0
    for id=1,#map.tiles do if WorldMap.distance(map,hub,id)==3 and WorldMap.distance(map,west,id)>=3 then rivalTile=id; break end end
    assert(rivalTile>0)
    for _, id in {hub,west,rivalTile} do map.tiles[id].terrain="Plains"; map.tiles[id].resource=nil; map.tiles[id].improvement=nil; map.tiles[id].road=nil; map.tiles[id].ownerId=nil end
    map.tiles[hub].ownerId=1
    local explored={}; for id=1,#map.tiles do table.insert(explored,id) end
    local legacyState: any={seed=124,radius=3,difficulty="Normal",humanPlayers=2,forest=false,maxTurns=120,turn=5,revision=9,activePlayerId=1,phase="Playing",tiles=map.tiles,
        units={{id=1,ownerId=1,kind="Warrior",tileId=hub,hp=100,moves=2,fortified=false,level=0},
            {id=2,ownerId=2,kind="Warrior",tileId=west,hp=100,moves=2,fortified=false,level=0},
            {id=3,ownerId=2,kind="Settler",tileId=rivalTile,hp=50,moves=2,fortified=false,level=0}},
        cities={{id=1,ownerId=1,originalOwnerId=1,capital=true,tileId=hub,name="Fixture",population=2,food=0,production=0,queue="Warrior",hp=150,buildings={},focus="Balanced"}},players={},
        diplomacy={status="War",peaceUntil=0},trades={},events={{id=1,kind="FoundCity",message="City founded.",tileId=hub,ownerId=1}},nextEvent=2,nextUnit=4,nextCity=2,nextTrade=1,log={}}
    for id=1,2 do table.insert(legacyState.players,{id=id,human=true,gold=200,science=0,culture=0,happiness=9,technologies={},policies={},explored=table.clone(explored),resources={},income={food=0,production=0,gold=0,science=0,culture=0,maintenance=0}}) end
    local legacy={format="unciv-luau-base",version=1,state=legacyState}
    assert(Save.valid(legacy),"the legacy fixture is a valid version-1 save")
    local restored: any,err=Game.restore(legacy); assert(restored and err==nil,err)
    assert(equal(Game.serialize(restored),legacy),"restore keeps every stored field and adds none")
    local cv=viewCity(Game.snapshot(restored,1),1)
    assert(cv.strikeReady and cv.canStrike and equal(cv.strikeTargets,{2}) and cv.strength==14+2+2,"a legacy city strikes at once (garrison Warrior +2)")
    -- No strike: no new field.
    local quiet: any=Game.restore(legacy); assert(quiet)
    apply(quiet,1,{kind="EndTurn"}); apply(quiet,2,{kind="EndTurn"})
    for _, c in Game.serialize(quiet).state.cities do assert(c.strikeTurn==nil,"no strikeTurn without a strike") end
    -- A strike writes strikeTurn and a CityStrike event with cityId; both round-trip.
    apply(restored,1,{kind="CityRangedStrike",cityId=1,targetUnitId=2})
    local saved=Game.serialize(restored); assert(saved.state.cities[1].strikeTurn==5)
    local again: any=Game.restore(saved); assert(again and equal(Game.serialize(again),saved))
    rejected(again,1,{kind="CityRangedStrike",cityId=1,targetUnitId=2},"the restored strike is still spent","This city has used its strike this round.")
    local function variant(change: (any)->()): any local value=Game.serialize(restored); change(value.state); return value end
    local function accepts(change: (any)->(),label: string) assert(Save.valid(variant(change)),label.." rejected") end
    local function rejects(change: (any)->(),label: string)
        local value=variant(change); assert(not Save.valid(value),label.." accepted")
        local loaded,message=Save.restore(value); assert(loaded==nil and type(message)=="string"); assert(Game.restore(value)==nil)
    end
    accepts(function(s) s.cities[1].strikeTurn=1 end,"an old strike round")
    accepts(function(s) s.cities[1].strikeTurn=nil end,"no strike round")
    rejects(function(s) s.cities[1].strikeTurn=6 end,"a future strike round")
    rejects(function(s) s.cities[1].strikeTurn=0 end,"round zero")
    rejects(function(s) s.cities[1].strikeTurn=2.5 end,"a fractional round")
    rejects(function(s) s.cities[1].strikeTurn="5" end,"a text round")
    rejects(function(s) s.cities[1].strikeReady=true end,"a derived field stored in a save")
    local function strikeEvent(s: any): any for _, e in s.events do if e.kind=="CityStrike" then return e end end; error("no strike event") end
    accepts(function(s) strikeEvent(s).cityId=1 end,"a known city id")
    rejects(function(s) strikeEvent(s).cityId=2 end,"a city id not yet issued")
    rejects(function(s) strikeEvent(s).cityId=0 end,"city id zero")
    rejects(function(s) strikeEvent(s).cityId="1" end,"a text city id")
    rejects(function(s) strikeEvent(s).kind="CityStrikes" end,"an unknown event kind")
    accepts(function(s) table.insert(s.events,{id=s.nextEvent,kind="UnitLost",message="x",unitId=2,ownerId=2,cause="CityStrike",byOwnerId=1,unitKind="Warrior",amount=40}); s.nextEvent += 1 end,"a UnitLost caused by a city strike")
    rejects(function(s) table.insert(s.events,{id=s.nextEvent,kind="UnitLost",message="x",cause="CityBombard"}); s.nextEvent += 1 end,"an unknown cause")
end

-- 11. Determinism: solo wars in which the human's cities and the AI's cities strike replay identically, with and
--     without saves between turns. The human defends: each turn its cities strike the first listed target.
do
    local function run(resume: boolean): (any,number,number,number)
        local s: any=Game.new(94,{humanPlayers=1,radius=5,difficulty="Hard"})
        apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id})
        local human,ai,kills=0,0,0
        for turn=1,40 do
            if s.phase~="Playing" then break end
            if turn==2 and s.diplomacy.status~="War" then apply(s,1,{kind="DeclareWar",targetId=2}) end
            local view=Game.snapshot(s,1)
            local ids={}; for id in view.cityStrikePreviews do table.insert(ids,tonumber(id) :: number) end; table.sort(ids)
            for _, id in ids do
                local list=view.cityStrikePreviews[tostring(id)]
                if #list>0 then
                    local expected=list[1]
                    apply(s,1,{kind="CityRangedStrike",cityId=id,targetUnitId=expected.unitId}); human += 1
                    local e=lastEvent(s,"CityStrike"); assert(e.amount==expected.dealt and e.unitId==expected.unitId,"the applied strike equals its preview")
                end
            end
            local before=s.nextEvent
            apply(s,1,{kind="EndTurn"})
            for _, e in s.events do
                if e.id>=before and e.kind=="CityStrike" then ai += 1; assert(e.ownerId==2) end
                if e.id>=before and e.kind=="UnitLost" and e.cause=="CityStrike" then kills += 1; assert(e.ownerId==1 and e.byOwnerId==2) end
            end
            if resume then s=Game.restore(Game.serialize(s)) end
        end
        return Game.serialize(s),human,ai,kills
    end
    local first,human,ai,kills=run(false); local second=run(false); local resumed=run(true)
    assert(equal(first,second) and equal(first,resumed),"city strikes are deterministic")
    assert(human>0 and ai>0 and kills>0,"the replay must include human strikes, AI strikes and kills")
    print(string.format("  determinism run: %d human city strikes, %d AI city strikes (%d kills), phase %s at turn %d",human,ai,kills,first.state.phase,first.state.turn))
end

print("base city combat: city strength, once-per-round CityRangedStrike with exact previews, kills, events and experience, validation, rounds and capture, Catapult siege, AI strikes, fog-safe fields, legacy saves and determinism passed")
