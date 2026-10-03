--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original fixtures for G9 barbarians: the rules and the match option, deterministic camp placement, caps and pacing,
-- clearing camps and their reward, the experience cap, combat with exact previews (in both directions), city strikes,
-- the zone of control, the barbarian and AI behaviour, fog, saves (legacy saves and validation), deterministic replays
-- with and without saves, and the Huge-map payload.
local Game = require("../../src/simulation/BaseGame")
local Save = require("../../src/simulation/BaseSave")
local WorldMap = require("../../src/simulation/WorldMap")
local Rules = require("../../src/simulation/BaseRules")
local B: any = Rules.barbarians
local function equal(a: any,b: any): boolean
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in a do if not equal(v,b[k]) then return false end end
    for k in b do if a[k]==nil then return false end end; return true
end
local function apply(s: any,owner: number,command: any)
    local result=Game.apply(s,owner,command); assert(result.ok,result.message)
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
local function viewUnit(view: any,id: number): any
    for _, u in view.units do if u.id==id then return u end end; return nil
end
local function eventsAfter(s: any,before: number,kind: string): {any}
    local list={}; for _, e in s.events do if e.id>=before and e.kind==kind then table.insert(list,e) end end; return list
end
local function barbarians(s: any): {any}
    local list={}; for _, u in s.units do if u.ownerId==0 then table.insert(list,u) end end; return list
end
local function place(s: any,owner: number,kind: string,tileId: number,hp: number?): any
    local u={id=s.nextUnit,ownerId=owner,kind=kind,tileId=tileId,hp=hp or Rules.units[kind].hp,moves=Rules.units[kind].moves,fortified=false,level=0}
    table.insert(s.units,u); s.nextUnit += 1; return u
end
local function addCamp(s: any,tileId: number): any
    local camp={id=s.barbarians.nextCamp,tileId=tileId,founded=s.turn,lastSpawn=s.turn}
    table.insert(s.barbarians.camps,camp); s.barbarians.nextCamp += 1; return camp
end
local function clear(s: any,id: number,terrain: string?)
    local t=s.tiles[id]; t.terrain=terrain or "Plains"; t.resource=nil; t.improvement=nil; t.road=nil; t.feature=nil
end
local function adjacent(graph: any,a: number,b: number): boolean return table.find(graph.neighbors[a],b)~=nil end
-- One full round in a two-human match: player 1 and player 2 end their turns, then the barbarians act.
local function round(s: any) apply(s,1,{kind="EndTurn"}); apply(s,2,{kind="EndTurn"}) end
local function bytes(v: any): number
    local t=type(v)
    if t=="number" then return #tostring(v) elseif t=="string" then return #v+2 elseif t=="boolean" then return if v then 4 else 5 end
    if t=="table" then local n=2; for k,c in v do n += (if type(k)=="string" then #k+3 else #tostring(k)+1)+bytes(c)+1 end; return n end
    return 4
end
local function paceOf(maxTurns: number): number return math.clamp(math.floor(maxTurns*100/120+0.5),50,200) end
local function rounds(n: number,maxTurns: number,difficulty: string): number
    return math.max(1,math.floor(n*paceOf(maxTurns)*B.difficultyPercent[difficulty]/10000+0.5))
end

-- The arena: a two-human match at peace (barbarians are hostile whatever the diplomacy), barbarians on, every unit
-- removed and player 1's capital ringed by cleared Plains to three hexes; features and rivers are stripped.
local function arenaState(): any
    local s: any=Game.new(71,{humanPlayers=2,radius=8,barbarians=true})
    for _, t in s.tiles do t.feature=nil; t.river=nil end
    apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id}); apply(s,1,{kind="EndTurn"})
    apply(s,2,{kind="FoundCity",unitId=firstUnit(s,2,"Settler").id}); apply(s,2,{kind="EndTurn"})
    s.units={}; return s
end
local base=arenaState()
local graph=WorldMap.fromTiles(base.tiles,base.radius)
local home=firstCity(base,1); local rivalCity=firstCity(base,2)
local function shell(center: number,d: number): {number}
    local cityTiles={}; for _, c in base.cities do cityTiles[c.tileId]=true end
    local ids={}
    for _, t in base.tiles do if not cityTiles[t.id] and WorldMap.distance(graph,t.id,center)==d then table.insert(ids,t.id) end end
    table.sort(ids); return ids
