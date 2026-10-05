--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original fixtures for percentage defence modifiers, wounded defenders, flanking, healing by
-- location, exact previews of the same formula and restoring saves written before these rules.
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
local function firstUnit(s: any,owner: number,kind: string): any
    for _, u in s.units do if u.ownerId==owner and u.kind==kind then return u end end; error("missing "..kind)
end
local function firstCity(s: any,owner: number): any
    for _, c in s.cities do if c.ownerId==owner then return c end end; error("missing city")
end
local function unitById(s: any,id: number): any
    for _, u in s.units do if u.id==id then return u end end; return nil
end
local function founded(seed: number,radius: number?): any
    local s=Game.new(seed,{humanPlayers=2,radius=radius or 8})
    -- These fixtures pin earlier rules on bare terrain: terrain features and rivers (G4) are removed from the whole map.
    for _, t in s.tiles do t.feature=nil; t.river=nil end
    apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id}); apply(s,1,{kind="EndTurn"})
    apply(s,2,{kind="FoundCity",unitId=firstUnit(s,2,"Settler").id}); apply(s,2,{kind="EndTurn"}); return s
end
local function clear(s: any,id: number,terrain: string?)
    local t=s.tiles[id]; t.terrain=terrain or "Plains"; t.resource=nil; t.improvement=nil; t.road=nil; t.ownerId=nil
end
local function place(s: any,owner: number,kind: string,tileId: number,hp: number?): any
    local u={id=s.nextUnit,ownerId=owner,kind=kind,tileId=tileId,hp=hp or Rules.units[kind].hp,moves=Rules.units[kind].moves,fortified=false,level=0}
    table.insert(s.units,u); s.nextUnit += 1; return u
end
-- A free tile with six neighbours, at least four hexes from every city and three from every unit;
-- the tile and its neighbours become unowned Plains. Returns the tile and its sorted neighbours.
local function field(s: any): (number,{number})
    local graph=WorldMap.fromTiles(s.tiles,s.radius)
    for _, tile in s.tiles do
        local neighbors=graph.neighbors[tile.id]
        if #neighbors~=6 then continue end
        local far=true
        for _, c in s.cities do if WorldMap.distance(graph,tile.id,c.tileId)<4 then far=false end end
        for _, u in s.units do if WorldMap.distance(graph,tile.id,u.tileId)<3 then far=false end end
        if not far then continue end
        local ids=table.clone(neighbors); table.sort(ids)
        clear(s,tile.id); for _, id in ids do clear(s,id) end
        return tile.id,ids
    end
    error("no open field")
end
-- The G7 bonuses written out: the Spearman and Pikeman +50% against Mounted units, the Anti-Tank Gun +75% against Armor.
local function versus(kind: string,otherKind: string): number
    local role=Rules.units[otherKind].role
    if (kind=="Spearman" or kind=="Pikeman") and role=="Mounted" then return 50 end
    if kind=="AntiTankGun" and role=="Armor" then return 75 end
    return 0
end
-- Independent statement of the G2 formula (percentages written out, not read from the rules), with G7's separate
-- attack and defence and the versus bonuses. Since G5 promotions, `level` adds nothing by itself (it was +3 strength per
-- level); the sweep still varies it to show that.
local function reference(attackerKind: string,attackerHp: number,level: number,defenderKind: string,defenderHp: number,fortified: boolean,terrain: string,flankers: number): (number,number)
    local a=Rules.units[attackerKind]; local ranged=a.range>1
    if not ranged and Rules.units[defenderKind].strength==0 then return 0,0 end
    local flank=if ranged then 0 else math.min(30,10*flankers)
    local _=level
    local attack=math.max(1,if ranged then a.rangedStrength else a.attack)*(0.5+attackerHp/200)*(100+flank+versus(attackerKind,defenderKind))/100
    local percent=(if terrain=="Hills" or terrain=="Forest" then 25 else 0)+(if fortified then 50 else 0)+versus(defenderKind,attackerKind)
    local defense=math.max(3,Rules.units[defenderKind].defense)*(100+percent)/100*(0.5+defenderHp/200)
    local dealt=math.clamp(math.floor(30*attack/math.max(1,defense)+0.5),8,65)
    local received=if ranged or Rules.units[defenderKind].strength==0 then 0 else math.clamp(math.floor(25*defense/attack+0.5),8,65)
    return dealt,received
