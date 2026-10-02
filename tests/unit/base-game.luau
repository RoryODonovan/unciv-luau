--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original base-game regression fixtures; no upstream gameplay parity claim.
local Game = require("../../src/simulation/BaseGame")
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
local function rejected(s: any,owner: number,command: any)
    local before=Game.serialize(s)
    local ok,result=pcall(function() return Game.apply(s,owner,command) end)
    assert(ok and not result.ok,"invalid command must reject without throwing")
    assert(equal(before,Game.serialize(s)),"rejection changed simulation state")
end
local function firstUnit(s: any,owner: number,kind: string): any
    for _, u in s.units do if u.ownerId==owner and u.kind==kind then return u end end; error("missing "..kind)
end
local function firstCity(s: any,owner: number): any
    for _, c in s.cities do if c.ownerId==owner then return c end end; error("missing city")
end
local function founded(seed: number?,radius: number?): any
    local s=Game.new(seed or 1,{humanPlayers=2,radius=radius or 4})
    apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id})
    apply(s,1,{kind="EndTurn"})
    apply(s,2,{kind="FoundCity",unitId=firstUnit(s,2,"Settler").id})
    apply(s,2,{kind="EndTurn"}); return s
end
local function round(s: any)
    apply(s,1,{kind="EndTurn"}); if s.phase=="Playing" then apply(s,2,{kind="EndTurn"}) end
