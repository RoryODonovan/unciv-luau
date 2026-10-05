--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original G15 fixtures: class slots, transit, production, protection/capture, projections and saves.
local Game=require("../../src/simulation/BaseGame")
local Save=require("../../src/simulation/BaseSave")
local Map=require("../../src/simulation/WorldMap")
local Rules=require("../../src/simulation/BaseRules")
local function apply(s: any,owner: number,cmd: any)
    local result=Game.apply(s,owner,cmd); assert(result.ok,result.message)
end
local function equal(a: any,b: any): boolean
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in a do if not equal(v,b[k]) then return false end end
    for k in b do if a[k]==nil then return false end end
    return true
end
local function reject(s: any,cmd: any)
    local before=Game.serialize(s)
    assert(not Game.apply(s,1,cmd).ok)
    assert(equal(before,Game.serialize(s)),"rejection is atomic")
end
local function place(s: any,owner: number,kind: string,tile: number): any
    local u={id=s.nextUnit,ownerId=owner,kind=kind,tileId=tile,hp=Rules.units[kind].hp,moves=Rules.units[kind].moves,fortified=false,level=0}
    s.nextUnit+=1; table.insert(s.units,u); return u
end
local function fixture(shape: string?): (any,number,number,number,any)
    local s: any=Game.new(115,if shape=="Sphere" then {humanPlayers=2,mapShape="Sphere",frequency=4} else {humanPlayers=2,radius=8})
    for owner=1,2 do
        for _,u in s.units do if u.ownerId==owner and u.kind=="Settler" then apply(s,owner,{kind="FoundCity",unitId=u.id}); break end end
        apply(s,owner,{kind="EndTurn"})
    end
    s.units={}
    for _,t in s.tiles do t.terrain="Plains"; t.feature=nil; t.river=nil; t.resource=nil; t.improvement=nil; t.road=nil end
    local g=if shape=="Sphere" then Map.fromSphereTiles(s.tiles,s.frequency) else Map.fromTiles(s.tiles,s.radius)
    for _,t in s.tiles do
        local far=true; for _,c in s.cities do if Map.distance(g,t.id,c.tileId)<4 then far=false end end
        if not far then continue end
        local a=t.id; local b=g.neighbors[a][1]
        for _,c in g.neighbors[b] do
            if Map.distance(g,a,c)==2 then
                for _,id in Map.range(g,a,3) do s.tiles[id].ownerId=nil end
                return s,a,b,c,g
            end
        end
    end
    error("no arena")
end
local function listed(s: any,u: any,tile: number): boolean
    return table.find(Game.snapshot(s,1).legalMoves[tostring(u.id)],tile)~=nil
end
local function roundtrip(s: any)
    local saved=Game.serialize(s); assert(Save.valid(saved))
    local restored,message=Game.restore(saved); assert(restored,message)
    assert(equal(s.units,restored.units) and equal(s.cities,restored.cities) and equal(s.events,restored.events),"stack/capture save roundtrip")
    local canonical=Game.serialize(restored); local twice=Game.restore(canonical); assert(twice and equal(canonical,Game.serialize(twice)),"canonical restore is stable")
end

-- Both movement directions; combat roles (Scout, Melee, Ranged) share one military slot.
for _,shape in {"Hex","Sphere"} do
    for _,kinds in {{"Warrior","Worker"},{"Worker","Warrior"},{"Settler","Archer"},{"Scout","Settler"}} do
        local s,a,b=fixture(shape); local mover=place(s,1,kinds[1],a); local friend=place(s,1,kinds[2],b)
        if friend.kind=="Archer" then s.players[1].technologies={"Agriculture","Archery"} end
        local before=Game.serialize(s); local p=Game.previewMove(s,1,mover.id,b)
        assert(p and listed(s,mover,b) and equal(before,Game.serialize(s)))
        apply(s,1,{kind="MoveUnit",unitId=mover.id,tileId=b})
        assert(mover.tileId==friend.tileId and mover.moves==p.movesLeft)
        local count=0; for _,u in Game.snapshot(s,1).units do if u.tileId==b then count+=1 end end
        assert(count==2,"snapshot preserves both units")
        roundtrip(s)
    end
    for _,kinds in {{"Worker","Settler"},{"Warrior","Scout"},{"Warrior","Archer"}} do
        local s,a,b=fixture(shape); local u=place(s,1,kinds[1],a); place(s,1,kinds[2],b)
        if kinds[2]=="Archer" then s.players[1].technologies={"Agriculture","Archery"} end
        assert(not listed(s,u,b) and Game.previewMove(s,1,u.id,b)==nil)
        reject(s,{kind="MoveUnit",unitId=u.id,tileId=b})
    end
