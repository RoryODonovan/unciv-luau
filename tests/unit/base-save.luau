--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original bounded trust-boundary tests, independent fixture with every entity family.
local Save=require("../../src/simulation/BaseSave")
local Map=require("../../src/simulation/WorldMap")
local function copy(value: any): any
    if type(value)~="table" then return value end
    local result={}; for key,child in value do result[key]=copy(child) end; return result
end
local function equal(a: any,b: any): boolean
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for key,value in a do if not equal(value,b[key]) then return false end end
    for key in b do if a[key]==nil then return false end end
    return true
end
local map=Map.generate(124,3)
local left=Map.tileId(map,-2,0) :: number
local right=Map.tileId(map,2,0) :: number
local center=Map.tileId(map,0,0) :: number
local worker=Map.tileId(map,1,0) :: number
for _,id in {left,right,center,worker} do map.tiles[id].terrain="Plains"; map.tiles[id].resource=nil end
map.tiles[center].ownerId=1; map.tiles[worker].ownerId=1; map.tiles[worker].terrain="Plains"; map.tiles[worker].resource="Wheat"
local explored={}; for id=1,#map.tiles do table.insert(explored,id) end
local state: any={seed=124,radius=3,difficulty="Normal",humanPlayers=2,forest=true,maxTurns=120,turn=1,revision=4,activePlayerId=1,phase="Playing",tiles=map.tiles,
    units={{id=1,ownerId=1,kind="Settler",tileId=left,hp=50,moves=2,fortified=false,level=0},{id=2,ownerId=2,kind="Settler",tileId=right,hp=50,moves=2,fortified=false,level=0},{id=3,ownerId=1,kind="Worker",tileId=worker,hp=50,moves=0,fortified=false,level=0,work={improvement="Farm",remaining=1}}},
    cities={{id=1,ownerId=1,originalOwnerId=1,capital=true,tileId=center,name="Fixture",borderCulture=0,borderTiles=0,population=2,food=7,production=3,queue="Warrior",hp=150,buildings={"Granary"},focus="Balanced"}},players={},
    diplomacy={status="Peace",peaceUntil=0,met=true},trades={{id=1,fromId=1,toId=2,giveGold=5,receiveGold=3,expires=4}},events={{id=1,kind="FoundCity",message="Founded.",tileId=center,unitId=1,ownerId=1,public=false}},nextEvent=2,nextUnit=4,nextCity=2,nextTrade=2,log={}}
for id=1,2 do table.insert(state.players,{id=id,human=true,gold=30,science=0,culture=0,happiness=9,technologies=if id==1 then {"Agriculture"} else {},policies={},explored=copy(explored),resources={},income={food=0,production=0,gold=0,science=0,culture=0,maintenance=0}}) end
local valid={format="unciv-luau-base",version=1,state=state}
assert(Save.valid(valid),"complete fixture must validate")
local serialized=Save.serialize(state)
local restored,err=Save.restore(serialized)
assert(restored and err==nil and equal(restored,state))
serialized.state.units[1].hp=1; assert(state.units[1].hp==50 and restored.units[1].hp==50)
restored.players[1].explored[1]=999; assert(state.players[1].explored[1]==1)
local checks=0
local function corrupt(change: (any)->())
    local value=copy(valid); change(value); checks+=1
    assert(not Save.valid(value),"corrupt case "..checks.." accepted")
    local loaded,error=Save.restore(value); assert(loaded==nil and type(error)=="string")