end
-- Human two has a real turn, own units and own view. Economy ticks once per actor.
local shared: any=Game.new(17,{humanPlayers=2})
assert(shared.activePlayerId==1 and Game.snapshot(shared,1).canAct and not Game.snapshot(shared,2).canAct)
assert(Game.snapshot(shared,1).seed==nil and Game.snapshot(shared,2).seed==nil)
rejected(shared,2,{kind="EndTurn"})
rejected(shared,1,{kind="MoveUnit",unitId=firstUnit(shared,2,"Warrior").id,tileId=1})
local p2=firstUnit(shared,2,"Settler")
apply(shared,1,{kind="EndTurn"})
assert(shared.activePlayerId==2 and shared.turn==1 and Game.snapshot(shared,2).canAct)
apply(shared,2,{kind="FoundCity",unitId=p2.id})
rejected(shared,1,{kind="EndTurn"})
apply(shared,2,{kind="EndTurn"}); assert(shared.turn==2 and shared.activePlayerId==1)
-- Fog discloses geometry, then static terrain, then visible entities; never rival economy.
-- Use a larger geography so this fixture explicitly contains a hidden rival capital.
local fog=founded(23,10); local own=Game.snapshot(fog,1); local rival=firstCity(fog,2)
local unknown: any=nil
for _, tile in own.tiles do if not tile.explored then unknown=tile; break end end
assert(unknown and unknown.terrain==nil and unknown.resource==nil and unknown.ownerId==nil and unknown.food==nil)
assert(#own.cities==1 and own.cities[1].ownerId==1 and own.scores[2]==0 and own.statistics[2].technologies==0)
fog.players[2].gold=1234; fog.players[2].culture=4321; fog.players[2].technologies={"Agriculture"}
table.insert(fog.events,{id=fog.nextEvent,kind="Research",message="hidden tech",ownerId=2}); fog.nextEvent += 1
table.insert(fog.events,{id=fog.nextEvent,kind="Production",message="hidden city",ownerId=2,tileId=rival.tileId}); fog.nextEvent += 1
assert(equal(own.tiles,Game.snapshot(fog,1).tiles))
for _, e in Game.snapshot(fog,1).events do assert(e.message~="hidden tech" and e.message~="hidden city") end
-- An explored unseen tile carries no current ownership, road or improvement.
table.insert(fog.players[1].explored,unknown.id); table.sort(fog.players[1].explored)
fog.tiles[unknown.id].terrain="Plains"; fog.tiles[unknown.id].resource=nil
fog.tiles[unknown.id].ownerId=2; fog.tiles[unknown.id].road=true
local stale=Game.snapshot(fog,1).tiles[unknown.id]
assert(stale.explored and not stale.visible and stale.terrain and not stale.ownerId and not stale.road)
-- Snapshot and rules copies cannot alter the authoritative engine.
local detached=Game.snapshot(fog,1); detached.units[1].hp=1; detached.tiles[1].terrain="invented"
assert(Game.snapshot(fog,1).units[1].hp~=1)
local detachedRules=Game.getRules(); detachedRules.units.Warrior.strength=999
assert(Game.getRules().units.Warrior.strength==Rules.units.Warrior.strength)
-- Hidden blockers cannot change observable legal destinations.
local hiddenClone=Game.restore(Game.serialize(fog)); assert(hiddenClone)
local unseenEnemy=firstUnit(hiddenClone,2,"Warrior"); unseenEnemy.tileId=unknown.id
assert(equal(Game.snapshot(fog,1).legalMoves,Game.snapshot(hiddenClone,1).legalMoves))
-- Legal destinations use the same weighted movement authority for BOTH actors.
for owner=1,2 do
    local s=founded(31); if owner==2 then apply(s,1,{kind="EndTurn"}) end
    for unitId,targets in Game.snapshot(s,owner).legalMoves do
        for _, tileId in targets do
            local clone=Game.restore(Game.serialize(s)); assert(clone)
            apply(clone,owner,{kind="MoveUnit",unitId=tonumber(unitId),tileId=tileId})
        end
    end
end
local movement=founded(1); local warrior=firstUnit(movement,1,"Warrior")
local map=WorldMap.fromTiles(movement.tiles,movement.radius)
local unitsAt={}; for _, u in movement.units do unitsAt[u.tileId]=true end
local destination: number?=nil
for _, id in map.neighbors[warrior.tileId] do if not unitsAt[id] and not movement.tiles[id].ownerId then destination=id; break end end
assert(destination); movement.tiles[destination].terrain="Hills"; movement.tiles[destination].resource=nil
warrior.moves=1
rejected(movement,1,{kind="MoveUnit",unitId=warrior.id,tileId=destination})
warrior.moves=2; apply(movement,1,{kind="MoveUnit",unitId=warrior.id,tileId=destination}); assert(warrior.moves==0)
local roadDestination: number?=nil
for _, id in map.neighbors[warrior.tileId] do if not unitsAt[id] and not movement.tiles[id].ownerId then roadDestination=id; break end end
assert(roadDestination); movement.tiles[warrior.tileId].road=true; movement.tiles[roadDestination].road=true; movement.tiles[roadDestination].terrain="Hills"; movement.tiles[roadDestination].resource=nil
warrior.moves=Rules.roadMovement; apply(movement,1,{kind="MoveUnit",unitId=warrior.id,tileId=roadDestination}); assert(warrior.moves==0)
-- Worker orders take owner turns, unlock resources, then enable strategic production.
local workerState=founded(4); local worker=firstUnit(workerState,1,"Worker"); local home=firstCity(workerState,1)
local workerTile=workerState.tiles[worker.tileId]; workerTile.ownerId=1; workerTile.terrain="Plains"; workerTile.resource="Iron"
workerState.players[1].technologies={"Mining","BronzeWorking","IronWorking"}
rejected(workerState,1,{kind="BuildImprovement",unitId=worker.id,improvement="Pasture"})
apply(workerState,1,{kind="BuildImprovement",unitId=worker.id,improvement="Mine"})
for _=1,2 do round(workerState); assert(workerTile.improvement==nil) end
round(workerState); assert(workerTile.improvement=="Mine" and workerState.players[1].resources.Iron==1)
workerState.players[1].gold=1000
apply(workerState,1,{kind="Purchase",cityId=home.id,item="Swordsman"})
rejected(workerState,1,{kind="Purchase",cityId=home.id,item="Swordsman"})
local upgrade=founded(4); local upgradeUnit=firstUnit(upgrade,1,"Warrior"); local upgradeTile=upgrade.tiles[firstUnit(upgrade,1,"Worker").tileId]
upgradeTile.ownerId=1; upgradeTile.terrain="Plains"; upgradeTile.resource="Iron"; upgradeTile.improvement="Mine"
upgrade.players[1].technologies={"Mining","BronzeWorking","IronWorking"}; upgrade.players[1].gold=1000
apply(upgrade,1,{kind="UpgradeUnit",unitId=upgradeUnit.id})
assert(upgradeUnit.kind=="Swordsman" and upgradeUnit.moves==0 and upgrade.players[1].gold<1000)
assert(not table.find(Game.snapshot(upgrade,1).availableProductionByCity[tostring(firstCity(upgrade,1).id)],"Swordsman"))
assert(Game.restore(Game.serialize(upgrade)))
-- Focus changes citizens' chosen yields; maintenance and unhappiness have consequences.
local foodState=founded(5); local productionState=Game.restore(Game.serialize(foodState)); assert(productionState)
for _, fixture in {foodState,productionState} do
    local s: any=fixture
    local city=firstCity(s,1); city.population=1; city.production=0; city.food=0
    local graph=WorldMap.fromTiles(s.tiles,s.radius)
    for index,id in graph.neighbors[city.tileId] do s.tiles[id].ownerId=1; s.tiles[id].resource=nil; s.tiles[id].terrain=if index==1 then "Grassland" else "Hills" end
end
apply(foodState,1,{kind="SetCityFocus",cityId=firstCity(foodState,1).id,focus="Food"})
apply(productionState,1,{kind="SetCityFocus",cityId=firstCity(productionState,1).id,focus="Production"})
apply(foodState,1,{kind="EndTurn"}); apply(productionState,1,{kind="EndTurn"})
assert(firstCity(foodState,1).food>firstCity(productionState,1).food)
assert(firstCity(foodState,1).production<firstCity(productionState,1).production)
assert(foodState.players[1].income.maintenance>=1)
local focusedScience=founded(5); local unfocusedScience=Game.restore(Game.serialize(focusedScience)); assert(unfocusedScience)
apply(focusedScience,1,{kind="SetCityFocus",cityId=firstCity(focusedScience,1).id,focus="Science"})
apply(focusedScience,1,{kind="EndTurn"}); apply(unfocusedScience,1,{kind="EndTurn"})
assert(focusedScience.players[1].income.science>unfocusedScience.players[1].income.science)
assert(focusedScience.players[1].income.production<unfocusedScience.players[1].income.production)
local starving=founded(6); local starvingCity=firstCity(starving,1); starvingCity.population=12; starvingCity.food=0
for _, tile in starving.tiles do if tile.ownerId==1 then tile.terrain="Desert"; tile.resource=nil end end
apply(starving,1,{kind="EndTurn"})
assert(starving.players[1].happiness<0 and starvingCity.population==11 and starvingCity.food==0)
local insolvent=founded(6); local insolventHome=firstCity(insolvent,1); insolvent.players[1].gold=0
insolventHome.buildings={"Library","Workshop","Observatory"}
insolvent.players[1].technologies=table.clone(Rules.technologyOrder)
apply(insolvent,1,{kind="EndTurn"})
local maintained=0; for _, u in insolvent.units do if u.ownerId==1 then maintained += Rules.units[u.kind].maintenance end end
assert(maintained==0 and insolvent.players[1].gold==0 and insolvent.players[1].income.gold<0)
assert(Game.restore(Game.serialize(insolvent)))
-- Actual research earns science and gates technologies/buildings; duplicate actions reject.
local research=founded(7); local researchHome=firstCity(research,1)
rejected(research,1,{kind="Research",technology="Rocketry"})
rejected(research,1,{kind="SetProduction",cityId=researchHome.id,item="Library"})
apply(research,1,{kind="Research",technology="Agriculture"})
rejected(research,1,{kind="Research",technology="Agriculture"})
for _=1,5 do round(research) end
assert(table.find(research.players[1].technologies,"Agriculture") and research.players[1].science>0)
apply(research,1,{kind="SetProduction",cityId=researchHome.id,item="Granary"})
researchHome.production=Rules.productionCosts.Granary
round(research); assert(table.find(researchHome.buildings,"Granary") and researchHome.queue=="Warrior")
rejected(research,1,{kind="SetProduction",cityId=researchHome.id,item="Granary"})
assert(not table.find(Game.snapshot(research,1).availableProductionByCity[tostring(researchHome.id)],"Granary"))
assert(not table.find(Game.snapshot(research,1).availablePurchasesByCity[tostring(researchHome.id)],"Granary"))
-- Diplomacy requires actor turns; gold trades conserve gold at acceptance.
local diplomacy=founded(8); local gold2=diplomacy.players[2].gold
apply(diplomacy,1,{kind="ProposeTrade",targetId=2,giveGold=10,receiveGold=4})
rejected(diplomacy,1,{kind="AcceptTrade",tradeId=1})
apply(diplomacy,1,{kind="EndTurn"})
local total=diplomacy.players[1].gold+diplomacy.players[2].gold
apply(diplomacy,2,{kind="AcceptTrade",tradeId=1})
assert(diplomacy.players[1].gold+diplomacy.players[2].gold==total and diplomacy.players[2].gold==gold2+6)
apply(diplomacy,2,{kind="DeclareWar",targetId=1})
rejected(diplomacy,2,{kind="ProposeTrade",targetId=1,giveGold=1,receiveGold=0})
apply(diplomacy,2,{kind="OfferPeace",targetId=1}); apply(diplomacy,2,{kind="EndTurn"})
apply(diplomacy,1,{kind="AcceptPeace",targetId=2})
rejected(diplomacy,1,{kind="DeclareWar",targetId=2})
assert(diplomacy.diplomacy.status=="Peace" and diplomacy.diplomacy.peaceUntil>diplomacy.turn)
-- Ranged combat is visible, consumes movement and does not retaliate or capture.
local ranged=founded(9); local attacker=firstUnit(ranged,1,"Warrior"); local defender=firstUnit(ranged,2,"Warrior")
local rangedMap=WorldMap.fromTiles(ranged.tiles,ranged.radius)
local target: number?=nil
for _, tile in ranged.tiles do if WorldMap.distance(rangedMap,attacker.tileId,tile.id)==2 and not tile.ownerId then target=tile.id; break end end
assert(target); ranged.tiles[target].terrain="Plains"; ranged.tiles[target].resource=nil; defender.tileId=target; attacker.kind="Archer"; attacker.hp=Rules.units.Archer.hp
apply(ranged,1,{kind="DeclareWar",targetId=2})
local hp=attacker.hp; local enemyHp=defender.hp
apply(ranged,1,{kind="RangedAttack",unitId=attacker.id,tileId=defender.tileId})
assert(attacker.hp==hp and defender.hp<enemyHp and attacker.moves==0 and attacker.tileId~=defender.tileId)
-- Each victory is attained through authoritative commands, never a victory command.
local domination=founded(10); local conqueror=firstUnit(domination,1,"Warrior"); local capital=firstCity(domination,2)
local conquestMap=WorldMap.fromTiles(domination.tiles,domination.radius)
local occupied={}; for _, u in domination.units do occupied[u.tileId]=true end
for _, id in conquestMap.neighbors[capital.tileId] do if not occupied[id] then conqueror.tileId=id; break end end
capital.hp=1; apply(domination,1,{kind="DeclareWar",targetId=2}); apply(domination,1,{kind="MoveUnit",unitId=conqueror.id,tileId=capital.tileId})
assert(domination.phase=="Finished" and domination.winner==1 and domination.victoryType=="Domination")
local science=founded(11); science.players[1].technologies=table.clone(Rules.technologyOrder)
local scienceHome=firstCity(science,1); scienceHome.production=Rules.productionCosts.SpaceProject
apply(science,1,{kind="SetProduction",cityId=scienceHome.id,item="SpaceProject"}); apply(science,1,{kind="EndTurn"})
assert(science.winner==1 and science.victoryType=="Science")
local culture=founded(12); culture.players[1].culture=1000
for _, id in Rules.policyOrder do apply(culture,1,{kind="AdoptPolicy",policy=id}) end
assert(culture.winner==1 and culture.victoryType=="Culture")
local score: any=Game.new(13,{humanPlayers=2,maxTurns=20})
apply(score,1,{kind="FoundCity",unitId=firstUnit(score,1,"Settler").id}); apply(score,1,{kind="EndTurn"})
apply(score,2,{kind="FoundCity",unitId=firstUnit(score,2,"Settler").id}); apply(score,2,{kind="EndTurn"})
while score.phase=="Playing" do round(score) end
assert(score.victoryType=="Score" and score.turn==20)
-- Runtime unit capacity is reflected in menu choices and purchase validation.
local capped: any=Game.new(13,{humanPlayers=2,radius=7})
apply(capped,1,{kind="FoundCity",unitId=firstUnit(capped,1,"Settler").id}); capped.players[1].gold=1000
local occupiedTiles={}; for _, u in capped.units do occupiedTiles[u.tileId]=true end
for _, tile in capped.tiles do
    tile.terrain="Plains"
    if not occupiedTiles[tile.id] then table.insert(capped.units,{id=capped.nextUnit,ownerId=1,kind="Warrior",tileId=tile.id,hp=100,moves=0,fortified=false,level=0}); capped.nextUnit += 1 end
end
assert(#capped.units==Rules.maxUnits)
rejected(capped,1,{kind="Purchase",cityId=firstCity(capped,1).id,item="Warrior"})
assert(not table.find(Game.snapshot(capped,1).availableProductionByCity[tostring(firstCity(capped,1).id)],"Warrior"))
-- Purchases and production share the movement rule for peaceful foreign land.
-- Every candidate except one foreign-owned neighbor is occupied by own units.
local function blockedDeployment(owner: number): (any,any,number)
    local s=founded(24+owner); if owner==2 then apply(s,1,{kind="EndTurn"}) end
    local city=firstCity(s,owner); local graph=WorldMap.fromTiles(s.tiles,s.radius)
    local unitsAt={}; for _, u in s.units do unitsAt[u.tileId]=true end
    local target: number?=nil
    for _, id in graph.neighbors[city.tileId] do if not unitsAt[id] then target=id; break end end
    assert(target)
    local candidates={city.tileId}; for _, id in graph.neighbors[city.tileId] do table.insert(candidates,id) end
    for _, id in candidates do
        local tile=s.tiles[id]; tile.terrain="Plains"; tile.resource=nil; tile.improvement=nil; tile.road=nil
        tile.ownerId=if id==target then 3-owner else owner
        if id~=target and not unitsAt[id] then
            table.insert(s.units,{id=s.nextUnit,ownerId=owner,kind="Worker",tileId=id,hp=Rules.units.Worker.hp,moves=0,fortified=false,level=0}); s.nextUnit += 1
        end
    end
    s.players[owner].gold=1000; city.queue="Warrior"; city.production=Rules.productionCosts.Warrior
    assert(Game.restore(Game.serialize(s)),"deployment fixture must be a valid resumable state")
    return s,city,target
end
for owner=1,2 do
    local peaceful,city,foreignTile=blockedDeployment(owner)
    rejected(peaceful,owner,{kind="Purchase",cityId=city.id,item="Warrior"})
    local purchases=Game.snapshot(peaceful,owner).availablePurchasesByCity[tostring(city.id)]
    assert(not table.find(purchases,"Warrior") and table.find(purchases,"Monument"))
    local count,beforeProduction=#peaceful.units,city.production
    apply(peaceful,owner,{kind="EndTurn"})
    assert(#peaceful.units==count and city.production>beforeProduction and peaceful.tiles[foreignTile].ownerId==3-owner)
    assert(Game.restore(Game.serialize(peaceful)))
    for _, relation in {"Own","War"} do
        local allowed,allowedCity,allowedTarget=blockedDeployment(owner)
        if relation=="Own" then allowed.tiles[allowedTarget].ownerId=owner
        else apply(allowed,owner,{kind="DeclareWar",targetId=3-owner}) end
        assert(table.find(Game.snapshot(allowed,owner).availablePurchasesByCity[tostring(allowedCity.id)],"Warrior"))
        local productionClone=Game.restore(Game.serialize(allowed)); assert(productionClone)
        local oldCount=#allowed.units
        apply(allowed,owner,{kind="Purchase",cityId=allowedCity.id,item="Warrior"})
        assert(#allowed.units==oldCount+1 and allowed.units[#allowed.units].ownerId==owner and allowed.units[#allowed.units].tileId==allowedTarget)
        apply(productionClone,owner,{kind="EndTurn"})
        assert(#productionClone.units==oldCount+1 and productionClone.units[#productionClone.units].ownerId==owner and productionClone.units[#productionClone.units].tileId==allowedTarget)
        assert(Game.restore(Game.serialize(allowed)) and Game.restore(Game.serialize(productionClone)))
    end
end
-- Solo AI acts once per round, researches, produces and stays deterministically resumable.
for _, difficulty in {"Easy","Normal","Hard"} do
    for seed=1,4 do
        local original: any=Game.new(seed,{difficulty=difficulty,maxTurns=60,radius=3+seed%3})
        apply(original,1,{kind="FoundCity",unitId=firstUnit(original,1,"Settler").id})
        local resumed=Game.restore(Game.serialize(original)); assert(resumed)
        for _=1,60 do
            if original.phase=="Finished" then break end
            apply(original,1,{kind="EndTurn"}); apply(resumed,1,{kind="EndTurn"})
            assert(equal(Game.serialize(original),Game.serialize(resumed)),"AI replay diverged")
            local restored=Game.restore(Game.serialize(resumed)); assert(restored); resumed=restored
            assert(original.activePlayerId==1 or original.phase=="Finished")
        end
        assert(original.players[2].science>0 and #original.players[2].technologies>0)
        assert(original.phase=="Finished" and Game.restore(Game.serialize(original)))
    end
end
-- Rejection is atomic across malformed inputs and nonfinite/unknown payload fields.
local malformed=founded(14)
for _, command in {false,5,"bad",{}, {kind="EndTurn",unexpected=true}, {kind="MoveUnit",unitId=0/0,tileId=1}, {kind="BuildImprovement",unitId=1,improvement={}}, {kind="Research",technology={}}, {kind="ProposeTrade",targetId=2,giveGold=math.huge,receiveGold=1}, {kind="Purchase",cityId=999,item="Warrior"}, {kind="RangedAttack",unitId=firstUnit(malformed,1,"Worker").id,tileId=1}} do rejected(malformed,1,command) end
rejected(malformed,1,nil); rejected(malformed,1,setmetatable({kind="EndTurn"},{}))
print("base game: actor turns, fog, detached snapshots, weighted legal moves, workers/resources, economy/focus/starvation, research/buildings, peace/trade, ranged combat, four victories and 12 deterministic AI replays passed")
