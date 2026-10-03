--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original fixtures for G5 experience and promotions: experience from each kind of strike, level thresholds,
-- PromoteUnit validation, each promotion's effect on the strike and on its exact preview, medic healing, the AI's
-- choice, fog-safe snapshot fields, saves written before promotions and deterministic replays.
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
local function rejected(s: any,owner: number,command: any,label: string)
    local before=Game.serialize(s)
    local result=Game.apply(s,owner,command)
    assert(not result.ok,label.." was accepted")
    assert(equal(before,Game.serialize(s)),label.." changed the state")
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
-- A unit with these promotions: enough experience for them and a level that counts them.
local function promoted(u: any,promotions: {string}?,xp: number?)
    local list=promotions or {}
    u.promotions=if #list>0 then table.clone(list) else nil; u.level=#list
    u.xp=xp or (if #list>0 then Rules.experienceThresholds[#list] else nil)
end
local function place(s: any,owner: number,kind: string,tileId: number,hp: number?,promotions: {string}?): any
    local u={id=s.nextUnit,ownerId=owner,kind=kind,tileId=tileId,hp=hp or Rules.units[kind].hp,moves=Rules.units[kind].moves,fortified=false,level=0}
    promoted(u,promotions); table.insert(s.units,u); s.nextUnit += 1; return u
end
-- A free tile with six neighbours, at least four hexes from every city and three from every unit; the tile and its
-- neighbours become unowned Plains. Returns the tile and its sorted neighbours.
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
local function lastEvent(s: any,kind: string): any
    local found: any=nil; for _, e in s.events do if e.kind==kind then found=e end end; return found
end

-- 1. Rules: four promotion lines, Civ V-like thresholds and experience per strike, unit classes.
do
    local ids={}; for id in Rules.promotions do table.insert(ids,id) end; table.sort(ids)
    assert(equal(ids,{"Accuracy1","Cover1","Drill1","Drill2","Medic","Shock1","Shock2"}),"seven promotions")
    assert(#Rules.promotionOrder==7)
    for _, id in Rules.promotionOrder do assert(Rules.promotions[id] and Rules.promotions[id].id==id) end
    assert(equal(Rules.promotions.Drill2.prerequisites,{"Drill1"}) and equal(Rules.promotions.Shock2.prerequisites,{"Shock1"}))
    assert(equal(Rules.promotions.Medic.prerequisites,{"Cover1"}) and #Rules.promotions.Cover1.prerequisites==0)
    assert(equal(Rules.promotions.Accuracy1.classes,{"Ranged"}) and equal(Rules.promotions.Drill1.classes,{"Melee"}) and equal(Rules.promotions.Medic.classes,{"Melee","Ranged"}))
    assert(Rules.promotions.Drill1.roughPercent==15 and Rules.promotions.Drill2.roughPercent==15 and Rules.promotions.Shock1.openPercent==15 and Rules.promotions.Shock2.openPercent==15)
    assert(Rules.promotions.Cover1.coverPercent==33 and Rules.promotions.Accuracy1.accuracyPercent==15 and Rules.promotions.Medic.adjacentHeal==5)
    assert(equal(Rules.experienceThresholds,{10,30,60,100,150,210}) and Rules.maxExperience==210 and Rules.promotionHealPercent==50)
    assert(Rules.experience.meleeAttack==5 and Rules.experience.meleeDefense==4 and Rules.experience.rangedAttack==2 and Rules.experience.rangedDefense==2)
    assert(Rules.units.Warrior.unitClass=="Melee" and Rules.units.Scout.unitClass=="Melee" and Rules.units.Archer.unitClass=="Ranged" and Rules.units.Catapult.unitClass=="Ranged")
    assert(Rules.units.Worker.unitClass=="Civilian" and Rules.units.Settler.unitClass=="Civilian")
    assert(Rules.terrains.Hills.rough and Rules.terrains.Forest.rough and not Rules.terrains.Plains.rough and not Rules.terrains.Grassland.rough and not Rules.terrains.Desert.rough and not Rules.terrains.Tundra.rough)
    local rules=Game.getRules(); assert(rules.promotions.Medic.adjacentHeal==5 and rules.experienceThresholds[3]==60)
    rules.promotions.Medic.adjacentHeal=99; assert(Game.getRules().promotions.Medic.adjacentHeal==5,"getRules is detached")
end

local base=founded(71); apply(base,1,{kind="DeclareWar",targetId=2})
base.players[1].technologies=table.clone(Rules.technologyOrder); base.players[2].technologies=table.clone(Rules.technologyOrder)
base.players[1].gold=1000; base.players[2].gold=1000
local center,ring=field(base)
local baseSave=Game.serialize(base)

-- Independent statement of the strike with promotions (percentages written out, not read from the rules).
local function promotionPercent(list: {string},rough: boolean,attacking: boolean,rangedStrike: boolean,againstUnit: boolean): number
    local total=0
    for _, id in list do
        if id=="Drill1" or id=="Drill2" then if rough then total += 15 end
        elseif id=="Shock1" or id=="Shock2" then if not rough then total += 15 end
        elseif id=="Cover1" then if not attacking and rangedStrike then total += 33 end
        elseif id=="Accuracy1" then if attacking and rangedStrike and againstUnit then total += 15 end end
    end
    return total
end
local function reference(setup: any): (number,number)
    local attackerKind=setup.attacker or "Warrior"; local defenderKind=setup.defender or "Warrior"
    local a=Rules.units[attackerKind]; local ranged=a.range>1; local terrain=setup.terrain or "Plains"
    local rough=terrain=="Hills" or terrain=="Forest"
    local flank=if ranged then 0 else math.min(30,10*(setup.flankers or 0))
    local attack=math.max(1,if ranged then a.rangedStrength else a.strength)*(0.5+(setup.attackerHp or a.hp)/200)
        *(100+flank+promotionPercent(setup.attackerPromotions or {},rough,true,ranged,true))/100
    local percent=(if rough then 25 else 0)+(if setup.fortified then 50 else 0)+promotionPercent(setup.defenderPromotions or {},rough,false,ranged,true)
    local defense=math.max(3,Rules.units[defenderKind].strength)*(100+percent)/100*(0.5+(setup.defenderHp or Rules.units[defenderKind].hp)/200)
    local dealt=math.clamp(math.floor(30*attack/math.max(1,defense)+0.5),8,65)
    local received=if ranged or Rules.units[defenderKind].strength==0 then 0 else math.clamp(math.floor(25*defense/attack+0.5),8,65)
    return dealt,received
end

-- One strike from ring[1] onto `center` (flankers on ring[2..]). Checks the query preview against the snapshot's,
-- applies the attack, checks the preview equals the applied result and returns the state and the numbers.
local function fight(setup: any): (any,any,number,number,any,any)
    local s: any=Game.restore(baseSave); assert(s)
    local attacker=firstUnit(s,1,"Warrior"); local defender=firstUnit(s,2,"Warrior")
    local attackerKind=setup.attacker or "Warrior"; local defenderKind=setup.defender or "Warrior"
    s.tiles[center].terrain=setup.terrain or "Plains"
    attacker.kind=attackerKind; attacker.hp=setup.attackerHp or Rules.units[attackerKind].hp
    attacker.tileId=ring[1]; attacker.moves=Rules.units[attackerKind].moves
    promoted(attacker,setup.attackerPromotions,setup.attackerXp)
    defender.kind=defenderKind; defender.hp=setup.defenderHp or Rules.units[defenderKind].hp; defender.tileId=center
    defender.fortified=setup.fortified==true and Rules.units[defenderKind].strength>0
    promoted(defender,setup.defenderPromotions,setup.defenderXp)
    for slot=1,setup.flankers or 0 do place(s,1,"Warrior",ring[slot+1]) end
    assert(Save.valid(Game.serialize(s)),"fixture must be a valid state")
    local before=Game.serialize(s)
    local preview=Game.previewAttack(s,1,attacker.id,center); assert(preview,"preview missing")
    assert(equal(before,Game.serialize(s)),"preview must not mutate state")
    local listed: any=nil
    for _, p in Game.snapshot(s,1).attackPreviews[tostring(attacker.id)] do if p.tileId==center then listed=p end end
    assert(listed and equal(listed,preview),"snapshot preview must match the query")
    assert(preview.exact and preview.target=="Unit")
    local attackerHp,defenderHp=attacker.hp,defender.hp
    local ranged=Rules.units[attackerKind].range>1
    apply(s,1,{kind=if ranged then "RangedAttack" else "MoveUnit",unitId=attacker.id,tileId=center})
    local attack=lastEvent(s,"Attack"); assert(attack and attack.unitId==attacker.id)
    local after=unitById(s,attacker.id); local hit=unitById(s,defender.id)
    local received=if after then attackerHp-after.hp else preview.received
    assert(attack.amount==preview.dealt,"dealt damage differs from preview")
    assert(received==preview.received,"received damage differs from preview")
    if hit then assert(defenderHp-hit.hp==preview.dealt and preview.defenderDefeated=="No") else assert(preview.defenderDefeated=="Yes") end
    if after then assert(preview.attackerDefeated=="No") else assert(preview.attackerDefeated=="Yes") end
    local expectedDealt,expectedReceived=reference(setup)
    assert(attack.amount==expectedDealt and received==expectedReceived,"strike differs from the formula: "..attack.amount.."/"..received.." vs "..expectedDealt.."/"..expectedReceived)
    return s,preview,attack.amount,received,after,hit
end
local function damage(setup: any): (number,number)
    local _,_,dealt,received=fight(setup); return dealt,received
end

-- 2. Experience per strike: melee attacker 5, defender against melee 4, ranged attacker 2, defender hit by a ranged
--    attack 2; strikes on civilians give none; experience stops at the last threshold.
do
    local _,_,_,_,attacker,defender=fight({})
    assert(attacker.xp==5 and defender.xp==4,"melee: attacker 5, defender 4")
    local _,_,_,_,archer,target=fight({attacker="Archer"})
    assert(archer.xp==2 and target.xp==2,"ranged: attacker 2, defender 2")
    local _,_,_,_,catapult,struck=fight({attacker="Catapult",defender="Pikeman"})
    assert(catapult.xp==2 and struck.xp==2)
    -- The amounts add to what a unit already has.
    local _,_,_,_,veteran,old=fight({attackerXp=7,defenderXp=3})
    assert(veteran.xp==12 and old.xp==7)
    -- A strike on a civilian gives no experience to either side.
    local _,_,_,_,raider,worker=fight({defender="Worker",defenderHp=50})
    assert(raider.xp==nil and worker==nil,"no experience from killing a worker")
    local _,_,_,_,shooter,civilian=fight({attacker="Archer",defender="Settler"})
    assert(shooter.xp==nil and (civilian==nil or civilian.xp==nil),"no experience from shooting a settler")
    -- Experience is capped at the last threshold.
    local _,_,_,_,capped,cappedDefender=fight({attackerXp=208,defenderXp=209})
    assert(capped.xp==Rules.maxExperience and cappedDefender.xp==Rules.maxExperience,"experience stops at 210")
    -- A unit that dies keeps nothing; the survivor keeps its gain.
    local _,_,_,_,winner,loser=fight({defenderHp=10})
    assert(loser==nil and winner.xp==5)
    local _,_,_,_,dead,survivor=fight({attackerHp=5,defender="Rifleman"})
    assert(dead==nil and survivor.xp==4,"a defender that kills its attacker gains defence experience")
end
-- Attacking a city: the attacker gains its strike's experience (cities have none).
do
    local s: any=Game.restore(baseSave); assert(s)
    local city=firstCity(s,2); local graph=WorldMap.fromTiles(s.tiles,s.radius)
    local around=table.clone(graph.neighbors[city.tileId]); table.sort(around)
    for i=#s.units,1,-1 do
        local u=s.units[i]
        if u.ownerId==2 and (u.tileId==city.tileId or table.find(around,u.tileId)) then table.remove(s.units,i) end
    end
    local free={}
    for _, id in around do
        local occupied=false; for _, u in s.units do if u.tileId==id then occupied=true end end
        if not occupied then s.tiles[id].terrain="Plains"; s.tiles[id].resource=nil; s.tiles[id].improvement=nil; table.insert(free,id) end
    end
    assert(#free>=2,"room around the city")
    s.tiles[city.tileId].terrain="Plains"; city.buildings={}; city.hp=150
    local melee=firstUnit(s,1,"Warrior"); melee.kind="Swordsman"; melee.tileId=free[1]; melee.moves=2
    local archer=place(s,1,"Archer",free[2])
    local cityState=Game.serialize(s)
    -- Promotions against a city: Shock (open terrain) counts, Accuracy (units only) does not.
    local function cityPreview(unitId: number,promotions: {string}?): any
        local t: any=Game.restore(cityState); assert(t); promoted(unitById(t,unitId),promotions)
        assert(Save.valid(Game.serialize(t)))
        local preview=Game.previewAttack(t,1,unitId,city.tileId); assert(preview and preview.target=="City" and preview.hiddenDefense); return preview
    end
    local population=city.population
    assert(cityPreview(melee.id).dealtMax==math.clamp(math.floor(30*18/(14+population)+0.5),8,65))
    assert(cityPreview(melee.id,{"Shock1"}).dealtMax==math.clamp(math.floor(30*18*1.15/(14+population)+0.5),8,65),"Shock counts against a city on open ground")
    assert(equal(cityPreview(archer.id,{"Accuracy1"}),cityPreview(archer.id)),"Accuracy does not count against a city")
    apply(s,1,{kind="MoveUnit",unitId=melee.id,tileId=city.tileId}); assert(melee.xp==5,"melee city attack: 5")
    apply(s,1,{kind="RangedAttack",unitId=archer.id,tileId=city.tileId}); assert(archer.xp==2,"ranged city attack: 2")
end

-- 3. Levels at the thresholds and the snapshot's experience fields.
do
    local s: any=Game.restore(baseSave); assert(s)
    local u=firstUnit(s,1,"Warrior")
    local function own(): any return viewUnit(Game.snapshot(s,1),u.id) end
    local v=own(); assert(v.xp==0 and v.level==0 and equal(v.promotions,{}) and v.nextLevelXp==10 and equal(v.promotionsAvailable,{}))
    u.xp=9; v=own(); assert(#v.promotionsAvailable==0 and v.nextLevelXp==10,"9 xp: no level yet")
    u.xp=10; v=own(); assert(equal(v.promotionsAvailable,{"Drill1","Shock1","Cover1"}) and v.nextLevelXp==30,"10 xp: first level")
    apply(s,1,{kind="PromoteUnit",unitId=u.id,promotion="Shock1"})
    v=own(); assert(v.level==1 and equal(v.promotions,{"Shock1"}) and #v.promotionsAvailable==0,"the level is spent")
    u.xp=29; assert(#own().promotionsAvailable==0)
    u.xp=30; v=own(); assert(equal(v.promotionsAvailable,{"Drill1","Shock2","Cover1"}) and v.nextLevelXp==60,"30 xp: second level opens Shock II")
    for index,threshold in Rules.experienceThresholds do
        u.xp=threshold; assert(own().nextLevelXp==Rules.experienceThresholds[index+1],"next threshold after "..threshold)
    end
    assert(own().nextLevelXp==nil,"no next level at 210")
    -- A ranged unit sees only its class's promotions; a civilian has none.
    local archer=place(s,1,"Archer",ring[3]); archer.xp=10
    assert(equal(viewUnit(Game.snapshot(s,1),archer.id).promotionsAvailable,{"Accuracy1","Cover1"}))
    local worker=firstUnit(s,1,"Worker")
    local wv=viewUnit(Game.snapshot(s,1),worker.id); assert(wv.xp==0 and #wv.promotionsAvailable==0)
    -- Experience reached through real combat opens a promotion.
    local t,_,_,_,attacker=fight({attackerXp=8})
    assert(attacker.xp==13 and equal(viewUnit(Game.snapshot(t,1),attacker.id).promotionsAvailable,{"Drill1","Shock1","Cover1"}))
    -- Promoting needs no movement: right after an attack the unit promotes.
    assert(attacker.moves==0); local hp=attacker.hp
    apply(t,1,{kind="PromoteUnit",unitId=attacker.id,promotion="Drill1"})
    assert(attacker.hp==math.min(100,hp+50) and attacker.level==1)
end

-- 4. PromoteUnit validation and effect.
do
    local s: any=Game.restore(baseSave); assert(s)
    local warrior=firstUnit(s,1,"Warrior"); local enemy=firstUnit(s,2,"Warrior")
    local archer=place(s,1,"Archer",ring[2]); local worker=firstUnit(s,1,"Worker")
    rejected(s,1,{kind="PromoteUnit",unitId=warrior.id,promotion="Shock1"},"no pending level")
    warrior.xp=10; archer.xp=10; enemy.xp=10; worker.xp=0
    assert(Save.valid(Game.serialize(s)))
    rejected(s,1,{kind="PromoteUnit",unitId=warrior.id,promotion="Unknown"},"unknown promotion")
    rejected(s,1,{kind="PromoteUnit",unitId=warrior.id,promotion="Accuracy1"},"a melee unit cannot take Accuracy")
    rejected(s,1,{kind="PromoteUnit",unitId=archer.id,promotion="Drill1"},"a ranged unit cannot take Drill")
    rejected(s,1,{kind="PromoteUnit",unitId=archer.id,promotion="Shock1"},"a ranged unit cannot take Shock")
    rejected(s,1,{kind="PromoteUnit",unitId=warrior.id,promotion="Drill2"},"Drill II needs Drill I")
    rejected(s,1,{kind="PromoteUnit",unitId=warrior.id,promotion="Shock2"},"Shock II needs Shock I")
    rejected(s,1,{kind="PromoteUnit",unitId=warrior.id,promotion="Medic"},"Medic needs Cover I")
    rejected(s,1,{kind="PromoteUnit",unitId=worker.id,promotion="Cover1"},"civilians have no promotions")
    rejected(s,1,{kind="PromoteUnit",unitId=enemy.id,promotion="Shock1"},"another civilization's unit")
    rejected(s,2,{kind="PromoteUnit",unitId=enemy.id,promotion="Shock1"},"out of turn")
    rejected(s,1,{kind="PromoteUnit",unitId=warrior.id,promotion=1},"a numeric promotion")
    rejected(s,1,{kind="PromoteUnit",unitId=warrior.id},"a missing promotion")
    rejected(s,1,{kind="PromoteUnit",unitId=warrior.id,promotion="Shock1",tileId=1},"an extra field")
    rejected(s,1,{kind="PromoteUnit",unitId=999999,promotion="Shock1"},"a missing unit")
    rejected(s,1,{kind="PromoteUnit",unitId=0.5,promotion="Shock1"},"a fractional unit id")
    -- An accepted promotion: one revision, level +1, half the maximum healed, movement ended, a Promotion event.
    warrior.hp=30; warrior.moves=2; local revision=s.revision
    apply(s,1,{kind="PromoteUnit",unitId=warrior.id,promotion="Cover1"})
    assert(s.revision==revision+1 and warrior.level==1 and equal(warrior.promotions,{"Cover1"}) and warrior.hp==80 and warrior.moves==0)
    local e=lastEvent(s,"Promotion"); assert(e and e.unitId==warrior.id and e.ownerId==1 and e.unitKind=="Warrior" and e.tileId==warrior.tileId)
    rejected(s,1,{kind="PromoteUnit",unitId=warrior.id,promotion="Medic"},"no second pending level")
    rejected(s,1,{kind="PromoteUnit",unitId=warrior.id,promotion="Cover1"},"already taken")
    warrior.xp=30; apply(s,1,{kind="PromoteUnit",unitId=warrior.id,promotion="Medic"})
    assert(warrior.level==2 and equal(warrior.promotions,{"Cover1","Medic"}) and warrior.hp==100,"healing stops at the maximum")
    -- A fortified unit keeps its fortification; a ranged unit takes its own line.
    archer.fortified=true; archer.moves=0; archer.hp=10
    apply(s,1,{kind="PromoteUnit",unitId=archer.id,promotion="Accuracy1"})
    assert(archer.fortified and archer.hp==45 and archer.moves==0,"an archer heals 35 (half of 70)")
    -- Promotions survive upgrades within the melee class.
    warrior.kind="Musketman"; warrior.moves=2; apply(s,1,{kind="UpgradeUnit",unitId=warrior.id})
    assert(warrior.kind=="Rifleman" and equal(warrior.promotions,{"Cover1","Medic"}) and Save.valid(Game.serialize(s)))
    -- Several pending levels may be spent one command at a time.
    local fresh=place(s,1,"Warrior",ring[4]); fresh.xp=60
    for _, id in {"Drill1","Drill2","Shock1"} do apply(s,1,{kind="PromoteUnit",unitId=fresh.id,promotion=id}) end
    assert(fresh.level==3); rejected(s,1,{kind="PromoteUnit",unitId=fresh.id,promotion="Shock2"},"three levels spent")
    local restored: any=Game.restore(Game.serialize(s)); assert(restored and equal(Game.serialize(restored),Game.serialize(s)))
end

-- 5. Each promotion's effect on the strike; every case checks the query, the snapshot preview, the applied result
--    and the independent formula.
do
    local function expect(setup: any,label: string,compare: any?)
        local dealt,received=damage(setup)
        if compare then
            local d0,r0=damage(compare)
            assert(dealt~=d0 or received~=r0,label..": the promotion must change the result")
        end
        return dealt,received
    end
    local function same(setup: any,compare: any,label: string)
        local d,r=damage(setup); local d0,r0=damage(compare)
        assert(d==d0 and r==r0,label..": the promotion must not change the result")
    end
    -- Shock: open terrain only, for attack and defence; Shock II adds another 15%.
    local d0=damage({}); local d1=expect({attackerPromotions={"Shock1"}},"Shock I attacking on open ground",{})
    local d2=expect({attackerPromotions={"Shock1","Shock2"}},"Shock II attacking on open ground",{attackerPromotions={"Shock1"}})
    assert(d0<d1 and d1<d2)
    same({attackerPromotions={"Shock1","Shock2"},terrain="Hills"},{terrain="Hills"},"Shock on Hills")
    same({attackerPromotions={"Shock1"},terrain="Forest"},{terrain="Forest"},"Shock in Forest")
    expect({defenderPromotions={"Shock1"}},"Shock I defending on open ground",{})
    expect({terrain="Grassland",attackerPromotions={"Shock1"}},"Shock on Grassland",{terrain="Grassland"})
    expect({terrain="Desert",defenderPromotions={"Shock1","Shock2"},fortified=true},"Shock II fortified on Desert",{terrain="Desert",fortified=true})
    -- Drill: rough terrain only.
    expect({terrain="Hills",attackerPromotions={"Drill1"}},"Drill I attacking into Hills",{terrain="Hills"})
    expect({terrain="Forest",attackerPromotions={"Drill1","Drill2"}},"Drill II attacking into Forest",{terrain="Forest",attackerPromotions={"Drill1"}})
    expect({terrain="Hills",defenderPromotions={"Drill1","Drill2"},fortified=true},"Drill II defending on Hills",{terrain="Hills",fortified=true})
    same({attackerPromotions={"Drill1","Drill2"}},{},"Drill on Plains")
    -- Cover: defence against ranged attacks only.
    expect({attacker="Archer",defenderPromotions={"Cover1"}},"Cover I against an Archer",{attacker="Archer"})
    expect({attacker="Catapult",defender="Pikeman",defenderPromotions={"Cover1"},terrain="Hills"},"Cover I against a Catapult",{attacker="Catapult",defender="Pikeman",terrain="Hills"})
    same({defenderPromotions={"Cover1"}},{},"Cover against melee")
    same({attackerPromotions={"Cover1"}},{},"Cover on the attacker")
    -- Accuracy: ranged attacks on units.
    expect({attacker="Archer",attackerPromotions={"Accuracy1"}},"Accuracy I",{attacker="Archer"})
    expect({attacker="Catapult",attackerPromotions={"Accuracy1"},terrain="Forest"},"Accuracy I in Forest",{attacker="Catapult",terrain="Forest"})
    expect({attacker="Archer",attackerPromotions={"Accuracy1"},defenderPromotions={"Cover1"}},"Accuracy against Cover",{attacker="Archer",defenderPromotions={"Cover1"}})
    -- Medic has no combat effect.
    same({attackerPromotions={"Cover1","Medic"}},{attackerPromotions={"Cover1"}},"Medic attacking")
    same({attacker="Archer",defenderPromotions={"Cover1","Medic"}},{attacker="Archer",defenderPromotions={"Cover1"}},"Medic defending")
    -- Level alone carries no bonus (it was +3 strength per level before promotions).
    do
        local s: any=Game.restore(baseSave); assert(s)
        local attacker=firstUnit(s,1,"Warrior"); attacker.tileId=ring[1]; attacker.moves=2
        firstUnit(s,2,"Warrior").tileId=center
        local plain=Game.previewAttack(s,1,attacker.id,center); attacker.level=3
        assert(Save.valid(Game.serialize(s)) and equal(Game.previewAttack(s,1,attacker.id,center),plain),"a veteran level adds no strength")
    end
    -- A sweep of combinations: both sides promoted, terrain, health, fortification and flanking.
    local melee={{},{"Shock1"},{"Shock1","Shock2"},{"Drill1"},{"Drill1","Drill2"},{"Cover1"},{"Cover1","Medic"},{"Drill1","Shock1","Cover1"},{"Drill1","Drill2","Shock1","Shock2","Cover1","Medic"}}
    local ranged={{},{"Accuracy1"},{"Cover1"},{"Accuracy1","Cover1","Medic"}}
    local attackers={"Warrior","Swordsman","Archer","Knight","Catapult","Pikeman","Rifleman"}
    local defenders={"Warrior","Pikeman","Archer","Musketman","Catapult"}
    local terrains={"Plains","Hills","Forest","Grassland","Tundra"}
    local changed,cases=0,0
    for i=0,149 do
        local attackerKind=attackers[i%#attackers+1]; local defenderKind=defenders[(i//3)%#defenders+1]
        local attackerList=if Rules.units[attackerKind].unitClass=="Ranged" then ranged[(i//2)%#ranged+1] else melee[(i//2)%#melee+1]
        local defenderList=if Rules.units[defenderKind].unitClass=="Ranged" then ranged[(i//5)%#ranged+1] else melee[(i//5)%#melee+1]
        local setup={attacker=attackerKind,defender=defenderKind,terrain=terrains[(i//7)%#terrains+1],
            attackerHp=math.max(1,Rules.units[attackerKind].hp-((i*13)%60)),defenderHp=math.max(1,Rules.units[defenderKind].hp-((i*29)%80)),
            fortified=(i//4)%2==1,flankers=(i*7)%4,attackerPromotions=attackerList,defenderPromotions=defenderList}
        local dealt,received=damage(setup)
        local plain: any=table.clone(setup); plain.attackerPromotions={}; plain.defenderPromotions={}
        local p0,r0=reference(plain)
        if dealt~=p0 or received~=r0 then changed += 1 end
        cases += 1
    end
    assert(cases==150 and changed>40,"promotions change many of the sweep's strikes ("..changed..")")
end

-- 6. Medic: a resting unit next to its owner's medic heals 5 more; medics do not stack, do not heal themselves and
--    help only units that rest.
do
    local function heal(setup: {patientMoves: number?,medics: {number}?,enemyMedic: number?,patientMedic: boolean?,patientHp: number?,owned: boolean?}): number
        local s: any=Game.restore(baseSave); assert(s)
        if setup.owned then s.tiles[center].ownerId=1 end
        local patient=place(s,1,"Warrior",center,setup.patientHp or 40,if setup.patientMedic then {"Cover1","Medic"} else nil)
        if setup.patientMoves then patient.moves=setup.patientMoves end
        for _, slot in setup.medics or {} do place(s,1,"Archer",ring[slot],nil,{"Cover1","Medic"}) end
        if setup.enemyMedic then place(s,2,"Warrior",ring[setup.enemyMedic],nil,{"Cover1","Medic"}) end
        assert(Save.valid(Game.serialize(s)),"medic fixture must be valid")
        apply(s,1,{kind="EndTurn"}); apply(s,2,{kind="EndTurn"})
        return unitById(s,patient.id).hp-(setup.patientHp or 40)
    end
    assert(heal({})==10,"no medic: +10 on neutral land")
    assert(heal({medics={1}})==15,"an adjacent medic: +5")
    assert(heal({medics={1,4}})==15,"two medics do not stack")
    assert(heal({medics={1},owned=true})==20,"friendly land with a medic: 15 + 5")
    assert(heal({medics={1},patientMoves=1})==0,"a unit that moved does not heal, even beside a medic")
    assert(heal({enemyMedic=1})==10,"an enemy medic helps nobody else")
    assert(heal({patientMedic=true})==10,"a medic does not heal itself more")
    assert(heal({medics={1},patientHp=97})==3,"healing stops at the maximum")
    -- A medic two hexes away does not count.
    local s: any=Game.restore(baseSave); assert(s)
    local graph=WorldMap.fromTiles(s.tiles,s.radius); local far: number?=nil
    for _, ringId in ring do
        for _, id in graph.neighbors[ringId] do if WorldMap.distance(graph,id,center)==2 and Rules.terrains[s.tiles[id].terrain].passable then far=id; break end end
        if far then break end
    end
    assert(far,"a tile two hexes from the patient"); clear(s,far :: number)
    local patient=place(s,1,"Warrior",center,40); place(s,1,"Archer",far :: number,nil,{"Cover1","Medic"})
    apply(s,1,{kind="EndTurn"}); apply(s,2,{kind="EndTurn"})
    assert(unitById(s,patient.id).hp==50,"a medic two hexes away does not help")
end

-- 7. The AI spends its pending levels after acting: the Drill line on rough ground, Shock on open ground, Accuracy
--    first for ranged units.
do
    local function aiChoice(kind: string,terrain: string,xp: number): (any,any)
        local s=Game.new(81,{humanPlayers=1,radius=6})
        apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id})
        local u=firstUnit(s,2,"Warrior"); u.kind=kind; u.hp=5; u.xp=xp
        if kind=="Archer" then table.insert(s.players[2].technologies,"Archery"); table.insert(s.players[2].technologies,"Agriculture") end
        local tile=s.tiles[u.tileId]; tile.terrain=terrain; tile.resource=nil; tile.improvement=nil
        assert(Save.valid(Game.serialize(s)))
        apply(s,1,{kind="EndTurn"})
        assert(Save.valid(Game.serialize(s)),"the AI's choices are valid saves")
        return s,u
    end
    local s,u=aiChoice("Warrior","Plains",10)
    assert(equal(u.promotions,{"Shock1"}) and u.level==1,"open ground: Shock I")
    assert(u.fortified and u.hp>=55,"the weak unit fortified, then the promotion healed 50")
    local e=lastEvent(s,"Promotion"); assert(e and e.ownerId==2 and e.unitId==u.id)
    s,u=aiChoice("Warrior","Hills",10); assert(equal(u.promotions,{"Drill1"}),"rough ground: Drill I")
    s,u=aiChoice("Warrior","Forest",30); assert(equal(u.promotions,{"Drill1","Drill2"}),"two levels in Forest: the Drill line")
    s,u=aiChoice("Warrior","Plains",100); assert(equal(u.promotions,{"Shock1","Shock2","Drill1","Drill2"}),"four levels on open ground")
    s,u=aiChoice("Archer","Plains",60); assert(equal(u.promotions,{"Accuracy1","Cover1","Medic"}),"ranged: Accuracy, Cover, Medic")
    s,u=aiChoice("Archer","Hills",210); assert(equal(u.promotions,{"Accuracy1","Cover1","Medic"}) and u.level==3,"a ranged unit stops after its three promotions")
    s,u=aiChoice("Warrior","Plains",9); assert(u.promotions==nil and u.level==0,"no level, no promotion")
    -- The AI's choices are valid saves.
    assert(Save.valid(Game.serialize(s)))
end

-- 8. Fog: level and promotions show with a visible unit; experience and pending choices are the owner's alone.
do
    local s: any=Game.restore(baseSave); assert(s)
    local enemy=place(s,2,"Warrior",ring[1],nil,{"Shock1","Drill1"}); enemy.xp=60
    place(s,1,"Warrior",center)
    local hidden: any=nil
    local graph=WorldMap.fromTiles(s.tiles,s.radius)
    local seen1={}; for _, u in s.units do if u.ownerId==1 then for _, t in s.tiles do if WorldMap.distance(graph,t.id,u.tileId)<=2 then seen1[t.id]=true end end end end
    for _, c in s.cities do if c.ownerId==1 then for _, t in s.tiles do if WorldMap.distance(graph,t.id,c.tileId)<=2 then seen1[t.id]=true end end end end
    for _, u in s.units do if u.ownerId==2 and not seen1[u.tileId] then hidden=u; break end end
    assert(hidden,"an enemy unit out of sight")
    promoted(hidden,{"Cover1"}); hidden.xp=12
    assert(Save.valid(Game.serialize(s)))
    local view=Game.snapshot(s,1)
    local ev=viewUnit(view,enemy.id); assert(ev,"the adjacent enemy is visible")
    assert(equal(ev.promotions,{"Shock1","Drill1"}) and ev.level==2,"visible promotions and level")
    assert(ev.xp==nil and ev.nextLevelXp==nil and ev.promotionsAvailable==nil,"no rival experience or choices")
    assert(viewUnit(view,hidden.id)==nil,"a hidden unit is not listed")
    for _, u in view.units do
        if u.ownerId==2 then assert(u.xp==nil and u.promotionsAvailable==nil) else assert(type(u.xp)=="number" and u.promotionsAvailable~=nil) end
        assert(type(u.promotions)=="table" and type(u.level)=="number")
    end
    -- The owner sees its own experience; choices are empty while it cannot act.
    local own=viewUnit(Game.snapshot(s,2),enemy.id)
    assert(own.xp==60 and own.nextLevelXp==100 and equal(own.promotionsAvailable,{}),"no choices out of turn")
    apply(s,1,{kind="EndTurn"})
    own=viewUnit(Game.snapshot(s,2),enemy.id); assert(equal(own.promotionsAvailable,{"Drill2","Shock2","Cover1"}),"choices on its turn")
    -- The snapshot is detached.
    own.promotions[1]="Medic"; assert(enemy.promotions[1]=="Shock1")
end

-- 9. Saves: a save from before experience and promotions restores unchanged and gains them in play; the new fields
--    are validated.
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
    -- The pre-G5 unit shape: no xp or promotions; unit 2 holds a veteran level the earlier validator accepted.
    local legacyState: any={seed=124,radius=3,difficulty="Normal",humanPlayers=2,forest=false,maxTurns=120,turn=5,revision=9,activePlayerId=1,phase="Playing",tiles=map.tiles,
        units={{id=1,ownerId=1,kind="Warrior",tileId=west,hp=100,moves=2,fortified=false,level=0},
            {id=2,ownerId=1,kind="Warrior",tileId=north,hp=40,moves=2,fortified=false,level=2},
            {id=3,ownerId=1,kind="Worker",tileId=east,hp=20,moves=2,fortified=false,level=0},
            {id=4,ownerId=2,kind="Settler",tileId=rival,hp=50,moves=2,fortified=false,level=0},
            {id=5,ownerId=2,kind="Warrior",tileId=foe,hp=100,moves=2,fortified=false,level=0}},
        cities={{id=1,ownerId=1,originalOwnerId=1,capital=true,tileId=hub,name="Fixture",population=2,food=0,production=0,queue="Warrior",hp=150,buildings={},focus="Balanced"}},players={},
        diplomacy={status="War",peaceUntil=0},trades={},events={{id=1,kind="FoundCity",message="City founded.",tileId=hub,ownerId=1}},nextEvent=2,nextUnit=6,nextCity=2,nextTrade=1,log={}}
    for id=1,2 do table.insert(legacyState.players,{id=id,human=true,gold=200,science=0,culture=0,happiness=9,technologies={},policies={},explored=table.clone(explored),resources={},income={food=0,production=0,gold=0,science=0,culture=0,maintenance=0}}) end
    local legacy={format="unciv-luau-base",version=1,state=legacyState}
    assert(Save.valid(legacy),"the legacy fixture is a valid version-1 save")
    local restored: any,err=Game.restore(legacy); assert(restored and err==nil,err)
    assert(equal(Game.serialize(restored),legacy),"restore keeps every stored field and adds none")
    local viaSave: any=Save.restore(legacy); assert(viaSave and equal(viaSave,legacyState))
    -- Snapshot defaults for the missing fields.
    local v=viewUnit(Game.snapshot(restored,1),1); assert(v.xp==0 and equal(v.promotions,{}) and v.level==0 and v.nextLevelXp==10)
    -- The veteran level adds no strength and counts as a level already spent: no choice until 60 experience.
    local veteran=unitById(restored,2)
    assert(#viewUnit(Game.snapshot(restored,1),2).promotionsAvailable==0)
    veteran.xp=59; assert(#viewUnit(Game.snapshot(restored,1),2).promotionsAvailable==0)
    veteran.xp=60; apply(restored,1,{kind="PromoteUnit",unitId=2,promotion="Cover1"})
    assert(veteran.level==3 and equal(veteran.promotions,{"Cover1"}) and Save.valid(Game.serialize(restored)))
    -- Ending turns without combat adds no field; a fight then writes experience, which round-trips.
    local quiet: any=Game.restore(legacy); assert(quiet)
    apply(quiet,1,{kind="EndTurn"}); apply(quiet,2,{kind="EndTurn"})
    for _, u in Game.serialize(quiet).state.units do assert(u.xp==nil and u.promotions==nil,"no new fields without combat") end
    local fought: any=Game.restore(legacy); assert(fought)
    local preview=Game.previewAttack(fought,1,1,foe :: number); assert(preview and preview.exact)
    apply(fought,1,{kind="MoveUnit",unitId=1,tileId=foe :: number})
    assert(unitById(fought,1).xp==5 and unitById(fought,5).xp==4)
    local again: any=Game.restore(Game.serialize(fought)); assert(again and unitById(again,1).xp==5 and equal(Game.serialize(again),Game.serialize(fought)))
    -- Validation of the new fields.
    local function variant(change: (any)->()): any
        local value=Game.serialize(restored); change(value.state); return value
    end
    local function accepts(change: (any)->(),label: string) assert(Save.valid(variant(change)),label.." rejected") end
    local function rejects(change: (any)->(),label: string)
        local value=variant(change); assert(not Save.valid(value),label.." accepted")
        local loaded,message=Save.restore(value); assert(loaded==nil and type(message)=="string")
        assert(Game.restore(value)==nil)
    end
    local function unit1(s: any): any for _, u in s.units do if u.id==1 then return u end end; error("unit 1") end
    accepts(function(s) unit1(s).xp=0 end,"zero experience")
    accepts(function(s) unit1(s).xp=210 end,"maximum experience")
    accepts(function(s) unit1(s).promotions={}; end,"an empty promotion list")
    accepts(function(s) local u=unit1(s); u.xp=30; u.level=2; u.promotions={"Drill1","Drill2"} end,"a promotion line")
    accepts(function(s) local u=unit1(s); u.xp=30; u.level=2; u.promotions={"Drill2","Drill1"} end,"any order")
    accepts(function(s) local u=unit1(s); u.xp=10; u.level=1; u.promotions={"Cover1"} end,"Cover I")
    rejects(function(s) unit1(s).xp=211 end,"experience above the maximum")
    rejects(function(s) unit1(s).xp=-1 end,"negative experience")
    rejects(function(s) unit1(s).xp=4.5 end,"fractional experience")
    rejects(function(s) unit1(s).xp="5" end,"text experience")
    rejects(function(s) for _, u in s.units do if u.kind=="Worker" then u.xp=5 end end end,"civilian experience")
    rejects(function(s) local u=unit1(s); u.xp=10; u.level=1; u.promotions={"Unknown"} end,"an unknown promotion id")
    rejects(function(s) local u=unit1(s); u.xp=30; u.level=2; u.promotions={"Drill1","Drill1"} end,"a duplicate promotion")
    rejects(function(s) local u=unit1(s); u.xp=10; u.level=1; u.promotions={"Drill2"} end,"a missing prerequisite")
    rejects(function(s) local u=unit1(s); u.xp=10; u.level=1; u.promotions={"Medic"} end,"Medic without Cover I")
    rejects(function(s) local u=unit1(s); u.xp=10; u.level=1; u.promotions={"Accuracy1"} end,"a ranged promotion on a melee unit")
    rejects(function(s) local u=unit1(s); u.xp=30; u.level=1; u.promotions={"Drill1","Drill2"} end,"more promotions than the level")
    rejects(function(s) local u=unit1(s); u.xp=9; u.level=1; u.promotions={"Drill1"} end,"more promotions than earned levels")
    rejects(function(s) local u=unit1(s); u.level=1; u.promotions={"Drill1"} end,"promotions without experience")
    rejects(function(s) unit1(s).promotions="Drill1" end,"a text promotion list")
    rejects(function(s) local u=unit1(s); u.xp=10; u.level=1; u.promotions={[2]="Drill1"} end,"a sparse promotion list")
    rejects(function(s) unit1(s).level=7 end,"a level above the last threshold")
    rejects(function(s) unit1(s).level=-1 end,"a negative level")
    rejects(function(s) unit1(s).experience=5 end,"an unknown unit field")
    rejects(function(s) table.insert(s.events,{id=s.nextEvent,kind="Promoted",message="x"}); s.nextEvent += 1 end,"an unknown event kind")
    accepts(function(s) table.insert(s.events,{id=s.nextEvent,kind="Promotion",message="Unit promoted: Cover I.",unitId=1,ownerId=1,unitKind="Warrior"}); s.nextEvent += 1 end,"a Promotion event")
end

-- 10. Determinism: solo wars in which both sides gain experience and promote replay identically, with and without
--     saves between turns.
do
    local function run(resume: boolean): (any,number)
        local s: any=Game.new(91,{humanPlayers=1,radius=5,difficulty="Hard"})
        apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id})
        for _, u in s.units do if Rules.units[u.kind].unitClass~="Civilian" then u.xp=8 end end
        local promotions=0
        for turn=1,40 do
            if s.phase~="Playing" then break end
            if turn==3 and s.diplomacy.status~="War" then apply(s,1,{kind="DeclareWar",targetId=2}) end
            local view=Game.snapshot(s,1)
            for _, u in view.units do
                local choices=u.promotionsAvailable or {}
                if u.ownerId==1 and #choices>0 then apply(s,1,{kind="PromoteUnit",unitId=u.id,promotion=choices[#choices]}) end
            end
            view=Game.snapshot(s,1); local ids={}
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
        for _, u in s.units do promotions += #(u.promotions or {}) end
        return Game.serialize(s),promotions
    end
    local first,count=run(false); local second=run(false); local resumed=run(true)
    assert(equal(first,second) and equal(first,resumed),"experience and promotions are deterministic")
    assert(count>0,"the replay must include promotions")
    local events=0; for _, e in first.state.events do if e.kind=="Promotion" then events += 1 end end
    print(string.format("  determinism run: %d promotions held by surviving units, %d Promotion events in the ring",count,events))
end

print("base promotions: experience per strike and thresholds, PromoteUnit validation, each promotion in strike and preview, medic healing, AI choice, fog-safe fields, legacy saves and determinism passed")