end
local function lastAttack(s: any): any
    local found: any=nil; for _, e in s.events do if e.kind=="Attack" then found=e end end; return found
end

-- Rules expose the percentages; Mountain stays impassable.
assert(Rules.terrains.Hills.defensePercent==25 and Rules.terrains.Forest.defensePercent==25 and Rules.terrains.Plains.defensePercent==0)
assert(Rules.terrains.Mountain.passable==false and Rules.terrains.Water.passable==false)
assert(Rules.fortifyDefensePercent==50 and Rules.flankingPercent==10 and Rules.maxFlankingPercent==30)
assert(Rules.healing.neutral==10 and Rules.healing.friendly==15 and Rules.healing.city==20)
assert(Game.getRules().terrains.Hills.defensePercent==25 and Game.getRules().healing.city==20)

local base=founded(71); apply(base,1,{kind="DeclareWar",targetId=2})
base.players[1].technologies=table.clone(Rules.technologyOrder); base.players[2].technologies=table.clone(Rules.technologyOrder)
base.players[1].gold=1000; base.players[2].gold=1000
local center,ring=field(base)
local baseSave=Game.serialize(base)

-- One melee or ranged strike from ring[1] onto `center`; flankers stand on ring[2..]. Returns the
-- preview and the applied dealt/received damage, after checking the snapshot lists the same preview.
local function fight(setup: {attacker: string?,attackerHp: number?,level: number?,defender: string?,defenderHp: number?,fortified: boolean?,terrain: string?,flankers: number?,flankKind: string?,flankOwner: number?,extra: {{owner: number,kind: string,slot: number}}?,listed: boolean?}): (any,number,number)
    local s: any=Game.restore(baseSave); assert(s)
    local attacker=firstUnit(s,1,"Warrior"); local defender=firstUnit(s,2,"Warrior")
    local attackerKind=setup.attacker or "Warrior"; local defenderKind=setup.defender or "Warrior"
    s.tiles[center].terrain=setup.terrain or "Plains"
    attacker.kind=attackerKind; attacker.hp=setup.attackerHp or Rules.units[attackerKind].hp; attacker.level=setup.level or 0
    attacker.tileId=ring[1]; attacker.moves=Rules.units[attackerKind].moves
    defender.kind=defenderKind; defender.hp=setup.defenderHp or Rules.units[defenderKind].hp; defender.tileId=center
    defender.fortified=setup.fortified==true
    for slot=1,setup.flankers or 0 do place(s,setup.flankOwner or 1,setup.flankKind or "Warrior",ring[slot+1]) end
    for _, e in setup.extra or {} do place(s,e.owner,e.kind,ring[e.slot]) end
    assert(Save.valid(Game.serialize(s)),"fixture must be a valid state")
    local before=Game.serialize(s)
    local preview=Game.previewAttack(s,1,attacker.id,center); assert(preview,"preview missing")
    assert(equal(before,Game.serialize(s)),"preview must not mutate state")
    if setup.listed~=false then
        local listed: any=nil
        for _, p in Game.snapshot(s,1).attackPreviews[tostring(attacker.id)] do if p.tileId==center then listed=p end end
        assert(listed and equal(listed,preview),"snapshot preview must match the query")
    end
    assert(preview.exact and preview.target=="Unit" and not preview.hiddenDefense)
    local attackerHp,defenderHp=attacker.hp,defender.hp
    local ranged=Rules.units[attackerKind].range>1
    apply(s,1,{kind=if ranged then "RangedAttack" else "MoveUnit",unitId=attacker.id,tileId=center})
    local attack=lastAttack(s); assert(attack and attack.unitId==attacker.id)
    local after=unitById(s,attacker.id); local hit=unitById(s,defender.id)
    local received=if after then attackerHp-after.hp else preview.received
    -- Preview equals the applied result: damage both ways and both outcomes.
    assert(attack.amount==preview.dealt,"dealt damage differs from preview")
    assert(received==preview.received,"received damage differs from preview")
    if hit and hit.ownerId==1 then assert(preview.capturesCivilian=="Yes" and hit.hp==defenderHp and preview.defenderDefeated=="Yes")
    elseif hit then assert(defenderHp-hit.hp==preview.dealt and preview.defenderDefeated=="No") else assert(preview.defenderDefeated=="Yes") end
    if after then assert(preview.attackerDefeated=="No") else assert(preview.attackerDefeated=="Yes" and attackerHp-preview.received<=0) end
    return preview,attack.amount,received
