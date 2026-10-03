--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original fixtures for G7 content: forty technologies in six eras, thirty units with separate attack, defence and
-- ranged values, twenty-five buildings, strategic resource quantities, the AI's use of the new content (its Colosseum
-- fix included), legacy saves and deterministic replays.
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
local function rejected(s: any,owner: number,command: any): string
    local before=Game.serialize(s)
    local result=Game.apply(s,owner,command); assert(not result.ok,"command must be rejected")
    assert(equal(before,Game.serialize(s)),"a rejection changes nothing")
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
local function place(s: any,owner: number,kind: string,tileId: number,hp: number?): any
    local u={id=s.nextUnit,ownerId=owner,kind=kind,tileId=tileId,hp=hp or Rules.units[kind].hp,moves=Rules.units[kind].moves,fortified=false,level=0}
    table.insert(s.units,u); s.nextUnit += 1; return u
end
local function viewUnit(view: any,id: number): any
    for _, u in view.units do if u.id==id then return u end end; return nil
end

-- 1. Content integrity: counts, unique ids in every order, an acyclic prerequisite graph listed in topological order,
--    eras that never decrease along it, every unit and building reachable, and upgrade paths that stay in their class.
do
    local function set(list: {string}, label: string): {[string]: boolean}
        local seen: {[string]: boolean}={}
        for _, id in list do assert(not seen[id],label.." lists "..id.." twice"); seen[id]=true end
        return seen
    end
    local function count(map: {[string]: any}): number local n=0; for _ in map do n += 1 end; return n end
    assert(#Rules.eras==6 and Rules.eras[1]=="Ancient" and Rules.eras[6]=="Modern")
    assert(#Rules.technologyOrder==40 and count(Rules.technologies)==40,"forty technologies")
    assert(#Rules.unitOrder==30 and count(Rules.units)==30,"thirty units")
    local ordinary=0; for _, rule in Rules.buildings do if not rule.wonder then ordinary += 1 end end
    assert(ordinary==25 and #Rules.buildingOrder==33 and count(Rules.buildings)==33,"twenty-five buildings and eight wonders")
    local techSet,unitSet,buildingSet=set(Rules.technologyOrder,"technologyOrder"),set(Rules.unitOrder,"unitOrder"),set(Rules.buildingOrder,"buildingOrder")
    for id in Rules.technologies do assert(techSet[id],id.." is ordered") end
    for id in Rules.units do assert(unitSet[id],id.." is ordered") end
    for id in Rules.buildings do assert(buildingSet[id],id.." is ordered") end
    -- Prerequisites exist and come earlier in the order (so the graph is acyclic); eras never decrease along an edge.
    local position: {[string]: number}={}
    for index, id in Rules.technologyOrder do
        local tech=Rules.technologies[id]
        assert(tech.id==id and type(tech.name)=="string" and #tech.name>0 and tech.era>=1 and tech.era<=6 and tech.cost>0)
        for _, prerequisite in tech.prerequisites do
            assert(position[prerequisite],id.." needs "..prerequisite.." first")
            assert(Rules.technologies[prerequisite].era<=tech.era,id.." comes no earlier than "..prerequisite)
        end
        position[id]=index
    end
    -- Every era has technologies, and the last one (the science victory) closes over most of the tree.
    local perEra={0,0,0,0,0,0}; for _, tech in Rules.technologies do perEra[tech.era] += 1 end
    for era=1,6 do assert(perEra[era]>=6,"era "..era.." has technologies") end
    local closure: {[string]: boolean}={}
    local function close(id: string) if closure[id] then return end; closure[id]=true; for _, p in Rules.technologies[id].prerequisites do close(p) end end
    close(Rules.scienceVictoryTechnology)
    assert(Rules.scienceVictoryTechnology=="SpaceFlight" and Rules.buildings.SpaceProject.technology=="SpaceFlight" and count(closure)==32,"the science victory needs thirty-two technologies")
    -- Every technology unlocks something: a unit, building, improvement or a later technology.
    local unlocks: {[string]: boolean}={}
    for _, rule in Rules.units do if rule.technology then unlocks[rule.technology]=true end end
    for _, rule in Rules.buildings do if rule.technology then unlocks[rule.technology]=true end end
    for _, rule in Rules.improvements do if rule.technology then unlocks[rule.technology]=true end end
    for _, tech in Rules.technologies do for _, p in tech.prerequisites do unlocks[p]=true end end
    for id in Rules.technologies do assert(unlocks[id],id.." unlocks something") end
    -- Units: valid technology and resource, eras in order, separate combat values, upgrades within the class.
    local lastEra=1
    for _, id in Rules.unitOrder do
        local rule=Rules.units[id]
        assert(rule.era>=lastEra,"units are in era order"); lastEra=rule.era
        assert(rule.era==(if rule.technology then Rules.technologies[rule.technology].era else 1),id.." era")
        assert(rule.strength==math.max(rule.attack,rule.defense) and rule.attack>=0 and rule.defense>=0,id.." strength")
        assert((rule.strength==0)==(rule.role=="Civilian") and (rule.unitClass=="Civilian")==(rule.role=="Civilian"),id.." role")
        assert((rule.range>1)==(rule.rangedStrength>0) and (rule.range>1)==(rule.unitClass=="Ranged"),id.." ranged values")
        assert(rule.resource==nil or (Rules.resources[rule.resource].category=="Strategic" and rule.resourceAmount==1),id.." resource")
        if rule.upgradeTo then
            local nextRule=Rules.units[rule.upgradeTo]
            assert(nextRule and nextRule.unitClass==rule.unitClass and nextRule.era>=rule.era and nextRule.cost>rule.cost,id.." upgrade")
        end
        for role in rule.versus do assert(role=="Mounted" or role=="Armor",id.." versus") end
    end
    -- Every unit is reachable: its technology is in the tree, and every kind but the four start kinds needs one.
    for id, rule in Rules.units do assert(rule.technology==nil or Rules.technologies[rule.technology],id.." technology") end
    lastEra=1
    for _, id in Rules.buildingOrder do
        local rule=Rules.buildings[id]
        if rule.wonder then continue end
        assert(rule.era>=lastEra,"ordinary buildings are in era order"); lastEra=rule.era
        assert(rule.technology==nil or Rules.technologies[rule.technology],id.." technology")
        local y=rule.yields; local effect=rule.happiness+rule.defense+y.food+y.production+y.gold+y.science+y.culture
        assert(effect>0 or id=="SpaceProject",id.." has an effect")
    end
    -- The sixteen technologies and eleven units from before G7 keep their numbers.
    local legacyTech: {[string]: {any}}={Agriculture={12},Mining={14},Archery={16,"Agriculture"},BronzeWorking={22,"Mining"},Writing={24,"Agriculture"},Masonry={22,"Mining"},
        IronWorking={38,"BronzeWorking"},Currency={38,"Writing"},Engineering={44,"Masonry","BronzeWorking"},Philosophy={42,"Writing"},CivilService={60,"Currency","Philosophy"},
        Education={70,"Philosophy","Engineering"},Astronomy={100,"Education"},Gunpowder={90,"Engineering","Education"},Rifling={130,"Gunpowder"},Rocketry={180,"Astronomy","Rifling"}}
    for id, row in legacyTech do
        local tech=Rules.technologies[id]
        assert(tech.cost==row[1] and #tech.prerequisites==#row-1,id.." keeps its cost and prerequisites")
        for index=2,#row do assert(table.find(tech.prerequisites,row[index]),id.." keeps "..row[index]) end
    end
    local legacyUnits: {[string]: {number}}={Scout={9,60,3,4},Warrior={12,100,2,10},Settler={24,50,2,0},Worker={16,50,2,0},Archer={18,70,2,5,12},Swordsman={28,100,2,18},Pikeman={30,100,2,20},
        Knight={42,100,3,26},Catapult={32,65,2,5,22},Musketman={48,100,2,30},Rifleman={62,100,2,42}}
    for id, row in legacyUnits do
        local rule=Rules.units[id]
        assert(rule.cost==row[1] and rule.hp==row[2] and rule.moves==row[3] and rule.strength==row[4] and rule.attack==row[4] and rule.defense==row[4] and rule.rangedStrength==(row[5] or 0),id.." keeps its numbers")
    end
    assert(Rules.units.Swordsman.resource=="Iron" and Rules.units.Knight.resource=="Horses" and Rules.units.Catapult.siegePercent==50)
    -- Resources: quantities, the two later strategic resources and their improvements.
    for _, id in Rules.resourceOrder do local r=Rules.resources[id]; assert(r.quantity==(if r.category=="Strategic" then 2 else 1) and r.name==id,id.." quantity") end
    assert(#Rules.resourceOrder==count(Rules.resources))
    assert(Rules.resources.Saltpeter.improvement=="Mine" and table.find(Rules.improvements.Mine.resources,"Saltpeter"))
    assert(Rules.resources.Oil.improvement=="Well" and Rules.improvements.Well.technology=="Combustion" and table.find(Rules.improvementOrder,"Well"))
    -- The Colosseum the AI's list named before G7 now exists: a happiness building.
    assert(Rules.buildings.Colosseum.happiness==3 and Rules.buildings.Colosseum.technology=="Construction")
    -- getRules exposes the new fields and is detached.
    local rules: any=Game.getRules()
    assert(rules.units.Horseman.attack==18 and rules.units.Horseman.defense==11 and rules.units.Spearman.versus.Mounted==50 and rules.technologies.Steel.era==3 and rules.resources.Oil.quantity==2)
    rules.units.Horseman.attack=99; assert(Game.getRules().units.Horseman.attack==18,"getRules is detached")
end

-- 1b. Victory pacing (G7): the science victory needs Space Flight, and a match without an explicit policy cost growth
--     takes policyCostIncrease (140) scaled by its pace (the round limit against 120 rounds, 50-200%).
do
    assert(Rules.scienceVictoryTechnology=="SpaceFlight" and Rules.cultureVictoryPolicies==6 and Rules.policyCostIncrease==140)
    for _, row in {{20,70},{45,70},{60,70},{80,94},{100,116},{120,140},{150,175},{240,280},{500,280}} do
        local s=Game.new(3,{maxTurns=row[1]}); assert(s.policyCostIncrease==row[2],"growth "..tostring(s.policyCostIncrease).." at "..row[1].." rounds")
        assert(Game.snapshot(s,1).policyCostIncrease==row[2],"the snapshot echoes it")
    end
    assert(Game.new(3,{maxTurns=45,policyCostIncrease=50}).policyCostIncrease==50 and Game.new(3,{policyCostIncrease=0}).policyCostIncrease==0,"an explicit value wins")
    -- Six policies at the Full default cost 235 + 1.4 x 750 = 1,285 culture (609 at the pre-G7 50%).
    local s: any=Game.new(3,{humanPlayers=2}); apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id}); s.players[1].culture=5000
    local spent=0
    for _, id in Rules.policyOrder do local before=s.players[1].culture; apply(s,1,{kind="AdoptPolicy",policy=id}); spent += before-s.players[1].culture end
    local expected=0; for index, id in Rules.policyOrder do expected += math.floor(Rules.policies[id].cost*(100+140*(index-1))/100) end
    assert(spent==expected and expected==1285,"six policies cost "..spent)
end

-- Combat fixture (as in base-combat): an open field away from both cities, at war, every technology known.
local function founded(seed: number): any
    local s=Game.new(seed,{humanPlayers=2,radius=8})
    for _, t in s.tiles do t.feature=nil; t.river=nil end
    apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id}); apply(s,1,{kind="EndTurn"})
    apply(s,2,{kind="FoundCity",unitId=firstUnit(s,2,"Settler").id}); apply(s,2,{kind="EndTurn"}); return s
end
local base=founded(71); apply(base,1,{kind="DeclareWar",targetId=2})
for _, p in base.players do p.technologies=table.clone(Rules.technologyOrder) end
local center: number,ring: {number}
do
    local graph=WorldMap.fromTiles(base.tiles,base.radius)
    for _, tile in base.tiles do
        local neighbors=graph.neighbors[tile.id]
        if #neighbors~=6 then continue end
        local far=true
        for _, c in base.cities do if WorldMap.distance(graph,tile.id,c.tileId)<4 then far=false end end
        for _, u in base.units do if WorldMap.distance(graph,tile.id,u.tileId)<3 then far=false end end
        if not far then continue end
        center=tile.id; ring=table.clone(neighbors); table.sort(ring); break
    end
    assert(center,"an open field")
    for _, id in {center,table.unpack(ring)} do local t=base.tiles[id]; t.terrain="Plains"; t.resource=nil; t.improvement=nil; t.road=nil; t.ownerId=nil end
end
local baseSave=Game.serialize(base)
-- Independent statement of the strike (numbers written out): separate attack and defence, the versus bonuses, terrain
-- and fortification.
local function versus(kind: string,otherKind: string): number
    local role=Rules.units[otherKind].role
    if (kind=="Spearman" or kind=="Pikeman") and role=="Mounted" then return 50 end
    if kind=="AntiTankGun" and role=="Armor" then return 75 end
    return 0
end
local function reference(attackerKind: string,attackerHp: number,defenderKind: string,defenderHp: number,terrain: string,fortified: boolean): (number,number)
    local a,d=Rules.units[attackerKind],Rules.units[defenderKind]; local ranged=a.range>1
    local attack=math.max(1,if ranged then a.rangedStrength else a.attack)*(0.5+attackerHp/200)*(100+versus(attackerKind,defenderKind))/100
    local percent=(if terrain=="Hills" then 25 else 0)+(if fortified then 50 else 0)+versus(defenderKind,attackerKind)
    local defense=math.max(3,d.defense)*(100+percent)/100*(0.5+defenderHp/200)
    local dealt=math.clamp(math.floor(30*attack/math.max(1,defense)+0.5),8,65)
    local received=if ranged or d.strength==0 then 0 else math.clamp(math.floor(25*defense/attack+0.5),8,65)
    return dealt,received
end
local function fight(attackerKind: string,defenderKind: string,setup: any?): (any,number,number)
    local o=setup or {}
    local s: any=Game.restore(baseSave); assert(s)
    s.tiles[center].terrain=o.terrain or "Plains"
    local attacker=place(s,1,attackerKind,ring[1],o.attackerHp); local defender=place(s,2,defenderKind,center,o.defenderHp)
    defender.fortified=o.fortified==true and Rules.units[defenderKind].strength>0
    assert(Save.valid(Game.serialize(s)),"fixture must be a valid state")
    local preview=Game.previewAttack(s,1,attacker.id,center); assert(preview and preview.exact,"preview missing")
    local listed: any=nil
    for _, p in Game.snapshot(s,1).attackPreviews[tostring(attacker.id)] do if p.tileId==center then listed=p end end
    assert(listed and equal(listed,preview),"snapshot preview equals the query")
    local attackerHp,defenderHp=attacker.hp,defender.hp
    apply(s,1,{kind=if Rules.units[attackerKind].range>1 then "RangedAttack" else "MoveUnit",unitId=attacker.id,tileId=center})
    local after,hit=unitById(s,attacker.id),unitById(s,defender.id)
    local dealt=if hit then defenderHp-hit.hp else preview.dealt
    local received=if after then attackerHp-after.hp else preview.received
    assert(dealt==preview.dealt and received==preview.received,"the applied strike equals the preview")
    if not hit then assert(preview.defenderDefeated=="Yes" and defenderHp-preview.dealt<=0) end
    local expectedDealt,expectedReceived=reference(attackerKind,attackerHp,defenderKind,defenderHp,o.terrain or "Plains",defender.fortified)
    assert(dealt==expectedDealt and received==expectedReceived,attackerKind.." on "..defenderKind..": "..dealt.."/"..received.." vs "..expectedDealt.."/"..expectedReceived)
    return preview,dealt,received
end

-- 2. Combat with separate attack and defence: worked examples and every military kind attacking and defending.
do
    local function expect(attackerKind: string,defenderKind: string,dealt: number,received: number)
        local _,d,r=fight(attackerKind,defenderKind)
        assert(d==dealt and r==received,attackerKind.." on "..defenderKind..": expected "..dealt.."/"..received..", got "..d.."/"..r)
    end
    expect("Warrior","Warrior",30,25)       -- unchanged from before G7
    expect("Horseman","Warrior",54,14)      -- attack 18 against defence 10
    expect("Warrior","Horseman",27,28)      -- attack 10 against defence 11
    expect("Spearman","Horseman",49,15)     -- 12 x 150% against 11
    expect("Horseman","Spearman",26,29)     -- 18 against 14 x 150%
    expect("Tank","AntiTankGun",23,33)      -- 70 against 52 x 175%
    -- Every military kind as attacker against a set of defenders, and as defender against a set of attackers.
    local military: {string}={}; for _, id in Rules.unitOrder do if Rules.units[id].strength>0 then table.insert(military,id) end end
    local defenders={"Warrior","Spearman","Horseman","Musketman","Tank","GatlingGun","Worker"}
    local attackers={"Warrior","Horseman","Pikeman","Crossbowman","Cannon","AntiTankGun"}
    local cases=0
    for index, kind in military do
        local defender=defenders[index%#defenders+1]
        fight(kind,defender,{terrain=if index%2==0 then "Hills" else "Plains",fortified=index%3==0,attackerHp=Rules.units[kind].hp-(index*7)%40})
        fight(attackers[index%#attackers+1],kind,{terrain=if index%3==0 then "Hills" else "Plains",fortified=index%2==1,defenderHp=Rules.units[kind].hp-(index*5)%30})
        cases += 2
    end
    assert(cases==2*#military and #military==28)
    -- The garrison adds a quarter of its defence (G7 garrisons use defence, not attack): a Horseman (defence 11) adds 2.
    local s: any=Game.restore(baseSave); local home=firstCity(s,1)
    local before: number=0; for _, c in Game.snapshot(s,1).cities do if c.id==home.id then before=c.strength :: number end end
    place(s,1,"Horseman",home.tileId)
    local after: number=0; for _, c in Game.snapshot(s,1).cities do if c.id==home.id then after=c.strength :: number end end
    assert(after-before==2,"a Horseman garrison adds floor(11 x 25%)")
end

-- 3. Eras are defined by technologies: the highest era among those known, public as progress.era, and they set the
--    city-strength era term.
do
    local s: any=Game.restore(baseSave)
    local cases: {{any}}={{{},1},{{"Agriculture","Mining","Masonry"},1},{{"Mining","BronzeWorking"},2},{{"Agriculture","Writing","Currency","Philosophy","CivilService"},3},
        {table.move(Rules.technologyOrder,1,table.find(Rules.technologyOrder,"Rifling") :: number,1,{}),5},{table.clone(Rules.technologyOrder),6}}
    for _, case in cases do
        s.players[1].technologies=case[1]
        assert(Save.valid(Game.serialize(s)),"a valid technology set")
        local view=Game.snapshot(s,1)
        assert(view.progress[1].era==case[2],"era "..view.progress[1].era.." vs "..case[2])
    end
end

-- Strategic fixture: a city with an improved Horses tile (two Horses) and every technology known.
local function strategicFixture(): (any,any,any)
    local s: any=Game.restore(baseSave); local home=firstCity(s,1)
    local graph=WorldMap.fromTiles(s.tiles,s.radius)
    local tile: any=nil
    for _, id in graph.neighbors[home.tileId] do local t=s.tiles[id]; if t.ownerId==1 and Rules.terrains[t.terrain].passable then tile=t; break end end
    assert(tile,"an owned tile beside the city")
    tile.terrain="Plains"; tile.feature=nil; tile.resource="Horses"; tile.improvement="Pasture"
    for _, other in s.tiles do if other~=tile and other.ownerId==1 and other.resource then other.improvement=nil end end
    s.players[1].gold=5000
    for _, u in s.units do if u.ownerId==1 and u.kind=="Warrior" then u.tileId=home.tileId end end
    return s,home,tile
end

-- 4. Strategic resource quantities: have (tiles x quantity) and used (living units), production and purchases blocked
--    with a message naming the shortage, forecasts, upgrades that free the unit's own use, and own-only reporting.
do
    local s,home,tile=strategicFixture()
    local view=Game.snapshot(s,1)
    assert(equal(view.strategic,{Horses={have=2,used=0},Iron={have=0,used=0},Saltpeter={have=0,used=0},Oil={have=0,used=0}}),"strategic stock")
    assert(view.resources.Horses==1,"resources still counts improved tiles")
    apply(s,1,{kind="Purchase",cityId=home.id,item="Knight"}); apply(s,1,{kind="Purchase",cityId=home.id,item="Cavalry"})
    view=Game.snapshot(s,1); assert(equal(view.strategic.Horses,{have=2,used=2}))
    assert(not table.find(view.availableProductionByCity[tostring(home.id)],"Lancer") and table.find(view.availableProductionByCity[tostring(home.id)],"Musketman"),"mounted units leave the menu")
    assert(rejected(s,1,{kind="SetProduction",cityId=home.id,item="Lancer"})=="Not enough Horses: needs 1, 2 available and 2 in use.")
    assert(rejected(s,1,{kind="Purchase",cityId=home.id,item="Horseman"})=="Not enough Horses: needs 1, 2 available and 2 in use.")
    assert(rejected(s,1,{kind="SetProduction",cityId=home.id,item="Nothing"})=="Production item is unavailable.")
    -- The rival's snapshot reports only its own (empty) stock.
    assert(equal(Game.snapshot(s,2).strategic.Horses,{have=0,used=0}),"strategic is own-only")
    -- A queued unit short of its resource is reported blocked and completes nothing.
    home.queue="Chariot"; home.production=500
    assert(Game.snapshot(s,1).cityForecasts[tostring(home.id)].productionBlocked=="NotAvailable")
    -- Upgrades: a Knight becoming a Lancer frees its own Horses; the view shows the upgrade, its cost and readiness.
    local knight=firstUnit(s,1,"Knight"); knight.moves=3
    local kv=viewUnit(Game.snapshot(s,1),knight.id)
    assert(kv.upgradeKind=="Lancer" and kv.upgradeCost==math.max(20,56-42)*2 and kv.canUpgrade==true,"upgrade fields")
    assert(viewUnit(Game.snapshot(s,2),knight.id)==nil or viewUnit(Game.snapshot(s,2),knight.id).upgradeKind==nil,"a rival never sees upgrade fields")
    local gold=s.players[1].gold
    apply(s,1,{kind="UpgradeUnit",unitId=knight.id})
    assert(knight.kind=="Lancer" and knight.moves==0 and s.players[1].gold==gold-40 and equal(Game.snapshot(s,1).strategic.Horses,{have=2,used=2}))
    -- A Warrior cannot become a Swordsman without Iron: the shortage message.
    local warrior=firstUnit(s,1,"Warrior"); warrior.moves=2
    assert(viewUnit(Game.snapshot(s,1),warrior.id).canUpgrade==false)
    assert(rejected(s,1,{kind="UpgradeUnit",unitId=warrior.id})=="Not enough Iron: needs 1, 0 available and 0 in use.")
    -- Losing the tile leaves the units (used above have) and blocks any more.
    tile.improvement=nil
    view=Game.snapshot(s,1); assert(equal(view.strategic.Horses,{have=0,used=2}) and firstUnit(s,1,"Cavalry"))
    assert(Save.valid(Game.serialize(s)),"used above have is a valid state")
    -- The global unit cap no longer blocks an upgrade (no unit is added).
    local full: any=Game.new(9,{humanPlayers=2,radius=14})
    apply(full,1,{kind="FoundCity",unitId=firstUnit(full,1,"Settler").id}); apply(full,1,{kind="EndTurn"})
    apply(full,2,{kind="FoundCity",unitId=firstUnit(full,2,"Settler").id}); apply(full,2,{kind="EndTurn"})
    full.players[1].technologies=table.clone(Rules.technologyOrder); full.players[1].gold=5000
    local fullHome=firstCity(full,1)
    local iron: any=nil
    for _, t in full.tiles do if t.ownerId==1 and t.id~=fullHome.tileId and Rules.terrains[t.terrain].passable then local free=true; for _, u in full.units do if u.tileId==t.id then free=false end end; if free then iron=t; break end end end
    for _, t in full.tiles do t.river=nil end
    iron.terrain="Hills"; iron.feature=nil; iron.resource="Iron"; iron.improvement="Mine"
    local swordsman=firstUnit(full,1,"Warrior"); swordsman.moves=2
    local occupied: {[number]: boolean}={}; for _, u in full.units do occupied[u.tileId]=true end
    for _, c in full.cities do occupied[c.tileId]=true end
    for _, t in full.tiles do
        if #full.units>=Rules.maxUnits then break end
        if not occupied[t.id] and Rules.terrains[t.terrain].passable then place(full,1,"Worker",t.id); occupied[t.id]=true end
    end
    assert(#full.units==Rules.maxUnits,"the unit cap is reached")
    apply(full,1,{kind="UpgradeUnit",unitId=swordsman.id}); assert(swordsman.kind=="Swordsman","an upgrade at the unit cap")
end

-- 5. Saltpeter and Oil: Mines and Wells, validated improvements and the save schema.
do
    local s,home,tile=strategicFixture()
    tile.resource="Oil"; tile.improvement="Well"
    assert(Save.valid(Game.serialize(s)),"a Well on Oil")
    assert(equal(Game.snapshot(s,1).strategic.Oil,{have=2,used=0}))
    apply(s,1,{kind="Purchase",cityId=home.id,item="Tank"}); apply(s,1,{kind="Purchase",cityId=home.id,item="BattleTank"})
    assert(rejected(s,1,{kind="Purchase",cityId=home.id,item="RocketArtillery"})=="Not enough Oil: needs 1, 2 available and 2 in use.")
    local saved=Game.serialize(s)
    local function variant(change: (any) -> ()): boolean local copy=Game.restore(saved) :: any; change(copy); return Save.valid({format="unciv-luau-base",version=1,state=copy}) end
    assert(not variant(function(v) for _, t in v.tiles do if t.id==tile.id then t.resource=nil end end end),"a Well needs Oil")
    assert(variant(function(v) for _, t in v.tiles do if t.id==tile.id then t.resource="Saltpeter"; t.improvement="Mine" end end end),"a Mine on Saltpeter")
    assert(not variant(function(v) for _, t in v.tiles do if t.id==tile.id then t.terrain="Grassland" end end end),"Oil never on Grassland")
    assert(variant(function(v) v.players[1].resources={Saltpeter=1,Oil=2} end),"new resource counts")
    assert(not variant(function(v) v.players[1].resources={Coal=1} end),"an unknown resource")
    -- A worker builds a Well only on Oil and only with Combustion.
    local w,_,wellTile=strategicFixture(); wellTile.resource="Oil"; wellTile.improvement=nil
    local worker=firstUnit(w,1,"Worker"); worker.tileId=wellTile.id; worker.moves=2
    local menu=Game.snapshot(w,1).availableImprovements[tostring(worker.id)]; assert(table.find(menu,"Well"),"Well offered on Oil")
    w.players[1].technologies=table.move(Rules.technologyOrder,1,10,1,{})
    menu=Game.snapshot(w,1).availableImprovements[tostring(worker.id)]; assert(not table.find(menu,"Well"),"Well needs Combustion")
end

-- AI fixture: a solo game without barbarians in which the AI knows `technologies`, its capital has `population`, its
-- treasury and last net gold are comfortable, and the human's units are far away.
local function aiFixture(technologies: {string}, population: number): (any,any)
    local s: any=Game.new(23,{humanPlayers=1,radius=10,barbarians=false})
    for _, t in s.tiles do t.feature=nil; t.river=nil end
    apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id})
    local p=s.players[2]; p.technologies=technologies; p.research=nil; p.gold=200; p.income.gold=10
    local capital=firstCity(s,2); capital.population=population; capital.queue="Warrior"
    -- Any accepted command refreshes both civilizations' happiness, which the AI reads.
    apply(s,1,{kind="SetCityFocus",cityId=firstCity(s,1).id,focus="Food"})
    assert(Save.valid(Game.serialize(s)),"AI fixture must be valid")
    return s,capital
end

-- 6. The AI's Colosseum fix: an unhappy AI builds the Colosseum (its best contentment per cost), a content one never
--    does, and it never builds the culture-yielding Temple for contentment.
do
    local construction={"Agriculture","Mining","Masonry","Pottery","Construction"}
    local s,capital=aiFixture(table.clone(construction),12)
    assert(Game.snapshot(s,1).happiness~=nil)
    apply(s,1,{kind="EndTurn"})
    assert(s.players[2].happiness<1 and capital.queue=="Colosseum","an unhappy AI builds a Colosseum, got "..capital.queue)
    local content,happy=aiFixture(table.clone(construction),1)
    apply(content,1,{kind="EndTurn"})
    assert(content.players[2].happiness>=1 and happy.queue=="Monument","a content AI builds no Colosseum, got "..happy.queue)
    -- Without Construction the Shrine is its contentment building; with only Philosophy it never picks the Temple.
    local shrine,shrineCity=aiFixture({"Agriculture","Pottery"},12)
    apply(shrine,1,{kind="EndTurn"}); assert(shrineCity.queue=="Shrine","got "..shrineCity.queue)
    local temple,templeCity=aiFixture({"Agriculture","Writing","Philosophy"},12)
    apply(temple,1,{kind="EndTurn"}); assert(templeCity.queue~="Temple" and templeCity.queue=="Monument","got "..templeCity.queue)
    -- A threatened city builds Walls first: a hostile military unit within three hexes during a war.
    local threatened,city=aiFixture({"Agriculture","Mining","Masonry"},1)
    threatened.diplomacy.status="War"
    local graph=WorldMap.fromTiles(threatened.tiles,threatened.radius)
    local near: number?=nil
    for _, id in WorldMap.range(graph,city.tileId,2) do
        local t=threatened.tiles[id]
        if id~=city.tileId and Rules.terrains[t.terrain].passable then
            local free=true; for _, u in threatened.units do if u.tileId==id then free=false end end
            if free then near=id; break end
        end
    end
    place(threatened,1,"Warrior",near :: number)
    apply(threatened,1,{kind="EndTurn"}); assert(city.queue=="Walls","a threatened city builds Walls, got "..city.queue)
end

-- 7. The AI upgrades in its own territory when it can pay, and keeps a gold reserve.
do
    local s,capital=aiFixture({"Agriculture","Mining","BronzeWorking","IronWorking"},3)
    local graph=WorldMap.fromTiles(s.tiles,s.radius)
    local mine: any=nil
    for _, id in graph.neighbors[capital.tileId] do local t=s.tiles[id]; if t.ownerId==2 and Rules.terrains[t.terrain].passable then local free=true; for _, u in s.units do if u.tileId==id then free=false end end; if free then mine=t; break end end end
    mine.terrain="Hills"; mine.resource="Iron"; mine.improvement="Mine"
    local warrior=firstUnit(s,2,"Warrior"); warrior.tileId=capital.tileId
    assert(Save.valid(Game.serialize(s)))
    local poor=Game.restore(Game.serialize(s)) :: any; poor.players[2].gold=50
    apply(s,1,{kind="EndTurn"})
    assert(unitById(s,warrior.id).kind=="Swordsman","the AI upgrades its Warrior")
    apply(poor,1,{kind="EndTurn"})
    assert(unitById(poor,warrior.id).kind=="Warrior","the AI keeps a 40-gold reserve")
end

-- 8. A save written before G7 (old technologies, units and resource keys) restores unchanged and plays on under the G7
--    rules: tech-defined eras, two Iron per mine, the Swordsman's upgrade to the Longswordsman.
do
    local s: any=Game.restore(baseSave)
    for _, p in s.players do p.technologies={"Agriculture","Mining","Archery","BronzeWorking","Writing","Masonry","IronWorking","Currency","Engineering","Philosophy","CivilService"}; p.resources={} end
    for _, u in s.units do u.xp=nil; u.promotions=nil end
    local legacy=Game.serialize(s)
    local restored=Game.restore(legacy) :: any; assert(restored and equal(Game.serialize(restored),legacy),"a pre-G7 save restores unchanged")
    assert(Save.restore(legacy),"both restore paths")
    assert(Game.snapshot(restored,1).progress[1].era==3,"Civil Service makes the Medieval era")
    local warrior=place(restored,1,"Swordsman",ring[1]); warrior.moves=2
    local view=viewUnit(Game.snapshot(restored,1),warrior.id); assert(view.upgradeKind==nil,"Longswordsman needs Steel")
    restored.players[1].technologies=table.clone(Rules.technologyOrder)
    view=viewUnit(Game.snapshot(restored,1),warrior.id); assert(view.upgradeKind=="Longswordsman")
end

-- 9. Deterministic AI games with the G7 content: solo games replay identically with and without saves between turns,
--    the AI uses new content, and every queue stays a valid item.
do
    local function run(seed: number, resume: boolean): (any,{[string]: boolean})
        local s: any=Game.new(seed,{humanPlayers=1,radius=10,maxTurns=90})
        apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id})
        local used: {[string]: boolean}={}
        for _=1,90 do
            if s.phase~="Playing" then break end
            local view=Game.snapshot(s,1)
            if not s.players[1].research and #view.availableResearch>0 then apply(s,1,{kind="Research",technology=view.availableResearch[1].id}) end
            apply(s,1,{kind="EndTurn"})
            for _, c in s.cities do if c.ownerId==2 then used[c.queue]=true; for _, b in c.buildings do used[b]=true end end end
            for _, u in s.units do if u.ownerId==2 then used[u.kind]=true end end
            if resume then s=Game.restore(Game.serialize(s)) end
        end
        return Game.serialize(s),used
    end
    local legacyItems={Scout=true,Warrior=true,Settler=true,Worker=true,Archer=true,Swordsman=true,Pikeman=true,Knight=true,Catapult=true,Musketman=true,Rifleman=true,
        Monument=true,Granary=true,Library=true,Walls=true,Market=true,Workshop=true,Temple=true,University=true,GuildHall=true,Observatory=true,SpaceProject=true}
    for _, seed in {5,42} do
        local first,used=run(seed,false); local again=run(seed,false); local resumed=run(seed,true)
        assert(equal(first,again) and equal(first,resumed),"G7 AI games are deterministic (seed "..seed..")")
        local fresh=0; for id in used do if not legacyItems[id] and not (Rules.buildings[id] and Rules.buildings[id].wonder) then fresh += 1 end end
        assert(fresh>=2,"the AI uses G7 content (seed "..seed..")")
        local names={}; for id in used do if not legacyItems[id] then table.insert(names,id) end end; table.sort(names)
        print(string.format("  seed %d: phase %s at round %d; AI G7 items: %s",seed,first.state.phase,first.state.turn,table.concat(names,", ")))
    end
end

print("base content: forty technologies in six eras with an acyclic tree, thirty units with separate attack, defence and ranged values in exact previews, twenty-five buildings, strategic quantities and shortage messages, upgrades, the AI's Colosseum, Walls and upgrades, pre-G7 saves and deterministic AI games passed")
