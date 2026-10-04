--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original contact, telegraphed war, fog and save regression fixtures. No upstream parity claim.
local Game=require("../../src/simulation/BaseGame")
local Save=require("../../src/simulation/BaseSave")
local Map=require("../../src/simulation/WorldMap")
local args={...}
local I=(Game :: any)._internal
if args[1]=="internal" then assert(I,"run node tests/war-warning.mjs") end
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
local function apply(s: any,actor: number,command: any)
    local result=Game.apply(s,actor,command); assert(result.ok,result.message)
end
local function events(s: any,actor: number,kind: string): {any}
    local result={}; for _, e in Game.snapshot(s,actor).events do if e.kind==kind then table.insert(result,e) end end; return result
end
local function fogSafe(e: any)
    for _, key in {"tileId","unitId","cityId","unitKind","wonder","cause","byOwnerId","amount"} do assert(e[key]==nil,"announcement leaked "..key) end
end
local function fresh(difficulty: string?, met: boolean?): any
    local s: any=Game.new(7919,{radius=10,difficulty=difficulty or "Normal",maxTurns=120})
    -- Two remote capitals, no mobile units: sight cannot accidentally meet the rival in the no-contact fixture.
    local settler: any=nil; for _, u in s.units do if u.ownerId==1 and u.kind=="Settler" then settler=u end end
    apply(s,1,{kind="FoundCity",unitId=settler.id})
    s.units={}; for _, c in s.cities do c.queue="" end
    s.diplomacy.met=met==true; s.events={}; s.nextEvent=1
    s.turn=15
    return s
end
local function aiStep(s: any,owner: number)
    if I then I.ai(s,owner) else assert(owner==2); apply(s,1,{kind="EndTurn"}) end
