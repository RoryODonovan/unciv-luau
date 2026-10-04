--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original seat-symmetry and Draw trust-boundary regression fixtures.
local Game=require("../../src/simulation/BaseGame")
local Save=require("../../src/simulation/BaseSave")
local Canonical=require("../golden/canonical")

local function fixture(sphere: boolean?): any
    local s: any=Game.new(73,{humanPlayers=2,maxTurns=20,barbarians=false,mapShape=if sphere then "Sphere" else nil,frequency=if sphere then 2 else nil})
    -- No cities: the final economy cannot grow population or complete production/research.
    -- Both civilizations keep their settlers, so no elimination can preempt the score result.
    s.turn=s.maxTurns
    return s
end
local function workers(s: any, owner: number, count: number)
    local occupied={}; for _, u in s.units do occupied[u.tileId]=true end
    for _, tile in s.tiles do
        if occupied[tile.id] or tile.terrain=="Water" or tile.terrain=="Mountain" then continue end
        table.insert(s.units,{id=s.nextUnit,ownerId=owner,kind="Worker",tileId=tile.id,hp=50,moves=2,fortified=false,level=0})
        s.nextUnit+=1; count-=1
        if count==0 then return end
    end
    error("not enough fixture deployment space")
end
local function swapped(s: any): any
    local copy=Game.restore(Game.serialize(s)); assert(copy)
    copy.players[1],copy.players[2]=copy.players[2],copy.players[1]
    copy.players[1].id=1; copy.players[2].id=2
    for _, u in copy.units do u.ownerId=3-u.ownerId end
    return copy
end
local function complete(s: any)
    assert(Save.valid(Game.serialize(s)),"fixture must be a valid save")
    for owner=1,2 do
        local result=Game.apply(s,owner,{kind="EndTurn"}); assert(result.ok,result.message)
        if owner==1 then assert(s.phase=="Playing","limit is evaluated after both turns") end
    end
    assert(s.phase=="Finished" and s.turn==20)
end

-- Higher scores still win, even when the lower-scoring civilization knows more.
local unequal=fixture(); unequal.players[2].technologies={"Agriculture","Mining"}; workers(unequal,1,6)
local unequalSwap=swapped(unequal)
for _, s in {unequal,unequalSwap} do complete(s) end
assert(unequal.winner==1 and unequalSwap.winner==2 and unequal.victoryType=="Score" and unequalSwap.victoryType=="Score")
assert(Game.snapshot(unequal,1).scores[1]>Game.snapshot(unequal,1).scores[2])
assert(unequal.reason=="Score victory for civilization 1.")

-- Knowledge contributes five points each; five extra workers offset two knowledge entries.
-- Test technology-only and policy-led advantages, in both seats. The policy-led winner has fewer techs.
for _, policies in {false,true} do
    local tied=fixture()
    if policies then
        tied.players[1].technologies={"Agriculture","Mining","Archery"}
        tied.players[2].technologies={"Agriculture"}
        tied.players[2].policies={"Tradition","Liberty","Honor","Commerce"}
    else tied.players[2].technologies={"Agriculture","Mining"} end
    workers(tied,1,5)
    local mirrored=swapped(tied)
    for index,s in {tied,mirrored} do
        complete(s)
        local view=Game.snapshot(s,1)
        assert(view.scores[1]==view.scores[2],"fixture must reach an exact score tie")
        local winner=if index==1 then 2 else 1
        assert(s.winner==winner and s.victoryType=="Score","greater combined knowledge must win in either seat")
        assert(s.reason=="Score victory for civilization "..winner.." (tie broken by technologies and policies).")
        local outcome=s.events[#s.events]
        assert(outcome.kind=="Victory" and outcome.ownerId==winner and outcome.message==s.reason and outcome.public)
    end
end

local draw=fixture(); local drawSwap=swapped(draw)
local distributed=fixture()
distributed.players[1].technologies={"Agriculture"}; distributed.players[1].policies={"Tradition"}
distributed.players[2].technologies={"Agriculture","Mining"}
local draws: {any}={draw,drawSwap,distributed,swapped(distributed),fixture(true)}
for _, s in draws do
    complete(s)
    assert(s.winner==nil and s.victoryType=="Draw","fully equal positions must draw in either seat")
    assert(s.reason=="Draw: equal score, technologies and policies.")
    local before=Canonical.encode(Game.serialize(s))
    for actor=1,2 do
        local view=Game.snapshot(s,actor)
        assert(view.phase=="Finished" and view.winner==nil and view.victoryType=="Draw" and view.reason==s.reason)
        assert(not view.canAct)
        for _, choices in view.legalMoves do assert(#choices==0) end
        for _, choices in view.attackPreviews do assert(#choices==0) end
        for _, choices in view.cityStrikePreviews do assert(#choices==0) end
        assert(view.scores[1]==view.scores[2] and view.scores[1]>0 and view.statistics[1].units==3 and view.statistics[2].units==3)
        local outcome=view.events[#view.events]
        assert(outcome.kind=="Victory" and outcome.ownerId==nil and outcome.message==s.reason and outcome.public)
        assert(not Game.apply(s,actor,{kind="EndTurn"}).ok,"Draw must reject further commands")
    end
    assert(Canonical.encode(Game.serialize(s))==before,"snapshots and rejected commands must preserve the Draw")
    local save=Game.serialize(s); assert(save.version==(if s.mapShape=="Sphere" then 2 else 1) and Save.valid(save))
    local restored,message=Game.restore(save); assert(restored and message==nil)
    assert(Canonical.encode(Game.serialize(restored))==before,"Draw must round-trip exactly")
    assert(Canonical.encode(Game.snapshot(restored,2))==Canonical.encode(Game.snapshot(s,2)))
    for _, kind in {"Science","Culture","Domination","Score","Unknown"} do
        save.state.victoryType=kind
        assert(not Save.valid(save),"a non-Draw must have a winner: "..kind)
        local invalid,why=Game.restore(save); assert(invalid==nil and type(why)=="string")
    end
    save.state.victoryType="Draw"
    for _, winner in {1,2,3,false} do
        save.state.winner=winner; assert(not Save.valid(save),"a Draw must not have a winner")
    end
    save.state.winner=nil; save.state.phase="Playing"
    assert(not Save.valid(save),"a Draw must be finished")
end
print("base tiebreak: higher score, combined technologies/policies, seat symmetry, Draw snapshots/events and save validation passed")