end
corrupt(function(s) s.version=2 end)
corrupt(function(s) s.format="unciv-luau-original" end)
corrupt(function(s) s.extra=true end)
corrupt(function(s) s.state.extra=true end)
corrupt(function(s) s.state.maxTurns=501 end)
corrupt(function(s) s.state.radius=41 end)
corrupt(function(s) s.state.turn=0 end)
corrupt(function(s) s.state.turn=121 end)
corrupt(function(s) s.state.seed=0/0 end)
corrupt(function(s) s.state.players[1].gold=math.huge end)
corrupt(function(s) s.state.players[1].gold=-1 end)
corrupt(function(s) s.state.players[1].gold=1.5 end)
corrupt(function(s) s.state.players[1].human=false end)
corrupt(function(s) s.state.players[1].income.science=nil end)
corrupt(function(s) s.state.players[1].income.unknown=0 end)
corrupt(function(s) s.state.players[1].income.maintenance=-1 end)
corrupt(function(s) s.state.players[1].resources.Unknown=1 end)
corrupt(function(s) s.state.players[1].resources.Iron=-1 end)
corrupt(function(s) s.state.players[1].technologies={"Astronomy"} end)
corrupt(function(s) s.state.players[1].technologies={"Agriculture","Agriculture"} end)
corrupt(function(s) s.state.players[1].policies={"Commerce"} end)
corrupt(function(s) s.state.players[1].research={id="Writing",cost=1,progress=0} end)
corrupt(function(s) s.state.players[1].research={id="Mining",cost=14,progress=14} end)
corrupt(function(s) s.state.players[1].explored={2,1} end)
corrupt(function(s) s.state.players[1].explored={1,1} end)
corrupt(function(s) s.state.players[1].explored={1000} end)
corrupt(function(s) s.state.tiles[1].id=2 end)
corrupt(function(s) s.state.tiles[1].x=s.state.tiles[2].x; s.state.tiles[1].y=s.state.tiles[2].y end)
corrupt(function(s) s.state.tiles[1].x=100 end)
corrupt(function(s) s.state.tiles[1].terrain="Lava" end)
corrupt(function(s) s.state.tiles[1].resource="Uranium" end)
corrupt(function(s) s.state.tiles[1].resource="Iron"; s.state.tiles[1].terrain="Water" end)
corrupt(function(s) s.state.tiles[1].improvement="Farm"; s.state.tiles[1].terrain="Water" end)
corrupt(function(s) s.state.tiles[1].food=9 end)
corrupt(function(s) s.state.units[1].tileId=999 end)
corrupt(function(s) s.state.units[1].kind="Dragon" end)
corrupt(function(s) s.state.units[1].kind="Archer" end)
corrupt(function(s) s.state.units[1].hp=1000 end)
corrupt(function(s) s.state.units[1].moves=0.25 end)
corrupt(function(s) s.state.units[1].moves=3 end)
corrupt(function(s) s.state.units[1].id=4 end)
corrupt(function(s) s.state.units[1].ownerId=3 end)
corrupt(function(s) s.state.units[2].tileId=s.state.units[1].tileId end)
corrupt(function(s) s.state.units[3].work.remaining=99 end)
corrupt(function(s) s.state.units[1].work={improvement="Farm",remaining=1} end)
corrupt(function(s) s.state.cities[1].hp=151 end)
corrupt(function(s) s.state.cities[1].buildings={"Library","Library"} end)
corrupt(function(s) s.state.cities[1].population=101 end)
corrupt(function(s) s.state.cities[1].ownerId=2 end)
corrupt(function(s) s.state.cities[1].focus="Unbounded" end)
corrupt(function(s) s.state.cities[1].queue="Granary" end)
corrupt(function(s) s.state.diplomacy.status="Alliance" end)
corrupt(function(s) s.state.diplomacy.peaceOfferBy=1 end)
corrupt(function(s) s.state.trades[1].toId=1 end)
corrupt(function(s) s.state.trades[1].giveGold=100001 end)
corrupt(function(s) s.state.trades[1].giveGold=0; s.state.trades[1].receiveGold=0 end)
corrupt(function(s) s.state.events[1].tileId=999 end)
corrupt(function(s) s.state.events[1].unitId=4 end)
corrupt(function(s) s.state.events[1].message=string.rep("x",257) end)
corrupt(function(s) s.state.events[1].id=2 end)
corrupt(function(s) s.state.nextEvent=5 end)
corrupt(function(s) s.state.winner=1 end)
corrupt(function(s) s.state.phase="Finished" end)
corrupt(function(s) s.state.units[1]=nil end)
corrupt(function(s) s.state.tiles.extra=1 end)
corrupt(function(s) s.state[{}]=1 end)
corrupt(function(s) s.state.log[1]=function() end end)
corrupt(function(s) s.state.log[1]=coroutine.create(function() end) end)
corrupt(function(s) s.state.log[1]=buffer.create(1) end)
corrupt(function(s) s.state.log[1]=string.rep("x",513) end)
corrupt(function(s) setmetatable(s.state,{}) end)
corrupt(function(s) s.state.log=s.state.events end)
corrupt(function(s) s.state.log[1]=s.state end)
corrupt(function(s) local node={}; s.state.log[1]=node; for _=1,12 do local child={}; node.child=child; node=child end end)
corrupt(function(s) for i=1,16385 do s.state.log[i]=true end end)
assert(not Save.valid(nil) and not Save.valid("save") and not Save.valid(1))
local large=copy(valid)
large.state.radius=7; large.state.tiles=Map.generate(124,7).tiles
-- The complete topology alone remains bounded; entity references are rebuilt for a true max-map fixture.
local largeMap=Map.fromTiles(large.state.tiles,7)
large.state.units[1].tileId=Map.tileId(largeMap,-6,0); large.state.units[2].tileId=Map.tileId(largeMap,6,0)
large.state.units[3].tileId=Map.tileId(largeMap,1,0); large.state.tiles[large.state.units[3].tileId].terrain="Plains"; large.state.tiles[large.state.units[3].tileId].ownerId=1; large.state.tiles[large.state.units[3].tileId].resource="Wheat"
large.state.cities[1].tileId=Map.tileId(largeMap,0,0); large.state.tiles[large.state.cities[1].tileId].ownerId=1
for _,id in {large.state.units[1].tileId,large.state.units[2].tileId,large.state.cities[1].tileId} do large.state.tiles[id].terrain="Plains"; large.state.tiles[id].resource=nil end
large.state.events[1].tileId=large.state.cities[1].tileId
for _,p in large.state.players do p.explored={}; for i=1,169 do table.insert(p.explored,i) end end
assert(Save.valid(large),"max map fixture rejected")
local loaded=Save.restore(large); assert(loaded and #loaded.tiles==169)
local finished=copy(valid); finished.state.phase="Finished"; finished.state.humanPlayers=1; finished.state.players[2].human=false; finished.state.activePlayerId=2; finished.state.winner=2; finished.state.reason="Culture victory for civilization 2."; finished.state.victoryType="Culture"
assert(Save.valid(finished),"a rival win retains its final active turn")
print("base save passed "..checks.." corrupt-input cases and detached roundtrips")