end
local function expect(setup: any,dealt: number,received: number,label: string)
    local _,d,r=fight(setup)
    assert(d==dealt and r==received,label..": expected "..dealt.."/"..received..", got "..d.."/"..r)
end

-- 1. Terrain and fortification are additive percentages of the defender's strength.
expect({},30,25,"open ground")
expect({terrain="Hills"},24,31,"hills +25%")
expect({terrain="Forest"},24,31,"forest +25%")
expect({fortified=true},20,38,"fortified +50%")
expect({terrain="Hills",fortified=true},17,44,"hills and fortified add to +75%")
expect({terrain="Forest",fortified=true},17,44,"forest and fortified add to +75%")

-- 2. Wounded defenders defend (and retaliate) at 0.5 + hp/200 of their strength.
expect({defenderHp=50},40,19,"half-health defender")
expect({defenderHp=60},38,20,"wounded defender")
expect({defenderHp=50,terrain="Hills",fortified=true},23,33,"wounded fortified defender on hills")
do
    local _,fresh=fight({defenderHp=100}); local _,hurt=fight({defenderHp=70}); local _,worse=fight({defenderHp=40})
    assert(fresh<hurt and hurt<worse,"a more wounded defender takes more damage")
end

-- 3. Flanking: +10% melee attack per other friendly military unit next to the defender, at most +30%.
expect({flankers=0},30,25,"no flanking")
expect({flankers=1},33,23,"one flanker")
expect({flankers=2},36,21,"two flankers")
expect({flankers=3},39,19,"three flankers")
expect({flankers=4},39,19,"four flankers are capped at +30%")
expect({flankers=5},39,19,"five flankers are capped at +30%")
expect({flankers=1,flankKind="Archer"},33,23,"a ranged unit flanks")
expect({flankers=3,flankKind="Worker"},30,25,"civilians do not flank")
expect({flankers=3,flankKind="Settler"},30,25,"settlers do not flank")
expect({flankers=3,flankOwner=2},30,25,"the defender's own units do not flank for the attacker")
expect({flankers=2,terrain="Hills",fortified=true},21,36,"flanking against a fortified hill defender")
do
    -- A ranged attack gains nothing from flanking; it still never receives retaliation.
    local _,alone,noReturn=fight({attacker="Archer"}); local _,flanked=fight({attacker="Archer",flankers=3})
    assert(alone==flanked and noReturn==0,"ranged attacks ignore flanking")
    local _,catapult=fight({attacker="Catapult",terrain="Hills"}); local _,catapultFlanked=fight({attacker="Catapult",terrain="Hills",flankers=2})
    assert(catapult==catapultFlanked)
end
-- A friendly unit next to the attacker but not next to the defender does not flank.
do
    local s: any=Game.restore(baseSave); assert(s)
    local graph=WorldMap.fromTiles(s.tiles,s.radius); local from: number?,outer: number?=nil,nil
    for _, ringId in ring do
        for _, id in graph.neighbors[ringId] do
            -- The field keeps every unit three hexes from the centre, so this tile is free.
            if WorldMap.distance(graph,id,center)==2 then from=ringId; outer=id; clear(s,id); break end
        end
        if outer then break end
    end
    assert(from and outer,"an outer tile beside the attacker")
    local attacker=firstUnit(s,1,"Warrior"); local defender=firstUnit(s,2,"Warrior")
    attacker.tileId=from :: number; attacker.moves=2; defender.tileId=center; place(s,1,"Warrior",outer :: number)
    local preview=Game.previewAttack(s,1,attacker.id,center); assert(preview and preview.dealt==30 and preview.received==25)
end

