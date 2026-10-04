--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original G14b sentry command, fog, private projection and save regressions. No upstream parity claim.
local Game=require("../../src/simulation/BaseGame")
local Save=require("../../src/simulation/BaseSave")
local Map=require("../../src/simulation/WorldMap")
local Rules=require("../../src/simulation/BaseRules")
local restores: {(any)->(any?,string?)}={Game.restore,Save.restore}
local I=(Game :: any)._internal
local args={...}; if args[1]=="internal" then assert(I,"run node tests/sentry.mjs") end
local function copy(value: any): any
    if type(value)~="table" then return value end
    local result={}; for key,child in value do result[key]=copy(child) end; return result
end
local function equal(a: any,b: any): boolean
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for key,value in a do if not equal(value,b[key]) then return false end end
    for key in b do if a[key]==nil then return false end end; return true
end
local function apply(s: any,actor: number,cmd: any)
    local result=Game.apply(s,actor,cmd); assert(result.ok,result.message)
end
local function reject(s: any,actor: number,cmd: any,expected: string?)
    local before=Game.serialize(s); local result=Game.apply(s,actor,cmd)
    assert(not result.ok,"command must be refused")
    if expected then assert(result.message==expected,result.message) end
    assert(equal(before,Game.serialize(s)),"rejection mutated state")
end
local function fixture(barbarians: boolean?): (any,any)
    local s: any=Game.new(7919,{humanPlayers=2,radius=8,barbarians=barbarians==true})
    local map=Map.fromTiles(s.tiles,s.radius)
    for _, t in s.tiles do t.terrain="Plains"; t.resource=nil; t.feature=nil; t.river=nil; t.ownerId=nil; t.improvement=nil; t.road=nil end
    local function unit(id: number,owner: number,kind: string,x: number,y: number): any
        return {id=id,ownerId=owner,kind=kind,tileId=assert(Map.tileId(map,x,y)),hp=Rules.units[kind].hp,moves=Rules.units[kind].moves,fortified=false,level=0}
    end
    s.units={unit(1,1,"Settler",-7,0),unit(2,1,"Warrior",0,0),unit(3,1,"Worker",-4,0),
        unit(4,2,"Settler",7,0),unit(5,2,"Warrior",6,0),unit(6,2,"Worker",7,-1)}
    s.cities={}; s.nextUnit=7; s.events={}; s.nextEvent=1; s.diplomacy.met=true
    s.players[1].technologies={"Agriculture"}; s.players[2].technologies={"Agriculture"}
    return s,map
end
local function tile(map: any,x: number,y: number?): number return assert(Map.tileId(map,x,y or 0)) end
local function unitView(s: any,actor: number,id: number): any
    for _, u in Game.snapshot(s,actor).units do if u.id==id then return u end end; error("unit not visible")
end
local function wakes(s: any,actor: number): {any}
    local result={}; for _, e in Game.snapshot(s,actor).events do if e.kind=="UnitWoke" then table.insert(result,e) end end; return result
end
local function sentry(s: any,actor: number,id: number) apply(s,actor,{kind="SentryUnit",unitId=id}) end
-- Own military/civilian orders preserve movement, can be set at zero moves and refuse busy/Settler/duplicate orders.
do
    local s=fixture(); local revision=s.revision
    sentry(s,1,2); assert(s.units[2].sentry==true and s.units[2].moves==2 and s.revision==revision+1)
    reject(s,1,{kind="SentryUnit",unitId=2},"This unit is already on sentry.")
    s.units[3].moves=0; sentry(s,1,3); assert(s.units[3].sentry==true and s.units[3].moves==0)
    reject(s,1,{kind="SentryUnit",unitId=1},"A settler cannot sentry.")
    reject(s,1,{kind="SentryUnit",unitId=5},"Select your unit.")
    reject(s,2,{kind="SentryUnit",unitId=5},"Wait for your civilization's turn.")
    reject(s,1,{kind="SentryUnit",unitId=2,extra=1},"Invalid command fields.")
    reject(s,1,{kind="SentryUnit"},"Missing command field.")
    s.units[3].sentry=nil; s.tiles[s.units[3].tileId].ownerId=1; s.units[3].work={improvement="Farm",remaining=2}
    reject(s,1,{kind="SentryUnit",unitId=3},"A unit building an improvement is already busy.")
