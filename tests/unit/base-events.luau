--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original fixtures for loser-owned loss events, fog-safe combat previews, revealed final
-- scores with coarse progress, and the configurable escalating culture race.
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
local function founded(seed: number,radius: number?): any
    local s=Game.new(seed,{humanPlayers=2,radius=radius or 4})
    -- These fixtures pin earlier rules on bare terrain: terrain features and rivers (G4) are removed from the whole map.
    for _, t in s.tiles do t.feature=nil; t.river=nil end
    apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id}); apply(s,1,{kind="EndTurn"})
    apply(s,2,{kind="FoundCity",unitId=firstUnit(s,2,"Settler").id}); apply(s,2,{kind="EndTurn"}); return s
end
local function graphOf(s: any): any return WorldMap.fromTiles(s.tiles,s.radius) end
local function clear(s: any,id: number,terrain: string?)
    local t=s.tiles[id]; t.terrain=terrain or "Plains"; t.resource=nil; t.improvement=nil; t.road=nil
end
local function eventsOf(view: any,kind: string): {any}
    local found={}; for _, e in view.events do if e.kind==kind then table.insert(found,e) end end; return found
end
-- Two adjacent free tiles, away from every city, and the defender tile at least `gap` hexes
-- from all other units/cities of `defenderOwner`.
local function arena(s: any,gap: number,defenderOwner: number,skip: {[number]: boolean}?): (number,number)
    local graph=graphOf(s); local used={}
    for _, u in s.units do used[u.tileId]=true end; for _, c in s.cities do used[c.tileId]=true end
    for _, tile in s.tiles do
        if used[tile.id] then continue end
        local far=true
        for _, c in s.cities do if WorldMap.distance(graph,tile.id,c.tileId)<gap then far=false end end
        for _, u in s.units do if u.ownerId==defenderOwner and not (skip and skip[u.id]) and WorldMap.distance(graph,tile.id,u.tileId)<gap then far=false end end
        if not far then continue end
        for _, id in graph.neighbors[tile.id] do
            local near=false; for _, c in s.cities do if WorldMap.distance(graph,id,c.tileId)<2 then near=true end end
            if not used[id] and not near then return id,tile.id end
        end
    end
    error("no arena")
end

