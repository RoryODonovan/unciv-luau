--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original restore regressions using a save written by the preceding library, not a current-state imitation.
local Game=require("../../src/simulation/BaseGame")
local Save=require("../../src/simulation/BaseSave")
local Map=require("../../src/simulation/WorldMap")
local legacy: any=require("../fixtures/base-territory-30be232")
local restores: {(any) -> (any?,string?)}={Game.restore,Save.restore}
local function copy(v: any): any
    if type(v)~="table" then return v end
    local result={}; for k,child in v do result[k]=copy(child) end; return result
end
local function equal(a: any,b: any): boolean
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in a do if not equal(v,b[k]) then return false end end
    for k in b do if a[k]==nil then return false end end
    return true
end
assert(Save.valid(legacy),"actual 30be232 save is still valid")
local map=Map.fromTiles(legacy.state.tiles,legacy.state.radius)
local target=assert(Map.tileId(map,3,0))
assert(legacy.state.tiles[assert(Map.tileId(map,2,0))].ownerId==1)
assert(not table.find(legacy.state.players[1].explored,target) and legacy.state.diplomacy.met==false)
local before=copy(legacy)
for _,restore in restores do
    local s=assert(restore(legacy)); local v=Game.snapshot(s,1); local tile=v.tiles[target]
    assert(tile.visible and tile.explored,"restore explores the newly visible territory ring")
    assert(tile.terrain=="Plains" and tile.resource=="Gold","restore projects visible terrain and resource")
    local found=false; for _,u in v.units do if u.ownerId==2 and u.tileId==target then found=true end end
    assert(found and v.diplomacy.met and Game.snapshot(s,2).diplomacy.met,"visible rival establishes bilateral contact on load")
    for actor=1,2 do
        for _,t in Game.snapshot(s,actor).tiles do assert(not t.visible or t.explored,"both owners reconcile exploration") end
    end
    assert(equal(s.events,legacy.state.events) and s.nextEvent==legacy.state.nextEvent,"restore contact is silent")
    assert(s.revision==legacy.state.revision and equal(s.log,legacy.state.log),"restore is not a command")
    local again=assert(restore(Game.serialize(s)))
    assert(equal(s,again) and equal(v,Game.snapshot(again,1)),"reconciliation is idempotent")
    -- An unrelated command must no longer repair exploration/contact in the restored projection.
    assert(Game.apply(s,1,{kind="SetCityFocus",cityId=s.cities[1].id,focus="Food"}).ok)
    assert(equal(s.players[1].explored,again.players[1].explored) and equal(s.players[2].explored,again.players[2].explored))
    assert(equal(s.events,again.events) and s.nextEvent==again.nextEvent,"no delayed Contact event")
end
assert(equal(legacy,before),"restore never mutates its input")
-- Contact must use either owner's sight and both entity families, even with persisted false or absent met.
for owner=1,2 do for kind=1,2 do for missing=1,2 do
    local saved: any=copy(legacy)
    if kind==2 then
        saved.state.units={}; saved.state.cities[2].tileId=target; saved.state.tiles[target].ownerId=2
    end
    if owner==2 then
        for _,t in saved.state.tiles do if t.ownerId then t.ownerId=3-t.ownerId end end
        for _,u in saved.state.units do u.ownerId=3-u.ownerId end
        for _,c in saved.state.cities do c.ownerId=3-c.ownerId; c.originalOwnerId=3-c.originalOwnerId end
        saved.state.players[1].explored,saved.state.players[2].explored=saved.state.players[2].explored,saved.state.players[1].explored
    end
    if missing==2 then saved.state.diplomacy.met=nil end
    assert(Save.valid(saved))
    for _,restore in restores do
        local s=assert(restore(saved)); assert(s.diplomacy.met,"unit/city contact from either owner")
        assert(equal(s.events,saved.state.events) and s.nextEvent==saved.state.nextEvent)
    end
end end end
-- Historical exploration alone cannot establish contact; existing true contact is never lost.
for _,met in {false,true} do
    local saved: any=copy(legacy); saved.state.units={}; saved.state.tiles[assert(Map.tileId(map,2,0))].ownerId=nil
    saved.state.diplomacy.met=met
    for actor=1,2 do saved.state.players[actor].explored={}; for id=1,#saved.state.tiles do table.insert(saved.state.players[actor].explored,id) end end
    for _,restore in restores do assert(assert(restore(saved)).diplomacy.met==met) end
end
-- Genuine current-format saves retain the complete state and both snapshots on Hex and Sphere.
for _,shape in {"Hex","Sphere"} do
    local s=Game.new(7919,{mapShape=shape,frequency=if shape=="Sphere" then 3 else nil,humanPlayers=2,barbarians=false})
    local settler=nil; for _,u in s.units do if u.ownerId==1 and u.kind=="Settler" then settler=u.id end end
    assert(Game.apply(s,1,{kind="FoundCity",unitId=assert(settler)}).ok)
    local saved=Game.serialize(s)
    for _,restore in restores do
        local loaded=assert(restore(saved)); assert(equal(saved,Game.serialize(loaded)),"current save remains unchanged")
        for actor=1,2 do assert(equal(Game.snapshot(s,actor),Game.snapshot(loaded,actor)),"current snapshot remains unchanged") end
    end
end
print("restore exploration/contact: preceding-library fixture, both APIs, both owners, silent contact and current idempotence passed")