end
-- Every accepted unit command clears sentry; rejected commands and unrelated commands preserve it.
for _, kindName in {"MoveUnit","FortifyUnit","BuildImprovement","UpgradeUnit","PromoteUnit","RangedAttack","MeleeAttack"} do
    -- `any` keeps luau-analyze from refining the literal union through every branch below (too complex to typecheck).
    local kind: any=kindName
    local s,map=fixture(); local u=s.units[if kind=="BuildImprovement" then 3 else 2]
    local cmd: any={kind=kind,unitId=u.id}
    if kind=="MoveUnit" then cmd.tileId=tile(map,1)
    elseif kind=="BuildImprovement" then s.tiles[u.tileId].ownerId=1; cmd.improvement="Farm"
    elseif kind=="UpgradeUnit" then
        s.players[1].technologies=table.clone(Rules.technologyOrder); s.players[1].gold=1000
        local t=s.tiles[s.units[3].tileId]; t.ownerId=1; t.resource="Iron"; t.improvement="Mine"
    elseif kind=="PromoteUnit" then u.xp=Rules.experienceThresholds[1]; cmd.promotion="Shock1"
    elseif kind=="RangedAttack" then
        u.kind="Archer"; u.hp=Rules.units.Archer.hp; s.players[1].technologies=table.clone(Rules.technologyOrder); u.moves=Rules.units.Archer.moves; s.units[5].tileId=tile(map,2); s.diplomacy.status="War"; cmd.tileId=tile(map,2)
    elseif kind=="MeleeAttack" then cmd.kind="MoveUnit"; cmd.tileId=tile(map,1); s.units[5].tileId=cmd.tileId; s.diplomacy.status="War" end
    sentry(s,1,u.id)
    reject(s,1,{kind="MoveUnit",unitId=u.id,tileId=u.tileId})
    assert(u.sentry==true)
    apply(s,1,{kind=if s.diplomacy.status=="War" then "OfferPeace" else "DeclareWar",targetId=2}); assert(u.sentry==true)
    apply(s,1,cmd); assert(u.sentry==nil,"accepted "..kind.." failed to clear sentry")
end
-- Own-only, detached view even when the rival sees the sleeping unit.
do
    local s,map=fixture(); s.units[5].tileId=tile(map,1); sentry(s,1,2)
    assert(unitView(s,1,2).sentry==true and unitView(s,2,2).sentry==nil)
    local v=unitView(s,1,2); v.sentry=false; assert(s.units[2].sentry==true)