-- 4. A preview of every combination equals the applied result and the independent formula.
do
    local attackers={"Warrior","Scout","Swordsman","Knight","Rifleman","Archer","Catapult","Pikeman","Spearman","Horseman","Crossbowman","Tank","AntiTankGun","Longswordsman"}
    local defenders={"Warrior","Pikeman","Worker","Musketman","Scout","Archer","Spearman","Horseman","GatlingGun","Tank","Infantry"}
    local terrains={"Plains","Hills","Forest","Grassland","Desert"}
    local cases,kills,deaths,flanked=0,0,0,0
    for i=0,307 do
        local attackerKind=attackers[i%#attackers+1]; local defenderKind=defenders[(i//3)%#defenders+1]
        local terrain=terrains[(i//7)%#terrains+1]
        local attackerHp=math.max(1,Rules.units[attackerKind].hp-((i*13)%70))
        local defenderHp=math.max(1,Rules.units[defenderKind].hp-((i*29)%95))
        local fortified=(i//2)%2==1 and Rules.units[defenderKind].strength>0
        local flankers=(i*7)%6; local level=(i//5)%3
        -- A worker beside the defender in every case: civilians never count.
        local extra=if flankers<5 then {{owner=1,kind="Worker",slot=6}} else nil
        local preview,dealt,received=fight({attacker=attackerKind,attackerHp=attackerHp,level=level,defender=defenderKind,defenderHp=defenderHp,fortified=fortified,terrain=terrain,flankers=flankers,extra=extra,listed=i%6==0})
        local expectedDealt,expectedReceived=reference(attackerKind,attackerHp,level,defenderKind,defenderHp,fortified,terrain,flankers)
        assert(dealt==expectedDealt and received==expectedReceived,"case "..i.." differs from the formula")
        if preview.defenderDefeated=="Yes" then kills += 1 end
        if preview.attackerDefeated=="Yes" then deaths += 1 end
        if flankers>0 and Rules.units[attackerKind].range<=1 then flanked += 1 end
        cases += 1
    end
    assert(cases==308 and kills>0 and kills<cases and deaths>0 and flanked>0,"sweep must cover kills, survivals, deaths and flanking")
end

-- 5. Cities: terrain adds its percentage to an undefended city; flanking needs a defending unit;
--    hidden Walls still only widen the preview range.
do
    local s: any=Game.restore(baseSave); assert(s)
    local city=firstCity(s,2); local graph=WorldMap.fromTiles(s.tiles,s.radius)
    local ring2=table.clone(graph.neighbors[city.tileId]); table.sort(ring2)
    for i=#s.units,1,-1 do
        local u=s.units[i]
        if u.ownerId==2 and (u.tileId==city.tileId or table.find(ring2,u.tileId)) then table.remove(s.units,i) end
    end
    local free={}
    for _, id in ring2 do
        local occupied=false; for _, u in s.units do if u.tileId==id then occupied=true end end
        if not occupied then s.tiles[id].terrain="Plains"; s.tiles[id].resource=nil; s.tiles[id].improvement=nil; table.insert(free,id) end
    end
    assert(#free>=4,"room around the city")
    local attacker=firstUnit(s,1,"Warrior"); attacker.kind="Swordsman"; attacker.tileId=free[1]; attacker.moves=2
    city.buildings={}; city.hp=150
    local function cityPreview(terrain: string): any
        s.tiles[city.tileId].terrain=terrain
        local preview=Game.previewAttack(s,1,attacker.id,city.tileId); assert(preview and preview.target=="City" and preview.hiddenDefense); return preview
    end
    local open=cityPreview("Plains"); local hill=cityPreview("Hills")
    local population=city.population
    assert(open.dealtMax==math.clamp(math.floor(30*18/(14+population)+0.5),8,65),"open city defence")
    assert(hill.dealtMax==math.clamp(math.floor(30*18/((14+population)*125/100)+0.5),8,65),"hill city defence +25%")
    assert(hill.dealtMax<open.dealtMax and hill.receivedMin>open.receivedMin)
    for i=2,4 do place(s,1,"Warrior",free[i]) end
    assert(equal(cityPreview("Hills"),hill),"an undefended city is not flanked")
    local hidden: any=Game.restore(Game.serialize(s)); assert(hidden); firstCity(hidden,2).buildings={"Walls"}
    assert(equal(Game.previewAttack(hidden,1,attacker.id,city.tileId),hill),"preview does not reveal Walls")
    local before=city.hp
    apply(hidden,1,{kind="MoveUnit",unitId=attacker.id,tileId=city.tileId})
    local dealt=before-firstCity(hidden,2).hp
    assert(dealt>=hill.dealtMin and dealt<=hill.dealtMax and dealt<hill.dealtMax,"Walls lower the damage inside the range")
end

-- 6. Healing at the start of the owner's turn after a turn without moving or attacking.
local function healingFixture(): (any,{[string]: number})
    local s: any=Game.restore(baseSave); assert(s)
    local graph=WorldMap.fromTiles(s.tiles,s.radius); local city=firstCity(s,1)
    local used={}; for _, u in s.units do used[u.tileId]=true end; for _, c in s.cities do used[c.tileId]=true end
    local function remote(): number
        for _, tile in s.tiles do
            if used[tile.id] or not Rules.terrains[tile.terrain].passable then continue end
            local far=true
            for _, c in s.cities do if WorldMap.distance(graph,tile.id,c.tileId)<4 then far=false end end
            for id in used do if WorldMap.distance(graph,tile.id,id)<2 then far=false end end
            if far then used[tile.id]=true; return tile.id end
        end
        error("no remote tile")
    end
    local ids: {[string]: number}={}
    local function add(name: string,kind: string,tileId: number,hp: number,prepare: ((any)->())?)
        local u=place(s,1,kind,tileId,hp); if prepare then prepare(u) end; ids[name]=u.id; used[tileId]=true
    end
    add("neutral","Warrior",remote(),40)
    local enemyLand=remote(); s.tiles[enemyLand].ownerId=2; add("enemy","Warrior",enemyLand,40)
    local friendly=remote(); s.tiles[friendly].ownerId=1; add("friendly","Warrior",friendly,40)
    for _, u in s.units do if u.tileId==city.tileId then u.tileId=remote() end end
    add("city","Warrior",city.tileId,40)
    add("moved","Warrior",remote(),40,function(u) u.moves=1 end)
    add("attacked","Warrior",remote(),40,function(u) u.moves=0 end)
    add("fortified","Warrior",remote(),40,function(u) u.moves=0; u.fortified=true end)
    local fortifiedHome=remote(); s.tiles[fortifiedHome].ownerId=1
    add("fortifiedHome","Pikeman",fortifiedHome,40,function(u) u.moves=0; u.fortified=true end)
    add("nearlyFull","Warrior",remote(),95)
    local farm=remote(); s.tiles[farm].ownerId=1; s.tiles[farm].terrain="Plains"
    add("worker","Worker",farm,20,function(u) u.moves=0; u.work={improvement="Farm",remaining=2} end)
    add("idleWorker","Worker",remote(),20)
    add("scout","Scout",remote(),30)
    assert(Save.valid(Game.serialize(s)),"healing fixture must be a valid state")
    return s,ids
end
local expected={neutral=50,enemy=50,friendly=55,city=60,moved=40,attacked=40,fortified=50,fortifiedHome=55,nearlyFull=100,worker=35,idleWorker=30,scout=40}
do
    local s,ids=healingFixture()
    -- The rival's turn starts first and heals none of civilization 1's units.
    apply(s,1,{kind="EndTurn"})
    for name,id in ids do assert(unitById(s,id).hp==(if name=="nearlyFull" then 95 elseif name=="worker" or name=="idleWorker" then 20 elseif name=="scout" then 30 else 40),name.." healed on the rival's turn") end
    apply(s,2,{kind="EndTurn"})
    for name,id in ids do
        local u=unitById(s,id); assert(u,name.." missing")
        assert(u.hp==expected[name],name..": expected "..expected[name].." hp, got "..u.hp)
        assert(u.hp<=Rules.units[u.kind].hp)
        assert(u.moves==(if u.work then 0 else Rules.units[u.kind].moves),"movement refreshes after healing")
    end
    -- Healing never exceeds the unit's maximum, turn after turn, and a unit that keeps resting keeps healing.
    for _=1,6 do apply(s,1,{kind="EndTurn"}); apply(s,2,{kind="EndTurn"}) end
    for name,id in ids do local u=unitById(s,id); assert(u.hp<=Rules.units[u.kind].hp,name.." exceeds its maximum") end
    assert(unitById(s,ids.neutral).hp==Rules.units.Warrior.hp and unitById(s,ids.moved).hp==Rules.units.Warrior.hp,"rested units recover fully")
end
-- Real commands: moving or attacking forfeits the next heal; fortifying keeps it; the decision survives a
-- save made mid-turn, because it is derived from saved movement and fortification.
do
    local s,ids=healingFixture()
    local mover=unitById(s,ids.neutral); local fortifier=unitById(s,ids.enemy)
    local graph=WorldMap.fromTiles(s.tiles,s.radius); local step: number?=nil
    for _, id in graph.neighbors[mover.tileId] do
        local occupied=false; for _, u in s.units do if u.tileId==id then occupied=true end end
        if not occupied and Rules.terrains[s.tiles[id].terrain].passable then step=id; break end
    end
    assert(step,"a free step")
    apply(s,1,{kind="MoveUnit",unitId=mover.id,tileId=step :: number})
    apply(s,1,{kind="FortifyUnit",unitId=fortifier.id})
    local resumed: any=Game.restore(Game.serialize(s)); assert(resumed)
    for _, state in {s,resumed} do apply(state,1,{kind="EndTurn"}); apply(state,2,{kind="EndTurn"}) end
    assert(equal(Game.serialize(s),Game.serialize(resumed)),"healing is deterministic across a mid-turn save")
    assert(unitById(s,ids.neutral).hp==40,"a unit that moved does not heal")
    assert(unitById(s,ids.enemy).hp==50 and unitById(s,ids.enemy).fortified,"a unit fortified in enemy land heals 10")
end
do
    local s: any=Game.restore(baseSave); assert(s)
    local attacker=firstUnit(s,1,"Warrior"); local defender=firstUnit(s,2,"Warrior")
    attacker.tileId=ring[1]; attacker.moves=2; attacker.hp=90; defender.tileId=center; defender.hp=100
    apply(s,1,{kind="MoveUnit",unitId=attacker.id,tileId=center})
    local afterAttack=attacker.hp; local defenderAfter=defender.hp
    assert(afterAttack<90 and defenderAfter<100)
    apply(s,1,{kind="EndTurn"})
    assert(defender.hp==defenderAfter+Rules.healing.neutral,"the defender rested and heals at its own turn start")
    apply(s,2,{kind="EndTurn"})
    assert(attacker.hp==afterAttack,"the attacker does not heal after attacking")
end
-- The AI fortifies weak units, which heal under the same rule (rested at its turn start, before it acts).
do
    local s=Game.new(81,{humanPlayers=1,radius=6})
    apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id})
    local warrior=firstUnit(s,2,"Warrior"); warrior.hp=5
    apply(s,1,{kind="EndTurn"})
    local tile=s.tiles[warrior.tileId]; local inCity=false; for _, c in s.cities do if c.tileId==warrior.tileId and c.ownerId==2 then inCity=true end end
    local heal=if inCity then 20 elseif tile.ownerId==2 then 15 else 10
    assert(warrior.fortified and warrior.hp==5+heal,"the AI unit heals at its turn start, then fortifies")
    apply(s,1,{kind="EndTurn"})
    assert(warrior.hp==5+2*heal,"the fortified AI unit heals by location again")
end

-- 7. Saves written before these rules restore unchanged and play under them; no new state fields.
do
    local map=WorldMap.generate(124,3)
    -- A save written before G4 has no features or rivers.
    for _, t in map.tiles do t.feature=nil; t.river=nil end
    local function at(x: number,y: number): number return WorldMap.tileId(map,x,y) :: number end
    local hub,west,north,east,rival=at(0,0),at(-2,0),at(0,-2),at(1,0),at(2,0)
    local foe: number?=nil
    for _, id in map.neighbors[west] do if id~=hub and id~=north and id~=east and id~=rival and WorldMap.distance(map,id,hub)>=2 then foe=id; break end end
    assert(foe)
    for _, id in {hub,west,north,east,rival,foe :: number} do map.tiles[id].terrain="Plains"; map.tiles[id].resource=nil; map.tiles[id].improvement=nil; map.tiles[id].road=nil; map.tiles[id].ownerId=nil end
    map.tiles[hub].ownerId=1; map.tiles[east].ownerId=1
    local explored={}; for id=1,#map.tiles do table.insert(explored,id) end
    -- The pre-G2 (and pre-culture-option) shape: no cultureVictoryPolicies/policyCostIncrease, events without cause.
    local legacyState: any={seed=124,radius=3,difficulty="Normal",humanPlayers=2,forest=false,maxTurns=120,turn=5,revision=9,activePlayerId=1,phase="Playing",tiles=map.tiles,
        units={{id=1,ownerId=1,kind="Warrior",tileId=west,hp=40,moves=2,fortified=false,level=0},
            {id=2,ownerId=1,kind="Warrior",tileId=north,hp=40,moves=1,fortified=false,level=0},
            {id=3,ownerId=1,kind="Warrior",tileId=hub,hp=40,moves=0,fortified=true,level=0},
            {id=4,ownerId=1,kind="Worker",tileId=east,hp=20,moves=2,fortified=false,level=0},
            {id=5,ownerId=2,kind="Settler",tileId=rival,hp=50,moves=2,fortified=false,level=0},
            {id=6,ownerId=2,kind="Warrior",tileId=foe,hp=100,moves=2,fortified=false,level=0}},
        cities={{id=1,ownerId=1,originalOwnerId=1,capital=true,tileId=hub,name="Fixture",population=2,food=0,production=0,queue="Warrior",hp=150,buildings={},focus="Balanced"}},players={},
        diplomacy={status="War",peaceUntil=0},trades={},events={{id=1,kind="FoundCity",message="City founded.",tileId=hub,ownerId=1}},nextEvent=2,nextUnit=7,nextCity=2,nextTrade=1,log={}}
    for id=1,2 do table.insert(legacyState.players,{id=id,human=true,gold=200,science=0,culture=0,happiness=9,technologies={},policies={},explored=table.clone(explored),resources={},income={food=0,production=0,gold=0,science=0,culture=0,maintenance=0}}) end
    local legacy={format="unciv-luau-base",version=1,state=legacyState}
    assert(Save.valid(legacy),"the legacy fixture is a valid version-1 save")
    local restored: any,err=Game.restore(legacy); assert(restored and err==nil,err)
    local prior=Game.serialize(restored); prior.state.diplomacy.met=nil
    for _, c in prior.state.cities do
        assert(c.borderCulture==0 and c.borderTiles==0,"legacy fixture has no post-founding borders")
        c.borderCulture=nil; c.borderTiles=nil
    end
    if prior.state.events[#prior.state.events] and prior.state.events[#prior.state.events].kind=="Contact" then
        table.remove(prior.state.events); prior.state.nextEvent-=1
    end
    assert(equal(prior,legacy),"restore preserves pre-contact fields while migrating contact")
    -- Combat in the restored game: preview equals result.
    local fightState: any=Game.restore(legacy); assert(fightState)
    local preview=Game.previewAttack(fightState,1,1,foe :: number); assert(preview and preview.exact)
    apply(fightState,1,{kind="MoveUnit",unitId=1,tileId=foe :: number})
    assert(lastAttack(fightState).amount==preview.dealt and 40-unitById(fightState,1).hp==preview.received)
    -- Healing in the restored game reads the saved movement/fortification.
    apply(restored,1,{kind="EndTurn"}); apply(restored,2,{kind="EndTurn"})
    assert(unitById(restored,1).hp==50,"rested on neutral land: +10")
    assert(unitById(restored,2).hp==40,"moved before the save: no heal")
    assert(unitById(restored,3).hp==60,"fortified in its city: +20")
    assert(unitById(restored,4).hp==35,"rested in friendly territory: +15")
    -- New saves keep the exact unit schema: no new required fields, and the optional G5 xp/promotions appear only after combat or a promotion.
    local saved=Game.serialize(restored)
    local allowed={id=true,ownerId=true,kind=true,tileId=true,hp=true,moves=true,fortified=true,level=true,work=true}
    for _, u in saved.state.units do for key in u do assert(allowed[key],"unexpected unit field "..tostring(key)) end end
    assert(saved.format=="unciv-luau-base" and saved.version==1 and Save.valid(saved))
end

-- 8. Determinism: identical solo wars replay identically, with saves taken along the way.
do
    local function run(resume: boolean): any
        local s: any=Game.new(91,{humanPlayers=1,radius=5,difficulty="Hard"})
        apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id})
        for turn=1,30 do
            if s.phase~="Playing" then break end
            if turn==3 and s.diplomacy.status~="War" then apply(s,1,{kind="DeclareWar",targetId=2}) end
            local view=Game.snapshot(s,1); local ids={}
            for id in view.attackPreviews do table.insert(ids,tonumber(id) :: number) end; table.sort(ids)
            for _, id in ids do
                local targets=view.attackPreviews[tostring(id)]
                if #targets>0 then
                    local target=targets[1]
                    apply(s,1,{kind=if target.ranged then "RangedAttack" else "MoveUnit",unitId=id,tileId=target.tileId}); break
                end
            end
            if s.phase~="Playing" then break end
            apply(s,1,{kind="EndTurn"})
            if resume then s=Game.restore(Game.serialize(s)) end
        end
        return Game.serialize(s)
    end
    assert(equal(run(false),run(false)) and equal(run(false),run(true)),"combat and healing are deterministic")
end

print("base combat: percentage terrain/fortify defence, wounded defenders, flanking with cap, 308 exact previews (G7 attack, defence and versus bonuses included), city terrain and hidden Walls, healing by location, legacy saves and determinism passed")