end
-- Never met: condition turns alone cannot create either a plan, warning, or war.
for _, turn in {15,20,25} do
    local s=fresh(); s.turn=turn
    aiStep(s,2)
    assert(s.diplomacy.met==false and s.diplomacy.status=="Peace" and s.diplomacy.warPlan==nil)
    assert(#events(s,1,"WarWarning")==0 and #events(s,1,"War")==0)
end
-- Contact does not bypass the original cadence, minimum round or treaty.
for _, case in {{turn=10,untilRound=0},{turn=16,untilRound=0},{turn=15,untilRound=16}} do
    local s=fresh(nil,true); s.turn=case.turn; s.diplomacy.peaceUntil=case.untilRound
    aiStep(s,2); assert(s.diplomacy.status=="Peace" and s.diplomacy.warPlan==nil)
end
for _, case in {{difficulty="Easy",lead=3},{difficulty="Normal",lead=2},{difficulty="Hard",lead=1}} do
    local s=fresh(case.difficulty,true)
    aiStep(s,2)
    assert(s.diplomacy.status=="Peace" and s.diplomacy.warPlan.by==2 and s.diplomacy.warPlan.at==15+case.lead)
    local warning=events(s,1,"WarWarning"); assert(#warning==1 and warning[1].ownerId==1 and warning[1].public~=true)
    assert(string.find(warning[1].message,tostring(case.lead).." rounds",1,true)~=nil); fogSafe(warning[1])
    assert(#events(s,2,"WarWarning")==0)
    for round=15,15+case.lead do
        s.turn=round
        local target=Game.snapshot(s,1).diplomacy; local planner=Game.snapshot(s,2).diplomacy
        assert(target.met and planner.met and target.warWarning and target.warWarning.roundsLeft==15+case.lead-round)
        assert(planner.warWarning==nil and (target :: any).warPlan==nil and (planner :: any).warPlan==nil)
        target.warWarning.roundsLeft=99; local again=Game.snapshot(s,1).diplomacy.warWarning; assert(again and again.roundsLeft~=99,"detached countdown")
        if round>15 then aiStep(s,2) end
        assert(s.diplomacy.status==(if round==15+case.lead then "War" else "Peace"),"incorrect declaration round")
    end
    assert(s.diplomacy.warPlan==nil and Game.snapshot(s,1).diplomacy.warWarning==nil and #events(s,1,"War")==1)
end
-- Human declaration cancels immediately; a new treaty cancels with no warning/cancellation event.
do
    local s=fresh(nil,true); aiStep(s,2)
    apply(s,1,{kind="DeclareWar",targetId=2}); assert(s.diplomacy.warPlan==nil)
    apply(s,1,{kind="OfferPeace",targetId=2}); s.turn=16; aiStep(s,2)
    assert(s.diplomacy.status=="Peace" and s.diplomacy.peaceUntil==24 and s.diplomacy.warPlan==nil)
    s.turn=17; aiStep(s,2); assert(s.diplomacy.status=="Peace" and #events(s,1,"WarWarning")==1)
    -- AcceptPeace also clears stale plans, even if a caller has changed the status directly.
    s=fresh(nil,true); aiStep(s,2); s.diplomacy.status="War"; s.diplomacy.peaceOfferBy=2
    apply(s,1,{kind="AcceptPeace",targetId=2}); assert(s.diplomacy.warPlan==nil and s.diplomacy.status=="Peace")
    for _, untilRound in {1,30} do
        s=fresh(nil,true); aiStep(s,2); s.diplomacy.peaceUntil=untilRound; s.turn=17
        assert(Game.snapshot(s,1).diplomacy.warWarning==nil)
        aiStep(s,2); assert(s.diplomacy.warPlan==nil and s.diplomacy.status=="Peace" and #events(s,1,"WarWarning")==1)
    end
end
-- Genuine unit/city sight establishes persistent bilateral contact, once, without a location.
local function contactFixture(shape: string): (any, any)
    local s: any=Game.new(7919,{humanPlayers=2,radius=if shape=="Hex" then 10 else nil,mapShape=shape,frequency=if shape=="Sphere" then 6 else nil})
    local graph=if shape=="Sphere" then Map.fromSphereTiles(s.tiles,s.frequency) else Map.fromTiles(s.tiles,s.radius)
    s.events={}; s.nextEvent=1; s.diplomacy.met=false; s.cities={}; s.units={}
    for _, tile in s.tiles do tile.terrain="Plains"; tile.ownerId=nil; tile.resource=nil; tile.feature=nil; tile.river=nil end
    local center=1; local near=graph.neighbors[center][1]
    local far: number?=nil; for id=1,#s.tiles do if Map.distance(graph,center,id)>6 then far=id; break end end; assert(far)
    s.units={{id=1,ownerId=1,kind="Settler",tileId=center,hp=50,moves=2,fortified=false,level=0},{id=2,ownerId=2,kind="Settler",tileId=far,hp=50,moves=2,fortified=false,level=0}}
    s.nextUnit=3; s.nextCity=1
    return s,{center=center,near=near,far=far,graph=graph}
end
for _, shape in {"Hex","Sphere"} do
    for _, owner in {1,2} do
        for _, kind in {"unit","city"} do
            local s,loc=contactFixture(shape)
            -- Swap entity ownership so contact is independent of which civilization sees the rival first.
            if owner==2 then s.units[1].ownerId=2; s.units[2].ownerId=1 end
            if kind=="unit" then s.units[2].tileId=loc.near
            else
                s.cities={{id=1,ownerId=3-owner,originalOwnerId=3-owner,capital=true,tileId=loc.near,name="Rival",population=1,food=0,production=0,queue="",hp=150,buildings={},focus="Balanced"}}; s.nextCity=2
            end
            -- A valid command refreshes both players' actual vision.
            apply(s,1,{kind="Research",technology="Agriculture"})
            assert(s.diplomacy.met==true)
            for actor=1,2 do local list=events(s,actor,"Contact"); assert(#list==1 and list[1].public==true); fogSafe(list[1]); assert(Game.snapshot(s,actor).diplomacy.met) end
            s.units[2].tileId=loc.far; s.cities={}
            apply(s,1,{kind="EndTurn"})
            assert(s.diplomacy.met and #events(s,1,"Contact")==1,"contact reset or repeated")
        end
    end
end
-- Mid-plan round trips preserve declaration timing, views, events and the detached source save.
do
    local s=fresh("Easy",true); aiStep(s,2); s.turn=16
    local saved=Game.serialize(s)
    for _, restore in {Game.restore,Save.restore} do
        local resumed=restore(saved); assert(resumed and equal(resumed,s))
        for actor=1,2 do assert(equal(Game.snapshot(resumed,actor),Game.snapshot(s,actor))) end
        for round=16,18 do resumed.turn=round; aiStep(resumed,2); assert(resumed.diplomacy.status==(if round==18 then "War" else "Peace")) end
        assert(saved.state.diplomacy.warPlan.at==18 and saved.state.diplomacy.status=="Peace")
    end
end
-- Legacy saves migrate through BOTH APIs, using current visibility instead of explored terrain.
for _, shape in {"Hex","Sphere"} do
    for _, relation in {"unseen","seen","war"} do
        local s,loc=contactFixture(shape)
        if relation=="seen" then s.units[2].tileId=loc.near elseif relation=="war" then s.diplomacy.status="War" end
        s.diplomacy.met=nil
        for actor=1,2 do s.players[actor].explored={}; for id=1,#s.tiles do table.insert(s.players[actor].explored,id) end end
        local saved=Save.serialize(s)
        for _, restore in {Game.restore,Save.restore} do
            local resumed=restore(saved); assert(resumed and resumed.diplomacy.met==(relation~="unseen"))
            assert(#events(resumed,1,"Contact")==(if relation=="seen" then 1 else 0))
            assert(Save.valid(Save.serialize(resumed)) and saved.state.diplomacy.met==nil)
            local again=restore(Save.serialize(resumed)); assert(again and equal(again,resumed),"migration repeated")
        end
    end
end
-- Exact schema, bounded values and fog-safe announcement validation.
do
    local s=fresh(nil,true); aiStep(s,2); local saved=Game.serialize(s)
    local function corrupt(change: (any)->())
        local bad=copy(saved); change(bad.state); assert(not Save.valid(bad),"corrupt diplomacy accepted")
        assert(Game.restore(bad)==nil and Save.restore(bad)==nil)
    end
    corrupt(function(t) t.diplomacy.met="true" end)
    corrupt(function(t) t.diplomacy.met=false end)
    corrupt(function(t) t.diplomacy.warPlan.by=1 end)
    corrupt(function(t) t.diplomacy.warPlan.by=0 end)
    corrupt(function(t) t.diplomacy.warPlan.at=14 end)
    corrupt(function(t) t.diplomacy.warPlan.at=124 end)
    corrupt(function(t) t.diplomacy.warPlan.at=17.5 end)
    corrupt(function(t) t.diplomacy.warPlan.peaceUntil=nil end)
    corrupt(function(t) t.diplomacy.warWarning={roundsLeft=2} end)
    corrupt(function(t) t.events[1].public=true end)
    corrupt(function(t) t.events[1].ownerId=nil end)
    corrupt(function(t) t.events[1].tileId=1 end)
    corrupt(function(t) t.events[1].kind="Contact" end)
    -- A pending declaration may lie past the match limit: at turn 20 Easy plans for 23.
    s=fresh("Easy",true); s.maxTurns=20; s.turn=20; aiStep(s,2); assert(Save.valid(Game.serialize(s)))
end
-- Balance harness calls the same AI in either seat. One global plan, never replaced by its target AI.
if I then
    local results={}
    for owner=1,2 do
        local s=fresh(nil,true); s.players[1].human=false
        I.ai(s,owner); assert(s.diplomacy.warPlan.by==owner and s.diplomacy.warPlan.at==17)
        I.ai(s,3-owner); assert(s.diplomacy.warPlan.by==owner and #events(s,3-owner,"WarWarning")==1 and #events(s,owner,"WarWarning")==0)
        s.turn=16; I.ai(s,3-owner); I.ai(s,owner); assert(s.diplomacy.status=="Peace")
        s.turn=17; I.ai(s,3-owner); assert(s.diplomacy.status=="Peace"); I.ai(s,owner)
        assert(s.diplomacy.status=="War" and s.diplomacy.warPlan==nil)
        results[owner]={status=s.diplomacy.status,war=#events(s,owner,"War"),turn=s.turn}
    end
    assert(equal(results[1],results[2]),"AI seat-swap asymmetry")
end
print("war warning: contact, cadence, difficulty leads, target-only countdown, cancellation, save migration and validation passed"..(if I then "; both AI seats and two-AI ownership passed" else " (seat harness: node tests/war-warning.mjs)"))