end
-- Start-of-turn check: visible barbarian at exactly two tiles, owner 2, no intervening barbarian phase.
do
    local s,map=fixture(true); s.activePlayerId=2; sentry(s,2,5)
    table.insert(s.units,{id=7,ownerId=0,kind="Warrior",tileId=tile(map,4),hp=100,moves=2,fortified=false,level=0}); s.nextUnit=8
    s.activePlayerId=1; apply(s,1,{kind="EndTurn"})
    assert(s.units[5].sentry==nil and #wakes(s,2)==1,"visible barbarian must wake at turn start")
    local e=wakes(s,2)[1]; assert(e.ownerId==2 and e.unitId==5 and e.tileId==s.units[5].tileId and e.public~=true)
    assert(e.message=="Your Warrior sees an enemy nearby.")
    apply(s,2,{kind="EndTurn"}); apply(s,1,{kind="EndTurn"}); assert(#wakes(s,2)==1,"wake event duplicated")
end
-- Peaceful rivals never wake a unit, during their visible move or at the next owner turn.
do
    local s,map=fixture(); sentry(s,1,2); s.units[5].tileId=tile(map,3)
    apply(s,1,{kind="EndTurn"}); apply(s,2,{kind="MoveUnit",unitId=5,tileId=tile(map,2)})
    assert(s.units[2].sentry==true and #wakes(s,1)==0)
    apply(s,2,{kind="EndTurn"}); assert(s.units[2].sentry==true and #wakes(s,1)==0)
end
-- Rival movement wakes immediately, before EndTurn, once each; rival sees the tile but never the private event.
do
    local s,map=fixture(); s.diplomacy.status="War"; sentry(s,1,2); s.units[5].tileId=tile(map,3)
    apply(s,1,{kind="EndTurn"}); apply(s,2,{kind="MoveUnit",unitId=5,tileId=tile(map,2)})
    assert(s.activePlayerId==2 and s.units[2].sentry==nil and #wakes(s,1)==1)
    assert(#wakes(s,2)==0 and unitView(s,2,2).sentry==nil,"waking leaked to rival")
    apply(s,2,{kind="EndTurn"}); assert(#wakes(s,1)==1)
end
-- A civilian wakes too; multiple sentries each receive exactly one event from one visible attack.
do
    local s,map=fixture(); s.diplomacy.status="War"; s.units[3].tileId=tile(map,1,1)
    sentry(s,1,2); sentry(s,1,3)
    s.units[5].kind="Archer"; s.units[5].tileId=tile(map,2)
    apply(s,1,{kind="EndTurn"}); apply(s,2,{kind="RangedAttack",unitId=5,tileId=s.units[2].tileId})
    assert(s.units[2].sentry==nil and s.units[3].sentry==nil and #wakes(s,1)==2 and #wakes(s,2)==0)
end
-- At war, a stationary visible hostile also wakes at the next turn start.
do
    local s,map=fixture(); s.diplomacy.status="War"; s.units[5].tileId=tile(map,2)
    sentry(s,1,2); apply(s,1,{kind="EndTurn"}); assert(s.units[2].sentry==true)
    apply(s,2,{kind="EndTurn"}); assert(s.units[2].sentry==nil and #wakes(s,1)==1)
end
-- Equal-snapshot fog pair: historical exploration does not reveal a hidden hostile or its hidden move.
do
    local a,map=fixture(); a.diplomacy.status="War"; sentry(a,1,2); a.units[5].tileId=tile(map,4)
    apply(a,1,{kind="EndTurn"})
    a.players[1].explored={}; for id=1,#a.tiles do table.insert(a.players[1].explored,id) end
    local b=copy(a); b.units[5].tileId=tile(map,5)
    assert(equal(Game.snapshot(a,1),Game.snapshot(b,1)),"fog pair differs before move")
    apply(a,2,{kind="MoveUnit",unitId=5,tileId=tile(map,5)})
    apply(b,2,{kind="MoveUnit",unitId=5,tileId=tile(map,4)})
    assert(a.units[2].sentry==true and b.units[2].sentry==true and #wakes(a,1)==0 and #wakes(b,1)==0)
    assert(equal(Game.snapshot(a,1),Game.snapshot(b,1)),"hidden move leaked")
    apply(a,2,{kind="EndTurn"}); apply(b,2,{kind="EndTurn"})
    assert(a.units[2].sentry==true and b.units[2].sentry==true)
    assert(equal(Game.snapshot(a,1),Game.snapshot(b,1)),"hidden enemy changed owner turn")
end
-- Optional boolean round-trips on both shapes through both restore APIs, with no schema version bump.
-- Sphere waking uses graph distance; a visible hostile at distance three does not wake until it moves to two.
do
    local s: any=Game.new(7919,{humanPlayers=2,mapShape="Sphere",frequency=4,barbarians=false})
    local map=Map.fromSphereTiles(s.tiles,s.frequency)
    for _, t in s.tiles do t.terrain="Plains"; t.resource=nil; t.feature=nil; t.river=nil; t.ownerId=nil end
    local sleeper: any=nil; local enemy: any=nil; local far={}
    for id=1,#s.tiles do if Map.distance(map,1,id)>5 then table.insert(far,id) end end
    local index=1
    for _, u in s.units do
        if u.kind=="Warrior" and u.ownerId==1 then sleeper=u; u.tileId=1
        elseif u.kind=="Warrior" and u.ownerId==2 then enemy=u
        else u.tileId=far[index]; index+=1 end
    end
    local from: number?=nil; local target: number?=nil
    for _, id in Map.range(map,1,3) do if Map.distance(map,1,id)==3 then
        for _, neighbor in map.neighbors[id] do if Map.distance(map,1,neighbor)==2 then from=id; target=neighbor; break end end
        if target then break end
    end end
    assert(from and target); enemy.tileId=from; s.diplomacy.status="War"; s.diplomacy.met=true
    -- Territory sight makes distance-three visible without changing the wake radius.
    s.tiles[from].ownerId=1
    sentry(s,1,sleeper.id); s.activePlayerId=2; apply(s,2,{kind="EndTurn"})
    assert(sleeper.sentry==true and #wakes(s,1)==0,"visible distance-three enemy woke sentry")
    apply(s,1,{kind="EndTurn"}); apply(s,2,{kind="MoveUnit",unitId=enemy.id,tileId=target})
    assert(sleeper.sentry==nil and #wakes(s,1)==1,"sphere graph move failed to wake")
end
-- Optional boolean round-trips on both shapes through both restore APIs, with no schema version bump.
for _, shape in {"Hex","Sphere"} do
    local s: any=Game.new(7919,{humanPlayers=2,radius=if shape=="Hex" then 8 else nil,mapShape=shape,frequency=if shape=="Sphere" then 4 else nil,barbarians=false})
    local military: any=nil; local worker: any=nil; local settler: any=nil
    for _, u in s.units do if u.ownerId==1 then
        if u.kind=="Warrior" then military=u elseif u.kind=="Worker" then worker=u else settler=u end
    end end
    sentry(s,1,military.id); worker.sentry=false
    local saved=Game.serialize(s); assert(saved.version==(if shape=="Hex" then 1 else 2) and Save.valid(saved))
    for _, restore in restores do
        local loaded,err=restore(saved); assert(loaded and err==nil)
        assert(equal(Game.serialize(loaded),saved),"sentry round trip changed save")
    end
    local function invalid(change: (any)->())
        local bad=copy(saved); change(bad.state)
        assert(not Save.valid(bad),"corrupt sentry save accepted")
        for _, restore in restores do local loaded,err=restore(bad); assert(loaded==nil and err~=nil) end
    end
    invalid(function(st) for _, u in st.units do if u.id==military.id then u.sentry="true" end end end)
    invalid(function(st) for _, u in st.units do if u.id==settler.id then u.sentry=true end end end)
    invalid(function(st) for _, u in st.units do if u.id==worker.id then u.sentry=true; u.work={improvement="Farm",remaining=1} end end end)
    -- Older saves omit the optional field and stay readable.
    for _, u in saved.state.units do u.sentry=nil end
    assert(Save.valid(saved)); local loaded=Game.restore(saved); assert(loaded)
end
-- Waking event round-trip and private shape validation, including a visible tile in the rival snapshot.
do
    local s,map=fixture(true); s.diplomacy.status="War"; sentry(s,1,2); s.units[5].tileId=tile(map,3)
    apply(s,1,{kind="EndTurn"}); apply(s,2,{kind="MoveUnit",unitId=5,tileId=tile(map,2)})
    local saved=Game.serialize(s); assert(Save.valid(saved))
    for _, restore in restores do
        local loaded,err=restore(saved); assert(loaded and err==nil and #wakes(loaded,1)==1 and #wakes(loaded,2)==0)
    end
    local function invalid(change: (any)->())
        local bad=copy(saved); for _, e in bad.state.events do if e.kind=="UnitWoke" then change(e) end end
        assert(not Save.valid(bad),"invalid waking event accepted")
    end
    invalid(function(e) e.public=true end); invalid(function(e) e.ownerId=nil end)
    invalid(function(e) e.tileId=nil end); invalid(function(e) e.unitId=nil end)
    table.insert(saved.state.units,{id=saved.state.nextUnit,ownerId=0,kind="Warrior",tileId=tile(map,4),hp=100,moves=2,fortified=false,level=0,sentry=true})
    saved.state.nextUnit+=1; assert(not Save.valid(saved),"barbarian sentry accepted")
end
-- Individual barbarian movement must wake before any subsequent attack, including the second civilization's seat.
if I then
    for owner=1,2 do
        local s,map=fixture(true); s.activePlayerId=owner
        local u=s.units[if owner==1 then 2 else 5]; u.tileId=tile(map,0)
        -- Keep the other civilization out of this barbarian's target selection.
        s.units[if owner==1 then 5 else 2].tileId=tile(map,if owner==1 then 6 else -6)
        sentry(s,owner,u.id)
        local enemy={id=7,ownerId=0,kind="Warrior",tileId=tile(map,3),hp=100,moves=2,fortified=false,level=0}
        table.insert(s.units,enemy); s.nextUnit=8
        I.barbarianAct(s,enemy)
        assert(enemy.tileId~=tile(map,3) and Map.distance(map,u.tileId,enemy.tileId)<=2)
        local e=wakes(s,owner); assert(u.sentry==nil and #e==1 and #wakes(s,3-owner)==0,"barbarian move failed to wake")
        for _, attack in s.events do if attack.kind=="Attack" then assert(e[1].id<attack.id,"waking was delayed until barbarian attack") end end
    end
    do
        local s,map=fixture(true); sentry(s,1,2)
        local enemy={id=7,ownerId=0,kind="Archer",tileId=tile(map,2),hp=Rules.units.Archer.hp,moves=2,fortified=false,level=0}
        table.insert(s.units,enemy); s.nextUnit=8
        I.barbarianAct(s,enemy); assert(s.units[2].sentry==nil and #wakes(s,1)==1 and #wakes(s,2)==0,"barbarian attack failed to wake")
    end
end
print("base-sentry: command, waking, fog, private view/events and saves passed")