-- 1. Loss events are owned by the loser and reach its projection regardless of fog.
do
    local s=founded(31,8); apply(s,1,{kind="DeclareWar",targetId=2})
    local attacker=firstUnit(s,1,"Warrior"); local victim=firstUnit(s,2,"Worker")
    local from,to=arena(s,4,2,{[victim.id]=true}); clear(s,from); clear(s,to)
    attacker.tileId=from; attacker.moves=2; victim.tileId=to; victim.hp=5
    apply(s,1,{kind="MoveUnit",unitId=attacker.id,tileId=to})
    local loserView=Game.snapshot(s,2)
    assert(loserView.tiles[to].visible==false,"fixture must place the loss outside the loser's sight")
    local lost=eventsOf(loserView,"UnitLost")
    assert(#lost==1 and lost[1].ownerId==2 and lost[1].unitId==victim.id and lost[1].unitKind=="Worker" and lost[1].cause=="Combat" and lost[1].byOwnerId==1 and lost[1].tileId==to and lost[1].amount>=5)
    assert(lost[1].message=="Your Worker was destroyed.")
    -- The winner sees the loss only through ordinary tile visibility.
    assert(#eventsOf(Game.snapshot(s,1),"UnitLost")==1)
    local saved=Game.serialize(s); assert(Save.valid(saved)); local restored=Game.restore(saved); assert(restored and equal(Game.serialize(restored),saved))
    for _, field in {{"cause","Teleport"},{"byOwnerId",3},{"unitKind","Dragon"}} do
        local bad=Game.serialize(s)
        for _, e in bad.state.events do if e.kind=="UnitLost" then e[field[1]]=field[2] end end
        assert(not Save.valid(bad),"loss event field "..field[1].." must be validated")
    end
end
-- A burst of routine events in later commands never displaces a loss from the 64-event ring.
do
    local s=founded(31,8); apply(s,1,{kind="DeclareWar",targetId=2})
    local attacker=firstUnit(s,1,"Warrior"); local victim=firstUnit(s,2,"Worker")
    local from,to=arena(s,4,2,{[victim.id]=true}); clear(s,from); clear(s,to)
    attacker.tileId=from; attacker.moves=2; victim.tileId=to; victim.hp=5
    apply(s,1,{kind="MoveUnit",unitId=attacker.id,tileId=to})
    -- The loss is now the oldest event and the ring is full of routine events behind it.
    while s.events[1].kind~="UnitLost" do table.remove(s.events,1) end
    while #s.events<64 do table.insert(s.events,{id=s.nextEvent,kind="Move",message="Moved.",ownerId=1}); s.nextEvent += 1 end
    assert(Save.valid(Game.serialize(s)))
    s.players[1].culture=1000
    for index=1,3 do apply(s,1,{kind="AdoptPolicy",policy=Rules.policyOrder[index]}) end
    assert(#s.events==64 and s.events[1].kind=="UnitLost" and s.events[64].kind=="Policy")
    assert(#eventsOf(Game.snapshot(s,2),"UnitLost")==1,"the loser still sees its loss after the burst")
    local saved=Game.serialize(s); assert(Save.valid(saved)); assert(Game.restore(saved))
    -- A partial ring must stay contiguous; a full ring may have eviction gaps.
    local gap=Game.serialize(s); table.remove(gap.state.events,2); assert(not Save.valid(gap),"a partial ring with a gap is corrupt")
    -- A ring holding only retained kinds evicts its oldest event, and the newest is always kept.
    for i=1,#s.events do local e=s.events[i]; s.events[i]={id=e.id,kind="UnitLost",message="Your Warrior was destroyed.",ownerId=2,cause="Combat",byOwnerId=1,unitKind="Warrior"} end
    local oldest=s.events[1].id
    apply(s,1,{kind="AdoptPolicy",policy=Rules.policyOrder[4]})
    assert(#s.events==64 and s.events[1].id>oldest and s.events[64].kind=="Policy" and Save.valid(Game.serialize(s)))
end
-- An attacker that dies is reported to its own owner; ranged kills record the Ranged cause.
do
    local s=founded(32,8); apply(s,1,{kind="DeclareWar",targetId=2})
    local attacker=firstUnit(s,1,"Warrior"); local defender=firstUnit(s,2,"Warrior")
    local from,to=arena(s,3,2,{[defender.id]=true}); clear(s,from); clear(s,to,"Hills")
    attacker.tileId=from; attacker.moves=2; attacker.hp=4; defender.tileId=to; defender.fortified=true
    apply(s,1,{kind="MoveUnit",unitId=attacker.id,tileId=to})
    local lost=eventsOf(Game.snapshot(s,1),"UnitLost")
    assert(#lost==1 and lost[1].ownerId==1 and lost[1].unitId==attacker.id and lost[1].byOwnerId==2 and lost[1].cause=="Combat" and lost[1].tileId==from)
    assert(#eventsOf(Game.snapshot(s,2),"UnitLost")==1,"the defender sees the visible attacker die")
    local r=founded(33,8); apply(r,1,{kind="DeclareWar",targetId=2})
    local archer=firstUnit(r,1,"Warrior"); archer.kind="Archer"; archer.hp=Rules.units.Archer.hp; r.players[1].technologies={"Agriculture","Archery"}
    local target=firstUnit(r,2,"Worker"); local a,b=arena(r,3,2,{[target.id]=true}); clear(r,a); clear(r,b)
    archer.tileId=a; archer.moves=2; target.tileId=b; target.hp=1
    apply(r,1,{kind="RangedAttack",unitId=archer.id,tileId=b})
    local ranged=eventsOf(Game.snapshot(r,2),"UnitLost")
    assert(#ranged==1 and ranged[1].cause=="Ranged" and ranged[1].byOwnerId==1 and ranged[1].ownerId==2)
    assert(Save.valid(Game.serialize(r)))
end
-- City capture: CityLost for the loser alongside the capturer's Capture; capital loss ends
-- the match with a public Eliminated(CapitalsLost) owned by the loser.
do
    local s=founded(34); local capital=firstCity(s,2); local graph=graphOf(s)
    local attacker=firstUnit(s,1,"Warrior"); local occupied={}; for _, u in s.units do occupied[u.tileId]=true end
    for _, id in graph.neighbors[capital.tileId] do if not occupied[id] then attacker.tileId=id; clear(s,id); break end end
    attacker.moves=2; capital.hp=1; apply(s,1,{kind="DeclareWar",targetId=2})
    apply(s,1,{kind="MoveUnit",unitId=attacker.id,tileId=capital.tileId})
    assert(s.phase=="Finished" and s.winner==1)
    local view=Game.snapshot(s,2)
    local cityLost=eventsOf(view,"CityLost"); local eliminated=eventsOf(view,"Eliminated")
    assert(#cityLost==1 and cityLost[1].ownerId==2 and cityLost[1].byOwnerId==1 and cityLost[1].cause=="Captured" and cityLost[1].tileId==capital.tileId)
    assert(#eliminated==1 and eliminated[1].ownerId==2 and eliminated[1].public==true and eliminated[1].cause=="CapitalsLost" and eliminated[1].byOwnerId==1)
    assert(#eventsOf(Game.snapshot(s,1),"Eliminated")==1 and #eventsOf(Game.snapshot(s,1),"Capture")==1)
    assert(Save.valid(Game.serialize(s)))
end
-- Losing the last (non-capital) city reports NoCities; a civilization that never founded
-- a city and loses its settler reports NeverFounded.
do
    local s=founded(35); local city=firstCity(s,2); city.capital=false; local graph=graphOf(s)
    local attacker=firstUnit(s,1,"Warrior"); local occupied={}; for _, u in s.units do occupied[u.tileId]=true end
    for _, id in graph.neighbors[city.tileId] do if not occupied[id] then attacker.tileId=id; clear(s,id); break end end
    attacker.moves=2; city.hp=1; apply(s,1,{kind="DeclareWar",targetId=2})
    apply(s,1,{kind="MoveUnit",unitId=attacker.id,tileId=city.tileId})
    local e=eventsOf(Game.snapshot(s,2),"Eliminated"); assert(#e==1 and e[1].cause=="NoCities" and s.winner==1)
    local n=Game.new(36,{humanPlayers=2,radius=8})
    apply(n,1,{kind="FoundCity",unitId=firstUnit(n,1,"Settler").id}); apply(n,1,{kind="DeclareWar",targetId=2})
    local settler=firstUnit(n,2,"Settler"); local warrior=firstUnit(n,1,"Warrior")
    local a,b=arena(n,3,2,{[settler.id]=true}); clear(n,a); clear(n,b)
    warrior.tileId=a; warrior.moves=2; settler.tileId=b; settler.hp=1
    apply(n,1,{kind="MoveUnit",unitId=warrior.id,tileId=b})
    local view=Game.snapshot(n,2)
    assert(#eventsOf(view,"UnitLost")==1 and eventsOf(view,"UnitLost")[1].unitKind=="Settler")
    local never=eventsOf(view,"Eliminated"); assert(#never==1 and never[1].cause=="NeverFounded" and never[1].ownerId==2 and n.winner==1)
end
-- Upkeep disbanding keeps its Disband event, owned by the loser, now with cause and kind.
do
    local s=founded(37,8); s.players[1].gold=0
    local used={}; for _, u in s.units do used[u.tileId]=true end; for _, c in s.cities do used[c.tileId]=true end
    local added=0
    for _, tile in s.tiles do
        if added>=20 then break end
        if not used[tile.id] and Rules.terrains[tile.terrain].passable then table.insert(s.units,{id=s.nextUnit,ownerId=1,kind="Warrior",tileId=tile.id,hp=100,moves=0,fortified=false,level=0}); s.nextUnit += 1; added += 1 end
    end
    apply(s,1,{kind="EndTurn"})
    local disbands=eventsOf(Game.snapshot(s,1),"Disband")
    assert(#disbands>0)
    for _, e in disbands do assert(e.ownerId==1 and e.cause=="Upkeep" and e.unitKind=="Warrior" and e.byOwnerId==nil) end
    assert(Save.valid(Game.serialize(s)))
end

-- 2. Combat previews match applied results exactly for units; city results lie in the range.
do
    local base=founded(41,8); apply(base,1,{kind="DeclareWar",targetId=2})
    base.players[1].technologies=table.clone(Rules.technologyOrder); base.players[2].technologies=table.clone(Rules.technologyOrder)
    local baseSave=Game.serialize(base)
    local attackers={"Warrior","Scout","Swordsman","Knight","Rifleman","Archer","Catapult"}
    local defenders={"Warrior","Pikeman","Worker","Musketman","Scout"}
    local cases,kills,deaths=0,0,0
    for ai, attackerKind in attackers do
        for di, defenderKind in defenders do
            for variant=0,3 do
                local s: any=Game.restore(baseSave); assert(s)
                local attacker=firstUnit(s,1,"Warrior"); local defender=firstUnit(s,2,"Warrior")
                local from,to=arena(s,3,2,{[defender.id]=true}); clear(s,from); clear(s,to,({"Plains","Hills","Forest","Grassland"})[variant+1])
                attacker.kind=attackerKind; attacker.hp=math.max(1,Rules.units[attackerKind].hp-((ai*13+variant*29)%60)); attacker.level=variant%3; attacker.tileId=from; attacker.moves=2
                defender.kind=defenderKind; defender.hp=math.max(1,Rules.units[defenderKind].hp-((di*17+variant*31)%90)); defender.fortified=variant%2==1 and Rules.units[defenderKind].strength>0; defender.tileId=to
                local before=Game.serialize(s)
                local preview=Game.previewAttack(s,1,attacker.id,to)
                assert(preview and equal(before,Game.serialize(s)),"preview must not mutate state")
                local listed: any=nil
                for _, p in Game.snapshot(s,1).attackPreviews[tostring(attacker.id)] do if p.tileId==to then listed=p end end
                assert(listed and equal(listed,preview),"snapshot preview must match the query")
                assert(preview.exact and preview.target=="Unit" and not preview.hiddenDefense and preview.dealt==preview.dealtMin and preview.received==preview.receivedMax)
                local attackerHp,defenderHp,defenderId=attacker.hp,defender.hp,defender.id
                local ranged=Rules.units[attackerKind].range>1
                apply(s,1,{kind=if ranged then "RangedAttack" else "MoveUnit",unitId=attacker.id,tileId=to})
                local stillAttacker=nil; for _, u in s.units do if u.id==attacker.id then stillAttacker=u end end
                local stillDefender=nil; for _, u in s.units do if u.id==defenderId then stillDefender=u end end
                local attack: any=nil; for _, e in s.events do if e.kind=="Attack" then attack=e end end
                assert(attack and attack.unitId==attacker.id and attack.amount==preview.dealt,"dealt damage differs from preview")
                if stillAttacker then assert(attackerHp-stillAttacker.hp==preview.received and preview.attackerDefeated=="No")
                else assert(preview.attackerDefeated=="Yes" and attackerHp-preview.received<=0) end
                assert((stillDefender==nil)==(preview.defenderDefeated=="Yes"),"defender outcome differs from preview")
                if stillDefender then assert(stillDefender.hp==defenderHp-preview.dealt) else kills += 1 end
                if not stillAttacker then deaths += 1 end
                cases += 1
            end
        end
    end
    assert(cases==#attackers*#defenders*4 and kills>0 and kills<cases and deaths>0,"fixtures must cover kills, survivals and attacker deaths")
    -- Cities: hidden Walls widen the range, the preview never depends on hidden buildings,
    -- and the applied result falls inside the range.
    for _, walls in {false,true} do
        for hp=1,150,37 do
            local s: any=Game.restore(baseSave); assert(s)
            local city=firstCity(s,2); local graph=graphOf(s); local attacker=firstUnit(s,1,"Warrior")
            local occupied={}; for _, u in s.units do occupied[u.tileId]=true end
            for _, id in graph.neighbors[city.tileId] do if not occupied[id] then attacker.tileId=id; clear(s,id); break end end
            attacker.moves=2; attacker.kind="Swordsman"; city.hp=hp; city.buildings=if walls then {"Walls"} else {}
            local preview=Game.previewAttack(s,1,attacker.id,city.tileId); assert(preview)
            local other: any=Game.restore(Game.serialize(s)); assert(other); firstCity(other,2).buildings=if walls then {} else {"Walls"}
            assert(equal(preview,Game.previewAttack(other,1,attacker.id,city.tileId)),"preview must not reveal hidden buildings")
            assert(preview.target=="City" and preview.hiddenDefense and not preview.exact and preview.dealt==nil and preview.dealtMin<preview.dealtMax)
            local attackerHp=attacker.hp
            apply(s,1,{kind="MoveUnit",unitId=attacker.id,tileId=city.tileId})
            local dealt=hp-(if city.ownerId==1 then 0 else city.hp)
            if city.ownerId==2 then assert(dealt>=preview.dealtMin and dealt<=preview.dealtMax) end
            assert(attackerHp-attacker.hp>=preview.receivedMin and attackerHp-attacker.hp<=preview.receivedMax)
            assert(if city.ownerId==1 then preview.captures~="No" else preview.captures~="Yes")
        end
    end
    -- Hidden, peaceful or foreign queries return nothing and reveal nothing.
    local s: any=Game.restore(baseSave); assert(s)
    local attacker=firstUnit(s,1,"Warrior"); local defender=firstUnit(s,2,"Warrior")
    local from,to=arena(s,3,2,{[defender.id]=true}); clear(s,from); clear(s,to); attacker.tileId=from; attacker.moves=2
    local graph=graphOf(s); local hiddenTile: number?=nil
    for _, tile in s.tiles do
        local far=Rules.terrains[tile.terrain].passable
        for _, u in s.units do if u.ownerId==1 and WorldMap.distance(graph,tile.id,u.tileId)<=2 then far=false end; if u.tileId==tile.id then far=false end end
        for _, c in s.cities do if WorldMap.distance(graph,tile.id,c.tileId)<=2 then far=false end end
        if far then hiddenTile=tile.id; break end
    end
    assert(hiddenTile); defender.tileId=hiddenTile
    local hidden,message=Game.previewAttack(s,1,attacker.id,hiddenTile)
    local empty,emptyMessage=Game.previewAttack(s,1,attacker.id,to)
    assert(hidden==nil and empty==nil and message==emptyMessage,"hidden targets must be indistinguishable from empty tiles")
    assert(Game.previewAttack(s,2,attacker.id,to)==nil and Game.previewAttack(s,1,attacker.id,0/0)==nil and Game.previewAttack(s,3,attacker.id,to)==nil)
    defender.tileId=to; assert(Game.previewAttack(s,1,attacker.id,to))
    local peace: any=founded(41,8); local pa=firstUnit(peace,1,"Warrior"); local pd=firstUnit(peace,2,"Warrior")
    local pf,pt=arena(peace,3,2,{[pd.id]=true}); clear(peace,pf); clear(peace,pt); pa.tileId=pf; pa.moves=2; pd.tileId=pt
    assert(Game.previewAttack(peace,1,pa.id,pt)==nil and #Game.snapshot(peace,1).attackPreviews[tostring(pa.id)]==0)
    -- Previews are only published to the actor that can act.
    apply(s,1,{kind="EndTurn"})
    for _, list in Game.snapshot(s,1).attackPreviews do assert(#list==0) end
end

-- 3. Scores stay private during play, are revealed at Finished; coarse progress is public.
do
    local s: any=Game.new(51,{humanPlayers=2,maxTurns=20})
    apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id}); apply(s,1,{kind="EndTurn"})
    apply(s,2,{kind="FoundCity",unitId=firstUnit(s,2,"Settler").id}); apply(s,2,{kind="EndTurn"})
    s.players[2].technologies={"Agriculture","Mining","Archery","BronzeWorking","Writing"}; s.players[2].policies={"Tradition"}
    local playing=Game.snapshot(s,1)
    assert(playing.scores[2]==0 and playing.statistics[2].technologies==0 and playing.scores[1]>0)
    assert(equal(playing.progress[2],{cities=1,policies=1,era=2}) and equal(playing.progress[1],{cities=1,policies=0,era=1}))
    assert(equal(Game.snapshot(s,2).progress,playing.progress))
    while s.phase=="Playing" do apply(s,1,{kind="EndTurn"}); if s.phase=="Playing" then apply(s,2,{kind="EndTurn"}) end end
    assert(s.victoryType=="Score")
    local one,two=Game.snapshot(s,1),Game.snapshot(s,2)
    assert(equal(one.scores,two.scores) and equal(one.statistics,two.statistics) and one.scores[2]>0 and one.statistics[2].technologies==5)
    assert(one.scores[s.winner]>=one.scores[3-s.winner])
end

-- 4. Culture race: escalating policy costs by default, configurable threshold, legacy saves.
do
    assert(Game.new(1).cultureVictoryPolicies==6 and Game.new(1).policyCostIncrease==50)
    for _, bad in {{cultureVictoryPolicies=0},{cultureVictoryPolicies=7},{cultureVictoryPolicies=2.5},{policyCostIncrease=-1},{policyCostIncrease=401}} do
        assert(not pcall(function() return Game.new(1,bad :: any) end),"invalid culture option must be rejected")
    end
    local s=founded(61); s.players[1].culture=1000
    local spent=0; local expected={20,37,60,100,165,227}
    for index, id in Rules.policyOrder do
        local view=Game.snapshot(s,1); local listed: any=nil
        for _, policy in view.availablePolicies do if policy.id==id then listed=policy end end
        assert(listed and listed.cost==expected[index],"policy cost must escalate with each adoption")
        local before=s.players[1].culture; apply(s,1,{kind="AdoptPolicy",policy=id}); spent += before-s.players[1].culture
    end
    assert(spent==609 and s.victoryType=="Culture" and s.winner==1)
    -- Escalation applies to the next adoption, not to the original order.
    local order=founded(62); order.players[1].culture=60
    apply(order,1,{kind="AdoptPolicy",policy="Honor"}); assert(order.players[1].culture==30)
    local view=Game.snapshot(order,1); for _, policy in view.availablePolicies do assert(policy.cost==math.floor(Rules.policies[policy.id].cost*1.5)) end
    local result=Game.apply(order,1,{kind="AdoptPolicy",policy="Liberty"} :: any); assert(not result.ok and order.players[1].culture==30)
    -- A shorter preset threshold and the flat-cost option.
    local quick: any=Game.new(63,{humanPlayers=2,cultureVictoryPolicies=4,policyCostIncrease=0})
    apply(quick,1,{kind="FoundCity",unitId=firstUnit(quick,1,"Settler").id}); quick.players[1].culture=1000
    assert(Game.snapshot(quick,1).cultureVictoryPolicies==4 and Game.snapshot(quick,1).objectives[4]=="Adopt 4 policies for culture victory.")
    for index=1,3 do apply(quick,1,{kind="AdoptPolicy",policy=Rules.policyOrder[index]}) end
    assert(quick.phase=="Playing" and quick.players[1].culture==1000-20-25-30)
    apply(quick,1,{kind="AdoptPolicy",policy="Commerce"}); assert(quick.victoryType=="Culture" and quick.winner==1)
    assert(Save.valid(Game.serialize(quick)))
    -- Saves from earlier library versions lack both fields: flat costs and six policies.
    local legacy=Game.serialize(founded(64)); legacy.state.cultureVictoryPolicies=nil; legacy.state.policyCostIncrease=nil
    assert(Save.valid(legacy)); local old: any=Game.restore(legacy); assert(old)
    old.players[1].culture=235
    for _, id in Rules.policyOrder do apply(old,1,{kind="AdoptPolicy",policy=id}) end
    assert(old.players[1].culture==0 and old.victoryType=="Culture")
    local legacyView=Game.snapshot(assert(Game.restore(legacy)),1)
    assert(legacyView.cultureVictoryPolicies==6 and legacyView.policyCostIncrease==0)
    for _, field in {{"cultureVictoryPolicies",0},{"cultureVictoryPolicies",7},{"policyCostIncrease",-5},{"policyCostIncrease",1.5}} do
        local bad=Game.serialize(founded(65)); bad.state[field[1]]=field[2]; assert(not Save.valid(bad),"culture option "..field[1].." must be validated")
    end
    -- The built-in AI pays the escalating cost too.
    local solo: any=Game.new(66,{maxTurns=40})
    apply(solo,1,{kind="FoundCity",unitId=firstUnit(solo,1,"Settler").id})
    solo.players[2].policies={"Tradition"}; solo.players[2].culture=36
    apply(solo,1,{kind="EndTurn"})
    assert(#solo.players[2].policies==1,"Liberty costs 37 after one adoption, not its flat 25")
    solo.players[2].culture=37; solo.players[1].culture=0
    apply(solo,1,{kind="EndTurn"})
    assert(#solo.players[2].policies==2 and solo.players[2].policies[2]=="Liberty")
end
print("base events: loser-owned UnitLost/CityLost/Eliminated/Disband, exact unit previews and fog-safe city ranges, final score reveal with coarse progress, escalating culture costs and legacy saves passed")