end
local ring1,ring2,ring3=shell(home.tileId,1),shell(home.tileId,2),shell(home.tileId,3)
assert(#ring1==6 and #ring2>=8 and #ring3>=8,"player 1's capital needs room around it")
assert(WorldMap.distance(graph,home.tileId,rivalCity.tileId)>=7,"the rival city stays out of the arena")
for _, list in {ring1,ring2,ring3} do for _, id in list do clear(base,id) end end
clear(base,home.tileId); home.population=1; home.buildings={}; home.hp=Rules.cityHp
assert(base.diplomacy.status=="Peace" and base.turn==2 and base.activePlayerId==1)
assert(Save.valid(Game.serialize(base)),"the arena is a valid state")
local baseSave=Game.serialize(base)
local function fresh(): any local s: any=Game.restore(baseSave); assert(s); return s end
-- A tile at least `d` hexes from player 1's capital and from the rival city, passable and free.
local function far(s: any,d: number,skip: {[number]: boolean}?): number
    for _, t in s.tiles do
        if Rules.terrains[t.terrain].passable and not (skip and skip[t.id]) and WorldMap.distance(graph,t.id,home.tileId)>=d and WorldMap.distance(graph,t.id,rivalCity.tileId)>=d then
            local free=true; for _, u in s.units do if u.tileId==t.id then free=false end end
            if free then return t.id end
        end
    end
    error("no far tile")
end
-- A pair (a in `first`, b in `second`) of adjacent tiles.
local function pair(first: {number},second: {number}): (number,number)
    for _, a in first do for _, b in second do if adjacent(graph,a,b) then return a,b end end end
    error("no adjacent pair")
end
-- Independent statement of one strike (numbers written out): attacker and defender on open ground or Hills, with
-- the defender's fortification. Returns dealt and received.
local function reference(attackerKind: string,attackerHp: number,defenderKind: string,defenderHp: number,terrain: string,fortified: boolean,flankers: number): (number,number)
    local a=Rules.units[attackerKind]; local d=Rules.units[defenderKind]
    local ranged=a.range>1
    local attack=math.max(1,if ranged then a.rangedStrength else a.attack)*(0.5+attackerHp/200)*(100+(if ranged then 0 else math.min(30,10*flankers)))/100
    local percent=(if terrain=="Hills" then 25 else 0)+(if fortified then 50 else 0)
    local defense=math.max(3,d.defense)*(100+percent)/100*(0.5+defenderHp/200)
    local dealt=math.clamp(math.floor(30*attack/math.max(1,defense)+0.5),8,65)
    local received=if ranged or d.strength==0 then 0 else math.clamp(math.floor(25*defense/attack+0.5),8,65)
    return dealt,received
end

-- 1. Rules.
do
    assert(B.ownerId==0 and B.firstCampTurn==10 and B.campInterval==8 and B.spawnInterval==6 and B.tilesPerCamp==320 and B.maxCamps==12)
    assert(B.unitsPerCamp==3 and B.maxUnits==30 and B.campCityDistance==4 and B.campSpacing==4 and B.huntRadius==5 and B.leashRadius==4)
    assert(B.campGold==25 and B.maxExperience==30 and B.healing==10)
    assert(B.difficultyPercent.Easy==150 and B.difficultyPercent.Normal==100 and B.difficultyPercent.Hard==75)
    -- One list per era (G7: six eras).
    assert(#B.eraUnits==#Rules.eras and #Rules.eras==6)
    for _, list in B.eraUnits do
        assert(#list>=2)
        for _, kind in list do assert(Rules.units[kind] and Rules.units[kind].strength>0,"barbarian kinds are military") end
        assert(Rules.units[list[1]].range==1,"a guard is a melee unit")
    end
    local rules: any=Game.getRules(); assert(rules.barbarians.campGold==25)
    rules.barbarians.campGold=99; assert((Game.getRules() :: any).barbarians.campGold==25,"getRules is detached")
    assert(table.isfrozen(Rules.barbarians) and table.isfrozen(Rules.barbarians.eraUnits[1]),"rules are frozen")
end

-- 2. The match option: on by default for a solo match, off for two humans, explicit either way, validated, echoed and
--    saved.
do
    local solo: any=Game.new(3,{radius=6}); assert(solo.barbarians and #solo.barbarians.camps==0 and solo.barbarians.nextCamp==1)
    assert(Game.snapshot(solo,1).barbarians==true and #Game.snapshot(solo,1).camps==0)
    local duo: any=Game.new(3,{radius=6,humanPlayers=2}); assert(duo.barbarians==nil and Game.snapshot(duo,2).barbarians==false)
    assert((Game.new(3,{radius=6,barbarians=false}) :: any).barbarians==nil)
    assert((Game.new(3,{radius=6,humanPlayers=2,barbarians=true}) :: any).barbarians~=nil)
    assert(not pcall(function() Game.new(3,{radius=6,barbarians="yes" :: any}) end),"a non-boolean option is rejected")
    local restored: any=Game.restore(Game.serialize(solo)); assert(restored.barbarians and equal(restored.barbarians,solo.barbarians))
    local restoredDuo: any=Game.restore(Game.serialize(duo)); assert(restoredDuo.barbarians==nil)
end

-- A scripted solo human for the long runs: found the city, research, strike, take attacks it survives and walk military
-- units into visible camps.
local function humanTurn(s: any)
    for _, u in s.units do if u.ownerId==1 and u.kind=="Settler" then Game.apply(s,1,{kind="FoundCity",unitId=u.id}) end end
    local view: any=Game.snapshot(s,1)
    if not s.players[1].research and #view.availableResearch>0 then apply(s,1,{kind="Research",technology=view.availableResearch[1].id}) end
    local cityIds={}; for id in view.cityStrikePreviews do table.insert(cityIds,tonumber(id) :: number) end; table.sort(cityIds)
    for _, id in cityIds do local list=view.cityStrikePreviews[tostring(id)]; if #list>0 then apply(s,1,{kind="CityRangedStrike",cityId=id,targetUnitId=list[1].unitId}) end end
    view=Game.snapshot(s,1)
    local campTiles={}; for _, camp in view.camps do campTiles[camp.tileId]=true end
    local unitIds={}; for id in view.legalMoves do table.insert(unitIds,tonumber(id) :: number) end; table.sort(unitIds)
    for _, id in unitIds do
        local u=unitById(s,id); if not u or u.moves<=0 then continue end
        local done=false
        for _, p in view.attackPreviews[tostring(id)] do
            if p.attackerDefeated=="No" then apply(s,1,{kind="MoveUnit",unitId=id,tileId=p.tileId}); done=true; break end
        end
        if not done then for _, tileId in view.legalMoves[tostring(id)] do if campTiles[tileId] then apply(s,1,{kind="MoveUnit",unitId=id,tileId=tileId}); break end end end
        view=Game.snapshot(s,1)
    end
    apply(s,1,{kind="EndTurn"})
end

-- 3. Spawning: deterministic camps on unseen land far from cities, preferring unexplored tiles, each with a guard of
--    the era's first kind, at the paced rounds and under the map's cap.
do
    local function run(seed: number,resume: boolean): (any,{any})
        local s: any=Game.new(seed,{radius=20})
        local map=WorldMap.fromTiles(s.tiles,s.radius)
        local appeared={}
        for _=1,40 do
            if s.phase~="Playing" then break end
            local known: {[number]: boolean}={}; for owner=1,2 do for _, id in s.players[owner].explored do known[id]=true end end
            local before={}; for _, camp in s.barbarians.camps do before[camp.id]=true end
            local roundNumber=s.turn
            humanTurn(s)
            for _, camp in s.barbarians.camps do
                if before[camp.id] then continue end
                table.insert(appeared,{id=camp.id,tileId=camp.tileId,founded=camp.founded})
                assert(camp.founded==roundNumber and camp.lastSpawn==roundNumber,"a camp records the round it appeared")
                assert(Rules.terrains[s.tiles[camp.tileId].terrain].passable,"a camp stands on passable land")
                for _, c in s.cities do assert(WorldMap.distance(map,camp.tileId,c.tileId)>=B.campCityDistance,"a camp keeps away from cities") end
                for _, other in s.barbarians.camps do if other.id~=camp.id then assert(WorldMap.distance(map,camp.tileId,other.tileId)>=B.campSpacing,"camps keep apart") end end
                for owner=1,2 do for _, v in Game.snapshot(s,owner).tiles do if v.id==camp.tileId then assert(not v.visible,"a camp appears out of sight") end end end
                assert(not known[camp.tileId],"an unexplored tile is preferred while one is free")
                local guard=nil; for _, u in s.units do if u.tileId==camp.tileId then guard=u end end
                -- The guard is the first kind of the lower of the two civilizations' eras (the highest era among each one's
                -- technologies).
                local function eraOf(list: {string}): number local e=1; for _, id in list do e=math.max(e,Rules.technologies[id].era) end; return e end
                local era=math.min(eraOf(s.players[1].technologies),eraOf(s.players[2].technologies))
                assert(guard and guard.ownerId==0 and guard.kind==B.eraUnits[era][1] and guard.moves==0,"a new camp starts with its guard")
            end
            assert(#s.barbarians.camps<=3,"Medium maps hold at most three camps")
            assert(Save.valid(Game.serialize(s)))
            if resume then s=Game.restore(Game.serialize(s)) end
        end
        return Game.serialize(s),appeared
    end
    local first,campsA=run(5,false); local second,campsB=run(5,false); local resumed,campsC=run(5,true)
    assert(equal(first,second) and equal(first,resumed) and equal(campsA,campsB) and equal(campsA,campsC),"camp spawning is deterministic with and without saves")
    assert(#campsA==3,"three camps by round 40 on a Medium map, got "..#campsA)
    assert(campsA[1].founded==10 and campsA[2].founded==18 and campsA[3].founded==26,"camps at rounds 10, 18 and 26")
    local _,other=run(6,false)
    local differs=false; for i, camp in other do if not campsA[i] or campsA[i].tileId~=camp.tileId then differs=true end end
    assert(differs,"another seed places camps elsewhere")
    print(string.format("  spawning: Medium seed 5 camps at tiles %d, %d, %d (rounds 10, 18, 26)",campsA[1].tileId,campsA[2].tileId,campsA[3].tileId))
end

-- 4. Pacing and caps: the first camp follows the match pace and difficulty; Tiny holds one camp and Huge twelve; the
--    barbarian unit count stays under its caps; the reward scales with the pace.
do
    for _, maxTurns in {60,120,240} do
        for _, difficulty in {"Easy","Normal","Hard"} do
            local s: any=Game.new(5,{radius=20,maxTurns=maxTurns,difficulty=difficulty})
            local expected=rounds(10,maxTurns,difficulty)
            local foundedAt: number?=nil
            for _=1,expected+1 do
                if s.phase~="Playing" then break end
                humanTurn(s)
                if #s.barbarians.camps>0 then foundedAt=s.barbarians.camps[1].founded; break end
            end
            assert(foundedAt==expected,string.format("%s %d rounds: first camp at %s, expected %d",difficulty,maxTurns,tostring(foundedAt),expected))
        end
    end
    assert(rounds(10,120,"Normal")==10 and rounds(10,60,"Normal")==5 and rounds(10,240,"Easy")==30 and rounds(10,120,"Hard")==8 and rounds(8,60,"Hard")==3)
    -- The reward: 25 gold at the default pace, scaled and rounded down.
    for maxTurns, gold in {[60]=12,[120]=25,[240]=50,[500]=50} do
        local s=fresh(); s.maxTurns=maxTurns
        local a,b=pair(ring2,ring3); place(s,1,"Warrior",a); addCamp(s,b)
        local goldBefore=s.players[1].gold
        apply(s,1,{kind="MoveUnit",unitId=s.nextUnit-1,tileId=b})
        assert(s.players[1].gold==goldBefore+gold,maxTurns.." rounds pay "..gold)
    end
    -- The cap per map size, and the unit caps over a fast-paced Huge match.
    local function cap(tiles: number): number return math.max(1,math.min(B.maxCamps,tiles//B.tilesPerCamp)) end
    assert(cap(331)==1 and cap(721)==2 and cap(1261)==3 and cap(2791)==8 and cap(4921)==12 and cap(4842)==12 and cap(61)==1)
    local cases: {any}={{options={radius=10,maxTurns=60},cap=1},{options={radius=40,maxTurns=60},cap=12}}
    for _, case: any in cases do
        local s: any=Game.new(9,case.options)
        local most,mostUnits=0,0; local started=os.clock()
        for _=1,59 do
            if s.phase~="Playing" then break end
            humanTurn(s)
            most=math.max(most,#s.barbarians.camps)
            local count=#barbarians(s); mostUnits=math.max(mostUnits,count)
            assert(#s.barbarians.camps<=case.cap,"camps stay under the map's cap")
            assert(count<=B.maxUnits and count<=B.unitsPerCamp*math.max(1,most),"barbarian units stay under their caps")
            assert(#s.units<=Rules.maxUnits)
        end
        assert(most==case.cap,"the map reaches its cap of "..case.cap..", got "..most)
        print(string.format("  caps: radius %d reached %d camps and %d barbarian units by round %d (%.2f s)",case.options.radius,most,mostUnits,s.turn,os.clock()-started))
    end
end

-- 5. Clearing camps: a military unit that enters an empty camp destroys it, earns the gold and stops there; a move
--    never passes through a camp; civilians cannot enter; a melee kill of the guard clears it, a ranged kill does not.
do
    local s=fresh(); local a,b=pair(ring2,ring3)
    local warrior=place(s,1,"Warrior",a); local camp=addCamp(s,b)
    local view: any=Game.snapshot(s,1)
    assert(table.find(view.legalMoves[tostring(warrior.id)],b),"an empty visible camp is a legal destination")
    assert(view.camps[1].id==camp.id and view.camps[1].tileId==b)
    local preview: any=Game.previewMove(s,1,warrior.id,b)
    assert(preview and preview.clearsCamp and preview.endsMovement and preview.movesLeft==0,"entering a camp ends movement and clears it")
    for _, tileId in view.legalMoves[tostring(warrior.id)] do
        local p: any=Game.previewMove(s,1,warrior.id,tileId)
        if p then
            for index, step in p.path do assert(step~=b or index==#p.path,"no move passes through a camp") end
            assert(p.clearsCamp==(tileId==b))
        end
    end
    local before=s.nextEvent; local gold=s.players[1].gold
    apply(s,1,{kind="MoveUnit",unitId=warrior.id,tileId=b})
    assert(#s.barbarians.camps==0 and warrior.tileId==b and warrior.moves==0 and s.players[1].gold==gold+25)
    local cleared=eventsAfter(s,before,"CampCleared")
    assert(#cleared==1 and cleared[1].ownerId==1 and cleared[1].tileId==b and cleared[1].unitId==warrior.id and cleared[1].amount==25 and cleared[1].unitKind=="Warrior")
    assert(#Game.snapshot(s,1).camps==0)
    -- A civilian cannot enter a camp.
    s=fresh(); local worker=place(s,1,"Worker",a); addCamp(s,b)
    view=Game.snapshot(s,1)
    assert(not table.find(view.legalMoves[tostring(worker.id)],b) and Game.previewMove(s,1,worker.id,b)==nil)
    assert(not Game.apply(s,1,{kind="MoveUnit",unitId=worker.id,tileId=b}).ok and #s.barbarians.camps==1)
    -- A melee kill of the guard advances into the camp and clears it; the preview says so exactly.
    s=fresh(); warrior=place(s,1,"Warrior",a); addCamp(s,b); local guard=place(s,0,"Warrior",b,10)
    local attack: any=Game.previewAttack(s,1,warrior.id,b)
    assert(attack and attack.exact and attack.defenderDefeated=="Yes" and attack.advances and attack.clearsCamp and attack.target=="Unit")
    assert(equal(Game.snapshot(s,1).attackPreviews[tostring(warrior.id)][1],attack),"the snapshot lists the same preview")
    before=s.nextEvent
    apply(s,1,{kind="MoveUnit",unitId=warrior.id,tileId=b})
    assert(unitById(s,guard.id)==nil and warrior.tileId==b and #s.barbarians.camps==0)
    local lost=eventsAfter(s,before,"UnitLost")
    assert(#lost==1 and lost[1].ownerId==0 and lost[1].byOwnerId==1 and lost[1].cause=="Combat" and lost[1].unitKind=="Warrior" and lost[1].message=="A barbarian Warrior was destroyed.")
    assert(#eventsAfter(s,before,"CampCleared")==1)
    -- A full-health guard survives: no clearing.
    s=fresh(); warrior=place(s,1,"Warrior",a); addCamp(s,b); place(s,0,"Warrior",b)
    attack=Game.previewAttack(s,1,warrior.id,b); assert(attack and not attack.advances and not attack.clearsCamp and attack.defenderDefeated=="No")
    -- A ranged kill leaves the camp standing, empty.
    s=fresh(); s.players[1].technologies={"Agriculture","Archery"}
    local archer=place(s,1,"Archer",a); addCamp(s,b); place(s,0,"Warrior",b,5)
    attack=Game.previewAttack(s,1,archer.id,b); assert(attack and attack.ranged and not attack.clearsCamp and attack.defenderDefeated=="Yes")
    apply(s,1,{kind="RangedAttack",unitId=archer.id,tileId=b})
    assert(#s.barbarians.camps==1 and archer.tileId==a)
    -- A city never deploys onto an adjacent camp: with every other deployment tile taken, a purchase is refused.
    s=fresh(); s.players[1].gold=500
    place(s,1,"Warrior",home.tileId); for i=2,#ring1 do place(s,1,"Warrior",ring1[i]) end; addCamp(s,ring1[1])
    assert(not Game.apply(s,1,{kind="Purchase",cityId=home.id,item="Warrior"} :: any).ok,"a camp is never a deployment tile")
    local forecast: any=Game.snapshot(s,1).cityForecasts[tostring(home.id)]; assert(forecast.productionBlocked=="NoSpace" or forecast.productionTurns==nil or forecast.productionTurns>1)
end

-- 6. Experience against barbarians stops at 30; barbarians never gain experience; experience elsewhere is unaffected.
do
    local a,b=pair(ring2,ring3)
    for _, case in {{xp=0,expected=5},{xp=28,expected=30},{xp=30,expected=30},{xp=40,expected=40}} do
        local s=fresh(); local warrior=place(s,1,"Warrior",a); warrior.xp=case.xp
        if case.xp>=30 then warrior.promotions={"Shock1"}; warrior.level=1 end
        local enemy=place(s,0,"Warrior",b)
        apply(s,1,{kind="MoveUnit",unitId=warrior.id,tileId=b})
        assert(warrior.xp==case.expected,"attacker experience "..tostring(warrior.xp).." from "..case.xp)
        assert(enemy.xp==nil,"barbarians gain no experience")
    end
    -- Defending: the barbarian attacks a weakened warrior holding 27 experience; it gains 3, not 4.
    local s=fresh(); local warrior=place(s,1,"Warrior",a,60); warrior.xp=27
    local enemy=place(s,0,"Warrior",b)
    round(s)
    assert(unitById(s,warrior.id) and warrior.xp==30 and enemy.xp==nil,"defender experience capped at 30")
    -- A city strike gives a barbarian nothing.
    s=fresh(); enemy=place(s,0,"Warrior",ring2[1])
    apply(s,1,{kind="CityRangedStrike",cityId=home.id,targetUnitId=enemy.id}); assert(enemy.xp==nil)
end

-- 7. Combat with exact previews: civilization units attacking barbarians at peace (query preview, snapshot preview,
--    applied result and an independent formula), and barbarians attacking civilization units (event amount and formula).
do
    local cases=0
    local a,b=pair(ring2,ring3)
    for _, attackerKind: string in {"Warrior","Archer","Swordsman"} do
        for _, defenderKind: string in {"Warrior","Archer","Swordsman","Pikeman"} do
            for _, terrain: string in {"Plains","Hills"} do
                for _, fortified: boolean in {false,true} do
                    for _, hp: number in {35,100} do
                        local s=fresh(); s.players[1].technologies={"Agriculture","Mining","Archery","BronzeWorking","IronWorking"}
                        clear(s,b,terrain)
                        local attacker=place(s,1,attackerKind,a,90); local defender=place(s,0,defenderKind,b,hp); defender.fortified=fortified
                        local query: any=Game.previewAttack(s,1,attacker.id,b)
                        local listed: any=Game.snapshot(s,1).attackPreviews[tostring(attacker.id)][1]
                        assert(query and equal(query,listed) and query.exact,"previews agree and are exact")
                        local dealt,received=reference(attackerKind,90,defenderKind,hp,terrain,fortified,0)
                        assert(query.dealt==dealt and query.received==received,attackerKind.." on "..defenderKind..": preview "..tostring(query.dealt).."/"..tostring(query.received)..", formula "..tostring(dealt).."/"..tostring(received))
                        local before=s.nextEvent
                        apply(s,1,{kind=if attackerKind=="Archer" then "RangedAttack" else "MoveUnit",unitId=attacker.id,tileId=b})
                        local hit=eventsAfter(s,before,"Attack")[1]; assert(hit.amount==dealt and hit.ownerId==1)
                        local after=unitById(s,defender.id)
                        if hp-dealt<=0 then assert(after==nil and query.defenderDefeated=="Yes") else assert(after.hp==hp-dealt and query.defenderDefeated=="No") end
                        local alive=unitById(s,attacker.id)
                        if 90-received<=0 then assert(alive==nil) else assert(alive.hp==90-received) end
                        -- On unowned land a melee kill the attacker survives advances, exactly as the preview says.
                        local advanced=attackerKind~="Archer" and hp-dealt<=0 and 90-received>0
                        assert(query.advances==advanced and (not alive or alive.tileId==(if advanced then b else a)),"advance as previewed")
                        cases += 1
                    end
                end
            end
        end
    end
    assert(cases==96)
    -- Barbarians attack: the Attack event's amount equals the formula, and a kill gives the loser a UnitLost.
    for _, hp in {30,60} do
        local s=fresh(); local warrior=place(s,1,"Warrior",a,hp); local raider=place(s,0,"Warrior",b)
        local dealt,received=reference("Warrior",100,"Warrior",hp,"Plains",false,0)
        local before=s.nextEvent; round(s)
        local hits=eventsAfter(s,before,"Attack"); assert(#hits==1 and hits[1].ownerId==0 and hits[1].unitId==raider.id and hits[1].tileId==a and hits[1].amount==dealt)
        assert(raider.hp==100-received)
        if hp<=dealt then
            local lost=eventsAfter(s,before,"UnitLost"); assert(#lost==1 and lost[1].ownerId==1 and lost[1].byOwnerId==0 and lost[1].cause=="Combat" and lost[1].unitKind=="Warrior")
            assert(raider.tileId==a,"the winner advances")
            local loss: any=nil; for _, e in Game.snapshot(s,1).events do if e.id==lost[1].id then loss=e end end; assert(loss,"the loser sees its loss")
        else assert(unitById(s,warrior.id)~=nil and raider.tileId==b) end
    end
    -- A barbarian does not attack when the strike is unfavourable (a full-health Swordsman beside it).
    local s=fresh(); s.players[1].technologies={"Mining","BronzeWorking","IronWorking"}
    place(s,1,"Swordsman",a); local raider=place(s,0,"Warrior",b)
    local before=s.nextEvent; round(s); assert(#eventsAfter(s,before,"Attack")==0 and raider.hp==100)
    -- Barbarians exert a zone of control on civilization units at peace; removing the barbarian removes it.
    s=fresh(); local x=ring3[1]; local from: number?=nil; local to: number?=nil
    for _, id in graph.neighbors[x] do
        if table.find(ring2,id) or table.find(ring3,id) then
            for _, other in graph.neighbors[x] do if other~=id and adjacent(graph,id,other) and (table.find(ring2,other) or table.find(ring3,other)) then from=id; to=other end end
        end
        if from then break end
    end
    assert(from and to)
    local mover=place(s,1,"Warrior",from :: number); place(s,0,"Warrior",x)
    local zoc: any=Game.previewMove(s,1,mover.id,to :: number); assert(zoc and zoc.zoneOfControl and zoc.movesLeft==0)
    for i=#s.units,1,-1 do if s.units[i].ownerId==0 then table.remove(s.units,i) end end
    zoc=Game.previewMove(s,1,mover.id,to :: number); assert(zoc and not zoc.zoneOfControl)
    print("  combat: "..cases.." attacks on barbarians equal their previews and the formula")
end

-- 8. City strikes on barbarians: a target at peace, the exact preview, the kill event and the AI's strike.
do
    local s=fresh(); local enemy=place(s,0,"Warrior",ring2[1])
    local view: any=Game.snapshot(s,1); local cityView: any=nil; for _, c in view.cities do if c.id==home.id then cityView=c end end
    assert(cityView.canStrike and table.find(cityView.strikeTargets,enemy.id),"a barbarian is a target at peace")
    local preview: any=Game.previewCityStrike(s,1,home.id,enemy.id); assert(preview and preview.exact and equal(view.cityStrikePreviews[tostring(home.id)][1],preview))
    apply(s,1,{kind="CityRangedStrike",cityId=home.id,targetUnitId=enemy.id})
    assert(enemy.hp==100-preview.dealt)
    s=fresh(); enemy=place(s,0,"Warrior",ring2[1],10)
    local before=s.nextEvent
    apply(s,1,{kind="CityRangedStrike",cityId=home.id,targetUnitId=enemy.id})
    local lost=eventsAfter(s,before,"UnitLost"); assert(#lost==1 and lost[1].ownerId==0 and lost[1].cause=="CityStrike" and lost[1].byOwnerId==1 and unitById(s,enemy.id)==nil)
    -- The AI strikes a barbarian next to its city.
    s=fresh(); s.humanPlayers=1; s.players[2].human=false
    local rivalRing: number?=nil; for _, id in graph.neighbors[rivalCity.tileId] do if Rules.terrains[s.tiles[id].terrain].passable then rivalRing=id; break end end
    enemy=place(s,0,"Archer",rivalRing :: number)
    before=s.nextEvent; apply(s,1,{kind="EndTurn"})
    local strikes=eventsAfter(s,before,"CityStrike"); assert(#strikes>=1 and strikes[1].ownerId==2 and strikes[1].unitId==enemy.id,"the AI strikes the barbarian")
end

-- 9. Barbarian behaviour: guards hold their camps, hunters close in and kill civilians, units wander within the leash,
--    cities are damaged but never captured, and a crowded phase terminates.
do
    local a,b=pair(ring2,ring3)
    -- A melee guard holds even against a lone worker it would kill; a ranged guard shoots.
    local s=fresh(); addCamp(s,b); local guard=place(s,0,"Warrior",b); local worker=place(s,1,"Worker",a)
    round(s); assert(guard.tileId==b and unitById(s,worker.id)~=nil,"a melee guard holds its camp")
    s=fresh(); addCamp(s,b); guard=place(s,0,"Archer",b); local target=place(s,1,"Warrior",a)
    local before=s.nextEvent; round(s); assert(guard.tileId==b and #eventsAfter(s,before,"Attack")==1 and target.hp<100,"a ranged guard shoots")
    -- A roaming barbarian kills an unescorted worker and advances.
    s=fresh(); local raider=place(s,0,"Warrior",b); worker=place(s,1,"Worker",a)
    before=s.nextEvent; round(s)
    local lost=eventsAfter(s,before,"UnitLost"); assert(#lost==1 and lost[1].unitId==worker.id and lost[1].byOwnerId==0 and raider.tileId==a)
    -- A hunter closes in on a civilization unit within five hexes.
    s=fresh(); local start=far(s,6); raider=place(s,0,"Warrior",start)
    local nearest=nil; for _, t in s.tiles do if Rules.terrains[t.terrain].passable and WorldMap.distance(graph,t.id,start)==4 and WorldMap.distance(graph,t.id,rivalCity.tileId)>=3 then nearest=t.id; break end end
    assert(nearest); local bait=place(s,1,"Swordsman",nearest :: number); s.players[1].technologies={"Mining","BronzeWorking","IronWorking"}
    round(s); assert(WorldMap.distance(graph,raider.tileId,bait.tileId)<4,"the hunter closes in")
    -- Without a target a barbarian stays within the leash of its camp.
    s=fresh(); local campTile=far(s,9); addCamp(s,campTile); place(s,0,"Warrior",campTile)
    local roamer: any=nil; for _, id in graph.neighbors[campTile] do if Rules.terrains[s.tiles[id].terrain].passable then roamer=place(s,0,"Warrior",id); break end end
    assert(roamer)
    for _=1,6 do round(s); assert(WorldMap.distance(graph,roamer.tileId,campTile)<=B.leashRadius,"a wanderer stays near its camp") end
    -- Cities are damaged but never captured; a city at 0 hit points is not attacked.
    s=fresh(); home=firstCity(s,1); home.hp=5; raider=place(s,0,"Warrior",ring1[1])
    before=s.nextEvent; round(s)
    assert(firstCity(s,1).ownerId==1 and raider.tileId==ring1[1] and #eventsAfter(s,before,"Capture")==0,"barbarians never capture")
    local cityHp=firstCity(s,1).hp; assert(cityHp<=5+5,"the city was struck")
    s=fresh(); firstCity(s,1).hp=0; raider=place(s,0,"Warrior",ring1[1])
    before=s.nextEvent; round(s); assert(#eventsAfter(s,before,"Attack")==0 and firstCity(s,1).ownerId==1,"a city at 0 HP is left alone")
    home=firstCity(base,1)
    -- A crowded phase: thirty barbarians among civilization units and cities; every phase ends and every state is valid.
    s=fresh(); local taken: {[number]: boolean}={}
    for _, c in s.cities do taken[c.tileId]=true end
    local count=0
    for _, t in s.tiles do
        if count>=30 then break end
        if Rules.terrains[t.terrain].passable and not taken[t.id] and t.id%3==0 then
            place(s,0,B.eraUnits[1][(t.id%2)+1],t.id); taken[t.id]=true; count += 1
        end
    end
    for i, id in ring2 do if not taken[id] and i%2==0 then place(s,1,"Warrior",id); taken[id]=true end end
    assert(Save.valid(Game.serialize(s)))
    local started=os.clock()
    for _=1,12 do
        if s.phase~="Playing" then break end
        round(s); assert(Save.valid(Game.serialize(s)),"every phase leaves a valid state")
        for _, u in s.units do assert(Rules.terrains[s.tiles[u.tileId].terrain].passable) end
    end
    print(string.format("  behaviour: 12 crowded rounds with %d barbarians in %.2f s",count,os.clock()-started))
end

-- 10. The AI and barbarians: it clears a camp it can reach, attacks a barbarian it survives and spares one that would
--     kill it.
do
    -- The rival city has used its strike this round, so the units' own choices show.
    local function soloArena(): any local s=fresh(); s.humanPlayers=1; s.players[2].human=false; firstCity(s,2).strikeTurn=s.turn; return s end
    local rivalTiles={}; for _, id in graph.neighbors[rivalCity.tileId] do if Rules.terrains[base.tiles[id].terrain].passable then table.insert(rivalTiles,id) end end
    local x: number?,y: number?=nil,nil
    for _, id in rivalTiles do for _, other in graph.neighbors[id] do if other~=rivalCity.tileId and Rules.terrains[base.tiles[other].terrain].passable and not table.find(rivalTiles,other) then x=id; y=other; break end end; if x then break end end
    assert(x and y)
    local s=soloArena(); clear(s,y :: number); place(s,2,"Warrior",x :: number); addCamp(s,y :: number)
    local before=s.nextEvent; local gold=s.players[2].gold
    apply(s,1,{kind="EndTurn"})
    local cleared=eventsAfter(s,before,"CampCleared"); assert(#cleared==1 and cleared[1].ownerId==2 and s.players[2].gold>=gold+25,"the AI clears a reachable camp")
    s=soloArena(); clear(s,y :: number); local fighter=place(s,2,"Warrior",x :: number); local foe=place(s,0,"Warrior",y :: number,30)
    before=s.nextEvent; apply(s,1,{kind="EndTurn"})
    local hits=eventsAfter(s,before,"Attack"); assert(#hits>=1 and hits[1].ownerId==2 and hits[1].unitId==fighter.id,"the AI attacks a weak barbarian")
    assert(unitById(s,foe.id)==nil)
    s=soloArena(); clear(s,y :: number); s.players[2].technologies={"Mining","BronzeWorking","IronWorking"}
    -- The warrior heals 15 in its own territory to 40 at the start of the AI's turn: enough not to fortify, too little to
    -- survive the Swordsman's return blow (64).
    assert(s.tiles[x :: number].ownerId==2)
    fighter=place(s,2,"Warrior",x :: number,25); place(s,0,"Swordsman",y :: number)
    before=s.nextEvent; apply(s,1,{kind="EndTurn"})
    for _, e in eventsAfter(s,before,"Attack") do assert(e.unitId~=fighter.id,"the AI spares a barbarian that would kill its unit") end
end

-- 11. Fog: barbarians and camps appear only while visible; hidden ones change nothing in a snapshot.
do
    local s=fresh(); local hiddenTile=far(s,6); local seenTile=ring2[1]
    local hiddenCamp=far(s,6,{[hiddenTile]=true})
    local hiddenUnit=place(s,0,"Warrior",hiddenTile); local seenUnit=place(s,0,"Archer",seenTile)
    addCamp(s,hiddenCamp); local visibleCamp=addCamp(s,ring2[#ring2])
    local view: any=Game.snapshot(s,1)
    assert(viewUnit(view,hiddenUnit.id)==nil,"a hidden barbarian is not listed")
    local shown=viewUnit(view,seenUnit.id)
    assert(shown and shown.ownerId==0 and shown.level==0 and #shown.promotions==0 and shown.xp==nil and shown.nextLevelXp==nil and shown.promotionsAvailable==nil)
    assert(#view.camps==1 and view.camps[1].id==visibleCamp.id and view.camps[1].tileId==visibleCamp.tileId,"only the visible camp is listed")
    -- Removing or moving the hidden barbarian and camp changes nothing the actor sees.
    local other=fresh(); place(other,0,"Archer",seenTile); other.nextUnit=s.nextUnit
    addCamp(other,ring2[#ring2]); other.barbarians.camps[1].id=visibleCamp.id; other.barbarians.nextCamp=s.barbarians.nextCamp
    other.units[1].id=seenUnit.id
    assert(equal(Game.snapshot(other,1),view),"hidden barbarians and camps leave the snapshot unchanged")
    -- A barbarian's attack on a hidden tile is not projected.
    s=fresh(); local farA=far(s,6); local farB: number?=nil
    for _, id in graph.neighbors[farA] do if Rules.terrains[s.tiles[id].terrain].passable and WorldMap.distance(graph,id,home.tileId)>=6 and WorldMap.distance(graph,id,rivalCity.tileId)>=3 then farB=id; break end end
    assert(farB)
    place(s,2,"Worker",farB :: number); place(s,0,"Warrior",farA)
    local before=s.nextEvent; round(s)
    local hits=eventsAfter(s,before,"Attack"); assert(#hits==1)
    for _, e in Game.snapshot(s,1).events do assert(e.id~=hits[1].id,"player 1 does not see a hidden barbarian attack") end
    local seenByTwo=false; for _, e in Game.snapshot(s,2).events do if e.id>=before and e.kind=="UnitLost" and e.ownerId==2 then seenByTwo=true end end
    assert(seenByTwo,"the victim learns of its loss")
end

-- 12. Saves: legacy saves restore without barbarians and never gain them; G9 saves round-trip; validation.
do
    -- A save written before barbarians: a solo match without the field (as every earlier save is).
    local legacy: any=Game.serialize(Game.new(5,{radius=20,barbarians=false}))
    assert(legacy.state.barbarians==nil and Save.valid(legacy))
    local s: any=Game.restore(legacy); assert(s and equal(Game.serialize(s),legacy),"restore adds no field")
    assert(equal(Save.restore(legacy),legacy.state))
    for _=1,30 do if s.phase~="Playing" then break end; humanTurn(s) end
    assert(s.barbarians==nil and #barbarians(s)==0 and Game.snapshot(s,1).barbarians==false,"a legacy match never gains barbarians")
    -- A G9 save with camps, barbarian units and their events round-trips.
    s=fresh(); local a,b=pair(ring2,ring3); addCamp(s,b); place(s,0,"Warrior",b,10); place(s,1,"Warrior",a)
    apply(s,1,{kind="MoveUnit",unitId=s.nextUnit-1,tileId=b})
    place(s,0,"Archer",ring2[#ring2])
    local saved=Game.serialize(s); local restored: any=Game.restore(saved); assert(restored and equal(Game.serialize(restored),saved))
    -- Validation, case by case.
    local valid=fresh(); addCamp(valid,ring3[1]); place(valid,0,"Warrior",ring3[1]); place(valid,0,"Archer",ring3[2])
    table.insert(valid.events,{id=valid.nextEvent,kind="Attack",message="x",tileId=ring2[1],unitId=valid.nextUnit-1,ownerId=0,amount=20}); valid.nextEvent += 1
    table.insert(valid.events,{id=valid.nextEvent,kind="UnitLost",message="x",tileId=ring2[1],unitId=valid.nextUnit-1,ownerId=1,cause="Ranged",byOwnerId=0,unitKind="Warrior",amount=20}); valid.nextEvent += 1
    table.insert(valid.events,{id=valid.nextEvent,kind="CampCleared",message="x",tileId=ring3[3],unitId=valid.nextUnit-1,ownerId=1,amount=25,unitKind="Warrior"}); valid.nextEvent += 1
    local validSave=Game.serialize(valid)
    local function variant(change: (any)->()): any local v: any=Game.serialize(valid); change(v.state); return v end
    local function accepts(change: (any)->(),label: string) assert(Save.valid(variant(change)),label.." rejected") end
    local function rejects(change: (any)->(),label: string)
        local value=variant(change); assert(not Save.valid(value),label.." accepted")
        local loaded,message=Save.restore(value); assert(loaded==nil and type(message)=="string"); assert(Game.restore(value)==nil)
    end
    local function barbarian(st: any): any for _, u in st.units do if u.ownerId==0 then return u end end; error("none") end
    assert(Save.valid(validSave))
    accepts(function(st) st.barbarians.camps={} end,"no camps")
    accepts(function(st) st.barbarians.camps[1].lastSpawn=st.turn end,"a spawn this round")
    accepts(function(st) barbarian(st).fortified=true end,"a fortified barbarian")
    accepts(function(st) barbarian(st).xp=0 end,"zero experience")
    accepts(function(st) st.barbarians.nextCamp=50 end,"a later next id")
    rejects(function(st) st.barbarians=nil end,"barbarian units without barbarians")
    rejects(function(st) st.barbarians.camps[1].tileId=st.cities[1].tileId end,"a camp on a city")
    rejects(function(st) for _, t in st.tiles do if not Rules.terrains[t.terrain].passable then st.barbarians.camps[1].tileId=t.id; break end end end,"a camp on impassable terrain")
    rejects(function(st) table.insert(st.barbarians.camps,{id=st.barbarians.nextCamp-1,tileId=ring3[4],founded=2,lastSpawn=2}) end,"a duplicate camp id")
    rejects(function(st) table.insert(st.barbarians.camps,{id=st.barbarians.nextCamp,tileId=ring3[4],founded=2,lastSpawn=2}) end,"an unissued camp id")
    rejects(function(st) st.barbarians.nextCamp=st.barbarians.nextCamp+1; table.insert(st.barbarians.camps,{id=st.barbarians.nextCamp-1,tileId=ring3[1],founded=2,lastSpawn=2}) end,"two camps on one tile")
    rejects(function(st) st.barbarians.camps[1].founded=st.turn+1; st.barbarians.camps[1].lastSpawn=st.turn+1 end,"a future camp")
    rejects(function(st) st.barbarians.camps[1].founded=0 end,"round zero")
    rejects(function(st) st.barbarians.camps[1].lastSpawn=st.barbarians.camps[1].founded-1 end,"a spawn before the camp")
    rejects(function(st) st.barbarians.camps[1].founded=1.5 end,"a fractional round")
    rejects(function(st) st.barbarians.camps[1].guard=true end,"an unknown camp field")
    rejects(function(st) st.barbarians.enabled=true end,"an unknown barbarian field")
    rejects(function(st) st.barbarians.camps[1].tileId=ring2[1]; for _, u in st.units do if u.tileId==ring3[1] then u.tileId=ring2[1] end end; for _, u in st.units do if u.ownerId==0 and u.tileId==ring2[1] then u.ownerId=1 end end end,"a civilization's unit in a camp")
    rejects(function(st) local camps={}; for i=1,13 do camps[i]={id=i,tileId=i,founded=1,lastSpawn=1} end; st.barbarians.camps=camps; st.barbarians.nextCamp=14 end,"more than twelve camps")
    rejects(function(st) barbarian(st).kind="Worker" end,"a barbarian civilian")
    rejects(function(st) barbarian(st).xp=5 end,"barbarian experience")
    rejects(function(st) barbarian(st).promotions={} end,"barbarian promotions")
    rejects(function(st) barbarian(st).level=1 end,"a barbarian level")
    rejects(function(st) barbarian(st).ownerId=3 end,"an unknown owner")
    rejects(function(st) barbarian(st).ownerId=-1 end,"a negative owner")
    rejects(function(st) st.tiles[ring2[1]].ownerId=0 end,"barbarian territory")
    rejects(function(st) st.cities[1].ownerId=0 end,"a barbarian city")
    rejects(function(st) for _, e in st.events do if e.kind=="CampCleared" then e.ownerId=0 end end end,"a barbarian CampCleared")
    rejects(function(st) for _, e in st.events do if e.kind=="Attack" then e.kind="Production" end end end,"a barbarian Production event")
    rejects(function(st) for _, e in st.events do if e.kind=="UnitLost" then e.kind="CityLost" end end end,"a CityLost by barbarians")
    rejects(function(st) for _, e in st.events do if e.kind=="CampCleared" then e.kind="CampSpotted" end end end,"an unknown kind")
    rejects(function(st) st.barbarians=nil; for i=#st.units,1,-1 do if st.units[i].ownerId==0 then table.remove(st.units,i) end end end,"barbarian events without barbarians")
    local function withoutBarbarians(st: any)
        st.barbarians=nil; for i=#st.units,1,-1 do if st.units[i].ownerId==0 then table.remove(st.units,i) end end
        for _, e in st.events do if e.ownerId==0 then e.ownerId=2 end; if e.byOwnerId==0 then e.byOwnerId=2 end end
    end
    accepts(function(st) withoutBarbarians(st); for _, e in st.events do if e.kind=="CampCleared" then e.kind="Production" end end end,"the same match without barbarians")
    -- A cleared camp exists only in a match with barbarians (Astra review of PR #11).
    rejects(function(st) withoutBarbarians(st) end,"a CampCleared without barbarians")
    -- Malformed entries in every list the validator indexes are rejected cleanly, never with an error (Astra review of
    -- PR #11: a scalar unit entry used to throw while its owner was read before its shape was checked).
    local function cleanlyRejected(change: (any)->(),label: string)
        local value=variant(change)
        local ok,result=pcall(Save.valid,value); assert(ok,label.." threw: "..tostring(result)); assert(result==false,label.." accepted")
        local restoredOk,restored=pcall(Game.restore,value); assert(restoredOk and restored==nil,label.." threw on restore")
        local loadedOk,loaded=pcall(Save.restore,value); assert(loadedOk and loaded==nil,label.." threw on BaseSave.restore")
    end
    local malformed: {() -> any}={
        function() return 42 end, function() return "entry" end, function() return true end, function() return {} end,
        function() return {ownerId=0} end, function() return {id=1,tileId=1} end, function() return {kind="Warrior",ownerId=0,tileId=1} end,
    }
    for index, make in malformed do
        local label="malformed entry "..index
        cleanlyRejected(function(st) st.units[1]=make() end,label.." in units")
        cleanlyRejected(function(st) st.units[#st.units]=make() end,label.." as the last unit")
        cleanlyRejected(function(st) st.barbarians.camps[1]=make() end,label.." in camps")
        cleanlyRejected(function(st) st.barbarians=make() end,label.." as the barbarian record")
        -- An empty table is a valid (empty) camp list.
        if index~=4 then cleanlyRejected(function(st) st.barbarians.camps=make() end,label.." as the camp list") end
        cleanlyRejected(function(st) st.events[#st.events]=make() end,label.." in events")
        cleanlyRejected(function(st) st.cities[1]=make() end,label.." in cities")
        cleanlyRejected(function(st) st.players[1]=make() end,label.." in players")
        cleanlyRejected(function(st) st.tiles[1]=make() end,label.." in tiles")
    end
    cleanlyRejected(function(st) st.units[1]=nil end,"a hole in units")
    cleanlyRejected(function(st) st.barbarians.camps[1]=nil; st.barbarians.camps[2]={id=1,tileId=ring3[1],founded=2,lastSpawn=2} end,"a hole in camps")
    local tooMany=fresh(); local n=0
    for _, t in tooMany.tiles do if n<=B.maxUnits and Rules.terrains[t.terrain].passable and t.id~=home.tileId and t.id~=rivalCity.tileId then place(tooMany,0,"Warrior",t.id); n += 1 end end
    assert(not Save.valid({format="unciv-luau-base",version=1,state=tooMany}),"more than thirty barbarian units")
end

-- 12b. Borders (Astra review of PR #11): a melee kill of a barbarian standing on the land of a civilization at peace
--      with the attacker kills it but does not advance, and so does not clear a camp there; the preview says so. At war
--      the same kill advances and clears the camp.
do
    local rivalLand: number?,outside: number?=nil,nil
    for _, id in graph.neighbors[rivalCity.tileId] do
        if base.tiles[id].ownerId~=2 or not Rules.terrains[base.tiles[id].terrain].passable then continue end
        for _, other in graph.neighbors[id] do
            if base.tiles[other].ownerId==nil and other~=rivalCity.tileId and Rules.terrains[base.tiles[other].terrain].passable and not adjacent(graph,other,rivalCity.tileId) then rivalLand=id; outside=other; break end
        end
        if rivalLand then break end
    end
    assert(rivalLand and outside,"the arena needs rival land beside unowned land")
    local borderCases: {any}={{war=false,camp=false},{war=false,camp=true},{war=true,camp=false},{war=true,camp=true}}
    for _, case in borderCases do
        local s=fresh(); clear(s,rivalLand :: number); clear(s,outside :: number)
        if case.war then s.diplomacy.status="War"; s.diplomacy.peaceUntil=0 else s.diplomacy.peaceUntil=s.turn+8 end
        local warrior=place(s,1,"Warrior",outside :: number); local raider=place(s,0,"Warrior",rivalLand :: number,10)
        if case.camp then addCamp(s,rivalLand :: number) end
        assert(Save.valid(Game.serialize(s)),"the border fixture is a valid state")
        local attack: any=Game.previewAttack(s,1,warrior.id,rivalLand :: number)
        assert(attack and attack.exact and attack.defenderDefeated=="Yes" and attack.attackerDefeated=="No")
        assert(equal(Game.snapshot(s,1).attackPreviews[tostring(warrior.id)][1],attack),"the snapshot lists the same preview")
        assert(attack.advances==case.war and attack.clearsCamp==(case.war and case.camp),"the preview tells whether the kill advances")
        local before=s.nextEvent
        apply(s,1,{kind="MoveUnit",unitId=warrior.id,tileId=rivalLand :: number})
        assert(unitById(s,raider.id)==nil,"the barbarian dies either way")
        assert(warrior.tileId==(if case.war then rivalLand else outside),"the attacker advances only into land it may enter")
        assert(#s.barbarians.camps==(if case.camp and not case.war then 1 else 0),"a camp on closed land stays")
        assert(#eventsAfter(s,before,"CampCleared")==(if case.camp and case.war then 1 else 0))
        assert(Save.valid(Game.serialize(s)))
        -- While the peace holds, the camp left on closed land cannot be entered either.
        if not case.war then assert(Game.previewMove(s,1,warrior.id,rivalLand :: number)==nil) end
    end
end

-- 13. Deterministic replays: solo matches with barbarians (camps, raids, kills and cleared camps) replay identically with
--     and without saves between turns, on a hex and a sphere map, and a two-human match runs the barbarians after
--     player 2.
do
    local function run(options: any,resume: boolean): (any,{[string]: number})
        local s: any=Game.new(13,options)
        local tally: {[string]: number}={attacks=0,losses=0,kills=0,cleared=0,camps=0}; local seen=0
        for _=1,60 do
            if s.phase~="Playing" then break end
            humanTurn(s)
            for _, e in s.events do
                if e.id<=seen then continue end
                seen=e.id
                if e.kind=="Attack" and e.ownerId==0 then tally.attacks += 1 end
                if e.kind=="UnitLost" and e.byOwnerId==0 then tally.losses += 1 end
                if e.kind=="UnitLost" and e.ownerId==0 then tally.kills += 1 end
                if e.kind=="CampCleared" then tally.cleared += 1 end
            end
            tally.camps=math.max(tally.camps,s.barbarians.nextCamp-1)
            if resume then s=Game.restore(Game.serialize(s)) end
        end
        return Game.serialize(s),tally
    end
    local replays: {any}={{radius=12,difficulty="Hard"},{mapShape="Sphere",frequency=8,difficulty="Hard"}}
    for _, options in replays do
        local first,tally=run(options,false); local second=run(options,false); local resumed=run(options,true)
        assert(equal(first,second) and equal(first,resumed),"barbarian matches are deterministic")
        assert(tally.camps>0 and tally.attacks>0 and tally.kills>0,"the replay includes camps, raids and barbarian deaths")
        print(string.format("  determinism %s: %d camps, %d barbarian attacks, %d civilization losses, %d barbarians killed, %d camps cleared; phase %s at round %d",
            if options.mapShape then "Sphere" else "Hex",tally.camps,tally.attacks,tally.losses,tally.kills,tally.cleared,first.state.phase,first.state.turn))
    end
    -- Two humans with barbarians: the barbarian phase follows player 2's EndTurn, not player 1's.
    local s=fresh(); local raider=place(s,0,"Warrior",far(s,6)); local start=raider.tileId
    apply(s,1,{kind="EndTurn"}); assert(raider.tileId==start and raider.moves==2)
    apply(s,2,{kind="EndTurn"}); assert(s.turn==3)
end

-- 14. The event ring: a barbarian's own loss is routine, so a full ring evicts it before a civilization's loss; a
--     CampCleared is kept like the other rare events.
do
    local s=fresh(); local a,b=pair(ring2,ring3); local mover=place(s,1,"Warrior",a)
    s.events={}
    table.insert(s.events,{id=s.nextEvent,kind="UnitLost",message="Your Warrior was destroyed.",ownerId=1,cause="Combat",byOwnerId=0,unitKind="Warrior"}); s.nextEvent += 1
    table.insert(s.events,{id=s.nextEvent,kind="CampCleared",message="x",tileId=b,ownerId=1,amount=25}); s.nextEvent += 1
    for _=1,62 do table.insert(s.events,{id=s.nextEvent,kind="UnitLost",message="A barbarian Warrior was destroyed.",ownerId=0,cause="Combat",byOwnerId=1,unitKind="Warrior"}); s.nextEvent += 1 end
    assert(Save.valid(Game.serialize(s)))
    local playerLoss,cleared,firstBarbarian=s.events[1].id,s.events[2].id,s.events[3].id
    apply(s,1,{kind="MoveUnit",unitId=mover.id,tileId=b})
    local ids={}; for _, e in s.events do ids[e.id]=true end
    assert(#s.events==64 and ids[playerLoss] and ids[cleared] and not ids[firstBarbarian],"the barbarian's loss goes first")
end

-- 15. Payload: fully explored Huge maps with twelve camps and thirty barbarian units stay within the snapshot bounds
--     and the save budget; a barbarian phase there is quick.
do
    local huge: {any}={{radius=40,humanPlayers=2,barbarians=true},{mapShape="Sphere",frequency=22,humanPlayers=2,barbarians=true}}
    for _, options in huge do
        local s: any=Game.new(5,options)
        for _, p in s.players do p.explored={}; for id=1,#s.tiles do table.insert(p.explored,id) end end
        local bare=Game.restore(Game.serialize(s)) :: any; bare.barbarians=nil
        local taken: {[number]: boolean}={}; for _, u in s.units do taken[u.tileId]=true end; for _, c in s.cities do taken[c.tileId]=true end
        -- Player 1 sees the tiles around its units: as many barbarians and camps as possible go there, so the actor's
        -- snapshot carries them; the rest spread over the map.
        local seen: {[number]: boolean}={}; for _, v in Game.snapshot(s,1).tiles do if v.visible then seen[v.id]=true end end
        local order={}; for _, t in s.tiles do table.insert(order,t.id) end
        table.sort(order,function(x: number,y: number) local a,b=seen[x]==true,seen[y]==true; if a~=b then return a end; return x<y end)
        local camps,units=0,0
        for _, id in order do
            if not Rules.terrains[s.tiles[id].terrain].passable or taken[id] or (not seen[id] and id%37~=0) then continue end
            if camps<12 then addCamp(s,id); camps += 1 end
            if units<30 then place(s,0,if units%2==0 then "Warrior" else "Archer",id); units += 1 end
            taken[id]=true
            if camps>=12 and units>=30 then break end
        end
        assert(camps==12 and units==30 and Save.valid(Game.serialize(s)),"a Huge save with every barbarian stays within the budget")
        local started=os.clock(); local view: any=Game.snapshot(s,1); local elapsed=os.clock()-started
        local shownUnits=0; for _, u in view.units do if u.ownerId==0 then shownUnits += 1 end end
        assert(#view.camps>=6 and shownUnits>=6,"the actor sees several camps and barbarians")
        local size,bareSize=bytes(view),bytes(Game.snapshot(bare,1))
        assert(size<1500000 and elapsed<1.5,"snapshot "..size.." bytes in "..elapsed.." s")
        assert(size-bareSize<0.02*bareSize,"barbarians add little to the snapshot")
        local save,bareSave=bytes(Game.serialize(s)),bytes(Game.serialize(bare))
        started=os.clock(); apply(s,1,{kind="EndTurn"}); apply(s,2,{kind="EndTurn"}); local phase=os.clock()-started
        assert(phase<1.5,"a Huge round with barbarians took "..phase.." s")
        print(string.format("  %s Huge: snapshot %d bytes (%d without barbarians; %d camps and %d barbarians visible) in %.0f ms; save %d bytes (%d without); a round with 30 barbarians %.0f ms",
            if options.mapShape then "Sphere" else "Hex",size,bareSize,#view.camps,shownUnits,elapsed*1000,save,bareSave,phase*1000))
    end
end

print("base barbarians: rules and option, deterministic camps under caps and pacing, clearing and rewards, the experience cap, exact combat previews both ways, city strikes, zone of control, barbarian and AI behaviour, fog, legacy saves and validation, deterministic replays and Huge payload passed")