end
-- Enemy/peaceful owners block all civilian movement. Save validation rejects both duplicate slots and mixed owners.
do
    local s,a,b=fixture(); local u=place(s,1,"Worker",a); local v=place(s,2,"Warrior",b)
    assert(not listed(s,u,b)); reject(s,{kind="MoveUnit",unitId=u.id,tileId=b})
    local bad=Game.serialize(s); bad.state.units[2].tileId=a; assert(not Save.valid(bad))
    v.ownerId=1; v.kind="Settler"; v.hp=50
    bad=Game.serialize(s); bad.state.units[2].tileId=a; assert(not Save.valid(bad))
end
-- Same-class transit through a corridor, including a full stack. Cost/river forced stops cannot transit.
for _,kind in {"Warrior","Worker"} do
    local s,a,b,c,g=fixture(); local u=place(s,1,kind,a); place(s,1,kind,b)
    place(s,1,if kind=="Worker" then "Warrior" else "Worker",b)
    for _,id in Map.range(g,a,3) do if id~=a and id~=b and id~=c then s.tiles[id].terrain="Mountain" end end
    local p=Game.previewMove(s,1,u.id,c); assert(p and #p.path==3 and p.path[2]==b and p.movesLeft==0)
    assert(not listed(s,u,b) and listed(s,u,c)); reject(s,{kind="MoveUnit",unitId=u.id,tileId=b})
    s.tiles[b].terrain="Hills"; assert(Game.previewMove(s,1,u.id,c)==nil)
    s.tiles[b].terrain="Plains"; s.tiles[a].river=2^((table.find(g.neighbors[a],b) :: number)-1)
    s.tiles[b].river=2^((table.find(g.neighbors[b],a) :: number)-1)
    assert(Game.previewMove(s,1,u.id,c)==nil)
    s.tiles[a].road=true; s.tiles[b].road=true; s.tiles[c].road=true
    assert(Game.previewMove(s,1,u.id,c)~=nil,"bridged roads permit transit")
    apply(s,1,{kind="MoveUnit",unitId=u.id,tileId=c}); assert(u.tileId==c)
end
-- A zone-of-control stop also cannot use a filled military slot as an intermediate node.
do
    local s,a,b,c,g=fixture(); local mover=place(s,1,"Warrior",a); place(s,1,"Scout",b)
    local enemy: number?=nil
    for _,id in g.neighbors[a] do if id~=b and table.find(g.neighbors[b],id) then enemy=id; break end end
    assert(enemy)
    for _,id in Map.range(g,a,3) do if id~=a and id~=b and id~=c and id~=enemy then s.tiles[id].terrain="Mountain" end end
    place(s,2,"Warrior",enemy :: number); apply(s,1,{kind="DeclareWar",targetId=2})
    assert(Game.previewMove(s,1,mover.id,c)==nil,"zone of control forces a stop before passing the occupied slot")
end
-- The public EndTurn AI path uses the same slots: its sole legal destination is a working civilian's tile.
do
    local s,a,b,_,g=fixture(); s.humanPlayers=1; s.players[2].human=false; s.players[2].technologies={"Mining"}
    local soldier=place(s,2,"Warrior",a); local worker=place(s,2,"Worker",b)
    s.tiles[b].ownerId=2; s.tiles[b].terrain="Hills"
    worker.moves=0; worker.work={improvement="Mine",remaining=Rules.improvements.Mine.turns}
    for _,id in Map.range(g,a,3) do if id~=a and id~=b then s.tiles[id].terrain="Mountain" end end
    apply(s,1,{kind="EndTurn"})
    assert(s.activePlayerId==1 and soldier.tileId==b and worker.tileId==b,"AI moves onto friendly civilian and completes turn")
    roundtrip(s)
end
-- Military first in either array order: surviving defenders protect; melee kills capture; ranged kills leave civilians.
for _,civilianKind in {"Worker","Settler"} do
    for _,reverse in {false,true} do
        for _,mode in {"Survives","MeleeKill","RangedKill"} do
            local s,a,b=fixture(); apply(s,1,{kind="DeclareWar",targetId=2})
            local attacker=place(s,1,if mode=="RangedKill" then "Archer" else "Warrior",a)
            if attacker.kind=="Archer" then s.players[1].technologies={"Agriculture","Archery"} end
            local victim: any; local defender: any
            if reverse then victim=place(s,2,civilianKind,b); defender=place(s,2,"Warrior",b)
            else defender=place(s,2,"Warrior",b); victim=place(s,2,civilianKind,b) end
            if mode~="Survives" then defender.hp=1 end
            local hp=victim.hp; local p=Game.previewAttack(s,1,attacker.id,b); assert(p and p.defenderHp==defender.hp and p.civilianUnitId==victim.id)
            assert(p.capturesCivilian==(if mode=="MeleeKill" then "Yes" else "No"))
            apply(s,1,{kind=if mode=="RangedKill" then "RangedAttack" else "MoveUnit",unitId=attacker.id,tileId=b})
            assert(victim.hp==hp,"protected civilian takes no damage")
            if mode=="MeleeKill" then
                assert(attacker.tileId==b and victim.ownerId==1 and victim.kind=="Worker" and victim.moves==0)
                assert(victim.work==nil and victim.sentry==nil and p.advances)
                local loss=false; for _,e in Game.snapshot(s,2).events do if e.kind=="UnitLost" and e.unitId==victim.id then loss=e.cause=="Captured" and e.unitKind==civilianKind end end
                assert(loss,"loser sees captured original kind")
            else assert(attacker.tileId==a and victim.ownerId==2 and victim.kind==civilianKind) end
            roundtrip(s)
        end
    end
    -- Lone melee capture is immediate at full HP, with no retaliation or experience.
    local s,a,b=fixture(); apply(s,1,{kind="DeclareWar",targetId=2})
    local attacker=place(s,1,"Warrior",a); local victim=place(s,2,civilianKind,b)
    local p=Game.previewAttack(s,1,attacker.id,b); assert(p and p.dealt==0 and p.received==0 and p.capturesCivilian=="Yes")
    apply(s,1,{kind="MoveUnit",unitId=attacker.id,tileId=b})
    assert(attacker.hp==100 and attacker.xp==nil and victim.ownerId==1 and victim.kind=="Worker"); roundtrip(s)
end
-- City strikes cannot bypass the military defender by naming the stacked civilian's id.
do
    local s,_,_,_,g=fixture(); local city=s.cities[1]; local tile=g.neighbors[city.tileId][1]
    local worker=place(s,2,"Worker",tile); local defender=place(s,2,"Warrior",tile)
    apply(s,1,{kind="DeclareWar",targetId=2})
    assert(Game.previewCityStrike(s,1,city.id,worker.id)==nil)
    reject(s,{kind="CityRangedStrike",cityId=city.id,targetUnitId=worker.id})
    local p=Game.previewCityStrike(s,1,city.id,defender.id); assert(p)
    apply(s,1,{kind="CityRangedStrike",cityId=city.id,targetUnitId=defender.id})
    assert(worker.hp==50 and defender.hp==100-p.dealt); roundtrip(s)
end
-- City slot priority, bounded nearest fallback, forecasts and purchase menus use the produced class.
for _,shape in {"Hex","Sphere"} do
    for _,item in {"Worker","Warrior"} do
        local s,_,_,_,g=fixture(shape); local city=s.cities[1]; s.players[1].gold=1000
        place(s,1,if item=="Worker" then "Warrior" else "Worker",city.tileId)
        local id=s.nextUnit; apply(s,1,{kind="Purchase",cityId=city.id,item=item})
        assert(s.units[#s.units].id==id and s.units[#s.units].tileId==city.tileId,"city first despite other class")
        local neighbors=table.clone(g.neighbors[city.tileId]); table.sort(neighbors)
        for _,tile in neighbors do s.tiles[tile].terrain="Plains"; s.tiles[tile].ownerId=1 end
        apply(s,1,{kind="Purchase",cityId=city.id,item=item})
        assert(s.units[#s.units].tileId==neighbors[1],"occupied slot falls back to nearest legal tile")
        for _,tile in neighbors do
            local occupied=false; for _,u in s.units do if u.tileId==tile and (Rules.units[u.kind].unitClass=="Civilian")== (Rules.units[item].unitClass=="Civilian") then occupied=true end end
            if not occupied then place(s,1,item,tile) end
        end
        city.queue=item; city.production=100
        local view=Game.snapshot(s,1)
        assert(view.cityForecasts[tostring(city.id)].productionBlocked=="NoSpace")
        assert(not table.find(view.availablePurchasesByCity[tostring(city.id)],item))
        reject(s,{kind="Purchase",cityId=city.id,item=item})
        roundtrip(s)
    end
    local s=fixture(shape); local city=s.cities[1]; place(s,1,"Worker",city.tileId)
    city.queue="Warrior"; city.production=100
    assert(Game.snapshot(s,1).cityForecasts[tostring(city.id)].productionTurns==1)
    local nextId=s.nextUnit; apply(s,1,{kind="EndTurn"})
    local found=false; for _,u in s.units do if u.id==nextId then found=u.tileId==city.tileId and u.kind=="Warrior" end end
    assert(found,"production stacks in city"); roundtrip(s)
end
-- Founding consumes only the Settler; upgrades keep the military slot and garrison ignores the civilian.
do
    local s,a=fixture(); local settler=place(s,1,"Settler",a); local soldier=place(s,1,"Warrior",a)
    apply(s,1,{kind="FoundCity",unitId=settler.id}); local city=s.cities[#s.cities]
    local function strength(): number
        for _,c in Game.snapshot(s,1).cities do if c.id==city.id then return c.strength :: number end end
        error("missing city")
    end
    local before=strength(); place(s,1,"Worker",a); assert(strength()==before)
    s.players[1].technologies={"Mining","BronzeWorking","IronWorking"}; s.players[1].gold=1000
    local iron=s.tiles[a]; iron.terrain="Hills"; iron.resource="Iron"; iron.improvement="Mine"
    apply(s,1,{kind="UpgradeUnit",unitId=soldier.id})
    assert(soldier.kind=="Swordsman" and soldier.tileId==a); roundtrip(s)
end
-- A city protects its lone civilian until city capture; a defeated garrison alone does not expose it to capture.
do
    local s,_,_,_,g=fixture(); local city=s.cities[2]; local victim=place(s,2,"Worker",city.tileId)
    local attacker=place(s,1,"Warrior",g.neighbors[city.tileId][1]); city.hp=1
    apply(s,1,{kind="DeclareWar",targetId=2})
    local p=Game.previewAttack(s,1,attacker.id,city.tileId); assert(p and p.target=="City" and p.capturesCivilian=="Yes")
    apply(s,1,{kind="MoveUnit",unitId=attacker.id,tileId=city.tileId})
    assert(city.ownerId==1 and victim.ownerId==1 and victim.hp==50); roundtrip(s)
end
do
    local s,_,_,_,g=fixture(); local city=s.cities[2]; local victim=place(s,2,"Worker",city.tileId)
    local guard=place(s,2,"Warrior",city.tileId); guard.hp=1
    local attacker=place(s,1,"Warrior",g.neighbors[city.tileId][1])
    apply(s,1,{kind="DeclareWar",targetId=2})
    local p=Game.previewAttack(s,1,attacker.id,city.tileId)
    assert(p and p.defenderDefeated=="Yes" and p.captures=="No" and p.capturesCivilian=="No")
    apply(s,1,{kind="MoveUnit",unitId=attacker.id,tileId=city.tileId})
    assert(city.ownerId==2 and city.hp==150 and victim.ownerId==2 and victim.hp==50 and attacker.tileId~=city.tileId)
    roundtrip(s)
end
print("G15 stacking: movement/transit, combat/capture, cities/spawn, projections and saves passed")
