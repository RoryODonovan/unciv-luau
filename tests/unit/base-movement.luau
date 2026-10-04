--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original fixtures for G3 movement: partial moves into costly terrain, the zone of control (same-enemy rule,
-- civilians, peace and war, fog), one-third road steps, move previews equal to applied moves and an independent
-- reference search, saves written before these rules and deterministic replays.
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
local function deep(value: any): any
    if type(value)~="table" then return value end
    local result={}; for k,v in value do result[k]=deep(v) end; return result
end
local function apply(s: any,owner: number,command: any)
    local result=Game.apply(s,owner,command); assert(result.ok,result.message)
end
local function rejected(s: any,owner: number,command: any)
    local before=deep(s)
    local result=Game.apply(s,owner,command); assert(not result.ok,"command should be rejected")
    assert(equal(before,s),"a rejected move changed the state")
end
local function firstUnit(s: any,owner: number,kind: string): any
    for _, u in s.units do if u.ownerId==owner and u.kind==kind then return u end end; error("missing "..kind)
end
local function unitById(s: any,id: number): any
    for _, u in s.units do if u.id==id then return u end end; return nil
end
-- Move previews for every owned unit, asked on demand: one previewMove per legal destination that is not an attack
-- target (snapshots carry only legalMoves). Every such destination must have a preview.
local function allPreviews(s: any,view: any): {[string]: {any}}
    local result: {[string]: {any}}={}
    for id,tiles in view.legalMoves do
        local attacks: {[number]: boolean}={}; for _, a in view.attackPreviews[id] do attacks[a.tileId]=true end
        local list={}
        for _, tileId in tiles do
            if attacks[tileId] then continue end
            local p=Game.previewMove(s,view.actorId,tonumber(id) :: number,tileId); assert(p,"a legal destination without a move preview")
            table.insert(list,p)
        end
        result[id]=list
    end
    return result
end
local function graphOf(s: any): any return WorldMap.fromTiles(s.tiles,s.radius) end
local function adjacent(g: any,a: number,b: number): boolean return table.find(g.neighbors[a],b)~=nil end

-- A two-human game on a large map with both capitals founded, every unit removed (cities keep both civilizations
-- alive) and a cleared arena: unowned Plains without roads in radius 4 around `center`, at least seven hexes from
-- each city so the cities see none of it. Player 1 is to move.
local function arena(seed: number): (any,number,any)
    local s: any=Game.new(seed,{humanPlayers=2,radius=12})
    -- These fixtures pin earlier rules on bare terrain: terrain features and rivers (G4) are removed from the whole map.
    for _, t in s.tiles do t.feature=nil; t.river=nil end
    apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id}); apply(s,1,{kind="EndTurn"})
    apply(s,2,{kind="FoundCity",unitId=firstUnit(s,2,"Settler").id}); apply(s,2,{kind="EndTurn"})
    s.units={}
    local g=graphOf(s)
    local ids: {number}={}; for _, t in s.tiles do table.insert(ids,t.id) end; table.sort(ids)
    for _, id in ids do
        local ring=WorldMap.range(g,id,4)
        if #ring~=61 then continue end
        local far=true; for _, c in s.cities do if WorldMap.distance(g,id,c.tileId)<7 then far=false end end
        if not far then continue end
        for _, t in ring do local tile=s.tiles[t]; tile.terrain="Plains"; tile.resource=nil; tile.improvement=nil; tile.road=nil; tile.ownerId=nil end
        return s,id,g
    end
    error("no arena")
end
local function place(s: any,owner: number,kind: string,tileId: number,moves: number?): any
    local u={id=s.nextUnit,ownerId=owner,kind=kind,tileId=tileId,hp=Rules.units[kind].hp,moves=moves or Rules.units[kind].moves,fortified=false,level=0}
    table.insert(s.units,u); s.nextUnit += 1; return u
end
local function placeCity(s: any,owner: number,tileId: number): any
    local c={id=s.nextCity,ownerId=owner,originalOwnerId=owner,capital=false,tileId=tileId,name="Fixture "..s.nextCity,population=1,food=0,production=0,queue="Warrior",hp=Rules.cityHp,buildings={},focus="Balanced"}
    table.insert(s.cities,c); s.nextCity += 1; s.tiles[tileId].ownerId=owner; return c
end
local function war(s: any) if s.diplomacy.status~="War" then apply(s,1,{kind="DeclareWar",targetId=2}) end end
local function preview(s: any,u: any,tileId: number): any
    local p,message=Game.previewMove(s,u.ownerId,u.id,tileId); assert(p,message); return p
end
-- Previews the move, applies it and checks the unit arrives with exactly the previewed movement.
local function move(s: any,u: any,tileId: number): any
    local p=preview(s,u,tileId)
    apply(s,u.ownerId,{kind="MoveUnit",unitId=u.id,tileId=tileId})
    assert(u.tileId==tileId and u.moves==p.movesLeft,"the applied move matches its preview")
    return p
end

-- Independent statement of the movement rules: a depth-first relaxation that keeps the most movement left on each
-- tile, in sixths. Steps cost the terrain's movement (or a third between two road tiles); a step that costs at least
-- what remains, or that goes between two tiles next to the same visible enemy military unit or city while at war
-- (military movers only), leaves no movement. Only visible, passable, unoccupied tiles outside enemy cities (and
-- outside foreign land at peace) may be entered.
local function reference(s: any,unit: any): {[number]: number}
    local g=graphOf(s); local seen: {[number]: boolean}={}
    for _, u in s.units do if u.ownerId==unit.ownerId then for _, id in WorldMap.range(g,u.tileId,2) do seen[id]=true end end end
    for _, c in s.cities do if c.ownerId==unit.ownerId then for _, id in WorldMap.range(g,c.tileId,2) do seen[id]=true end end end
    for _, tile in s.tiles do if tile.ownerId==unit.ownerId then
        seen[tile.id]=true; for _, id in g.neighbors[tile.id] do seen[id]=true end
    end end
    local unitAt: {[number]: any},cityAt: {[number]: any}={},{}
    for _, u in s.units do unitAt[u.tileId]=u end; for _, c in s.cities do cityAt[c.tileId]=c end
    local atWar=s.diplomacy.status=="War"; local military=Rules.units[unit.kind].strength>0
    local function source(id: number): boolean
        if not seen[id] then return false end
        local u,c=unitAt[id],cityAt[id]
        return (u~=nil and u.ownerId~=unit.ownerId and Rules.units[u.kind].strength>0) or (c~=nil and c.ownerId~=unit.ownerId)
    end
    local function enterable(id: number): boolean
        local t=s.tiles[id]
        if not seen[id] or not Rules.terrains[t.terrain].passable then return false end
        if unitAt[id]~=nil and unitAt[id]~=unit then return false end
        if cityAt[id]~=nil and cityAt[id].ownerId~=unit.ownerId then return false end
        if t.ownerId~=nil and t.ownerId~=unit.ownerId and not atWar then return false end
        return true
    end
    local start=math.round(unit.moves*6); local best: {[number]: number}={[unit.tileId]=start}
    local function walk(from: number,left: number)
        for _, to in g.neighbors[from] do
            if not enterable(to) then continue end
            local cost=if s.tiles[from].road and s.tiles[to].road then 2 else Rules.terrains[s.tiles[to].terrain].movement*6
            local zoc=false
            if military and atWar then for _, n in g.neighbors[to] do if adjacent(g,from,n) and source(n) then zoc=true end end end
            local after=if zoc or cost>=left then 0 else left-cost
            if best[to]==nil or after>best[to] then best[to]=after; if after>0 then walk(to,after) end end
        end
    end
    if start>0 then walk(unit.tileId,start) end
    best[unit.tileId]=nil
    return best
end
-- Checks every move preview of one unit against the reference, the path rules, previewMove and the applied result.
local function verifyUnit(s: any,view: any,u: any,g: any): (number,number,number)
    local expected=reference(s,u); local previews=allPreviews(s,view)[tostring(u.id)]
    local listed: {[number]: boolean}={}; local count,controlled,exhausted=0,0,0
    for _, p in previews do
        listed[p.tileId]=true; count += 1
        if p.zoneOfControl then controlled += 1 end
        if not p.zoneOfControl and p.movesLeft==0 and p.movesSpent<Rules.units[u.kind].moves and p.movesSpent==u.moves then exhausted += 1 end
        assert(expected[p.tileId]~=nil,"a previewed destination the rules do not allow")
        assert(p.movesLeft==expected[p.tileId]/6,"movement left differs from the reference")
        assert(p.unitId==u.id and p.endsMovement==(p.movesLeft==0) and math.abs(p.movesSpent+p.movesLeft-u.moves)<1e-9)
        assert(not p.zoneOfControl or p.movesLeft==0,"the zone of control always ends movement")
        assert(p.path[1]==u.tileId and p.path[#p.path]==p.tileId)
        for i=2,#p.path do assert(adjacent(g,p.path[i-1],p.path[i]),"path steps are adjacent") end
        local clone=deep(s); local mover=unitById(clone,u.id)
        apply(clone,1,{kind="MoveUnit",unitId=u.id,tileId=p.tileId})
        assert(mover.tileId==p.tileId and mover.moves==p.movesLeft,"applied move equals its preview")
    end
    for tileId in expected do assert(listed[tileId],"a destination the rules allow is missing") end
    -- Legal moves are the previewed destinations plus attack targets, which are never move destinations.
    local attacks: {[number]: boolean}={}
    for _, a in view.attackPreviews[tostring(u.id)] do attacks[a.tileId]=true; assert(not listed[a.tileId]) end
    for _, tileId in view.legalMoves[tostring(u.id)] do assert(listed[tileId] or attacks[tileId]) end
    assert(#view.legalMoves[tostring(u.id)]==count+#view.attackPreviews[tostring(u.id)])
    -- Anything else nearby is rejected without changing the state.
    for _, tileId in WorldMap.range(g,u.tileId,4) do
        if not listed[tileId] and not attacks[tileId] then
            assert(Game.previewMove(s,1,u.id,tileId)==nil)
            if tileId%7==0 then rejected(s,1,{kind="MoveUnit",unitId=u.id,tileId=tileId}) end
        end
    end
    return count,controlled,exhausted
end

-- 0. Rules: a road step is a third of a move; Hills and Forest cost two; the generic map cost is unchanged.
assert(Rules.roadMovement==1/3 and Game.getRules().roadMovement==1/3)
assert(Rules.terrains.Hills.movement==2 and Rules.terrains.Forest.movement==2 and Rules.terrains.Plains.movement==1)
assert(WorldMap.movementCost({id=1,terrain="Hills",road=true})==1,"WorldMap's per-tile default still charges one on roads")

-- 1. Partial moves: any movement left lets a unit enter an adjacent allowed tile; a costlier step ends movement.
do
    local s,c,g=arena(301)
    local n=g.neighbors[c]; table.sort(n)
    s.tiles[n[1]].terrain="Hills"; s.tiles[n[2]].terrain="Forest"
    local warrior=place(s,1,"Warrior",c,1)
    local p=move(s,warrior,n[1]); assert(p.movesLeft==0 and p.endsMovement and not p.zoneOfControl and p.movesSpent==1)
    -- With full movement: one Plains step, then Hills with one move left (cost two) still enters and ends movement.
    local s2,c2,g2=arena(302)
    local ring=g2.neighbors[c2]; table.sort(ring)
    local outer: number?=nil
    for _, id in g2.neighbors[ring[1]] do if WorldMap.distance(g2,id,c2)==2 then outer=id; break end end
    assert(outer); s2.tiles[outer :: number].terrain="Hills"
    for _, id in g2.neighbors[c2] do if id~=ring[1] then s2.tiles[id].terrain="Hills" end end
    local w2=place(s2,1,"Warrior",c2)
    local q=preview(s2,w2,outer :: number); assert(q.movesLeft==0 and q.movesSpent==2 and #q.path==3 and q.path[2]==ring[1])
    -- A tile three steps away is out of reach: the Hills step left no movement.
    for _, id in WorldMap.range(g2,c2,4) do if WorldMap.distance(g2,id,c2)==3 then assert(Game.previewMove(s2,1,w2.id,id)==nil) end end
    move(s2,w2,outer :: number); assert(w2.moves==0)
    -- No movement: no preview and the move is rejected.
    rejected(s2,1,{kind="MoveUnit",unitId=w2.id,tileId=g2.neighbors[outer :: number][1]})
    -- A third of a move (left after road steps) still enters Forest; a worker with one move enters Hills.
    local s3,c3,g3=arena(303)
    local m=g3.neighbors[c3]; table.sort(m)
    s3.tiles[m[1]].terrain="Forest"; s3.tiles[m[2]].terrain="Hills"
    local third=place(s3,1,"Warrior",c3,1/3); local wp=move(s3,third,m[1]); assert(wp.movesLeft==0 and math.abs(wp.movesSpent-1/3)<1e-12)
    local worker=place(s3,1,"Worker",m[3],1)
    local rough: number?=nil
    for _, id in g3.neighbors[m[3]] do if WorldMap.distance(g3,id,c3)==2 then rough=id; break end end
    s3.tiles[rough :: number].terrain="Hills"
    local wk=move(s3,worker,rough :: number); assert(worker.moves==0 and wk.movesSpent==1 and not wk.zoneOfControl)
end

-- 2. Zone of control.
do
    -- Start next to an enemy warrior, then step along the front: all movement is spent. Stepping away costs one.
    local s,c,g=arena(311); war(s)
    place(s,2,"Warrior",c)
    local ring=g.neighbors[c]; table.sort(ring)
    local a=ring[1]; local b: number?=nil; local away: number?=nil
    for _, id in g.neighbors[a] do
        if id~=c and adjacent(g,id,c) and not b then b=id end
        if WorldMap.distance(g,id,c)==2 and not away then away=id end
    end
    assert(b and away)
    local mover=place(s,1,"Warrior",a)
    local front0=preview(s,mover,b :: number); assert(front0.zoneOfControl and front0.movesLeft==0 and front0.movesSpent==2)
    local out=preview(s,mover,away :: number); assert(not out.zoneOfControl and out.movesLeft==1)
    move(s,mover,b :: number); assert(mover.moves==0)
    -- Approaching from outside is free: the first step into contact costs its terrain, the next step along the
    -- front spends the rest.
    local s2,c2,g2=arena(312); war(s2)
    place(s2,2,"Warrior",c2)
    local r2=g2.neighbors[c2]; table.sort(r2)
    local front=r2[1]; local behind: number?=nil
    for _, id in g2.neighbors[front] do if WorldMap.distance(g2,id,c2)==2 then behind=id; break end end
    local scout=place(s2,1,"Scout",behind :: number)
    local enter=move(s2,scout,front); assert(not enter.zoneOfControl and enter.movesLeft==2)
    local next: number?=nil; for _, id in g2.neighbors[front] do if id~=c2 and adjacent(g2,id,c2) then next=id; break end end
    local stop=move(s2,scout,next :: number); assert(stop.zoneOfControl and stop.movesLeft==0,"scouts obey the zone of control")
    -- One search: two steps (approach, then along the front) arrive with no movement left.
    local s3,c3,g3=arena(313); war(s3)
    place(s3,2,"Warrior",c3)
    local r3=g3.neighbors[c3]; table.sort(r3)
    local f1=r3[1]; local start: number?=nil; local f2: number?=nil
    for _, id in g3.neighbors[f1] do if id~=c3 and adjacent(g3,id,c3) and not f2 then f2=id end end
    for _, id in g3.neighbors[f1] do if WorldMap.distance(g3,id,c3)==2 and not adjacent(g3,id,f2 :: number) and not start then start=id end end
    assert(start and f2)
    -- Hills elsewhere force the cheapest route to f2 through f1 (the other approaches stay costlier).
    for _, id in WorldMap.range(g3,c3,3) do if id~=c3 and id~=f1 and id~=f2 and id~=start then s3.tiles[id].terrain="Hills" end end
    local knight=place(s3,1,"Knight",start :: number)
    local p3=preview(s3,knight,f2 :: number); assert(p3.zoneOfControl and p3.movesLeft==0 and p3.path[2]==f1 and p3.movesSpent==3)
    -- Two different enemies, each next to only one end of the step: no zone of control (same-enemy rule).
    local s4,c4,g4=arena(314); war(s4)
    local found=false
    local r4=g4.neighbors[c4]; table.sort(r4)
    for _, from in r4 do
        for _, to in g4.neighbors[from] do
            if to==c4 or adjacent(g4,to,c4) then continue end
            for _, second in g4.neighbors[to] do
                if second==from or adjacent(g4,second,from) or adjacent(g4,second,c4) or second==c4 then continue end
                place(s4,2,"Warrior",c4); place(s4,2,"Warrior",second); local w=place(s4,1,"Warrior",from)
                local p4=preview(s4,w,to); assert(not p4.zoneOfControl and p4.movesLeft==1,"different enemies do not combine")
                found=true; break
            end
            if found then break end
        end
        if found then break end
    end
    assert(found)
    -- Enemy cities and ranged units exert a zone of control; enemy civilians do not; own civilians ignore it.
    local function along(kind: string?,city: boolean,moverKind: string,status: string): any
        local t,center,graph=arena(315)
        if status=="War" then war(t) end
        if city then placeCity(t,2,center); for _, id in graph.neighbors[center] do t.tiles[id].ownerId=nil end end
        if kind then place(t,2,kind,center) end
        local r=graph.neighbors[center]; table.sort(r)
        local from=r[1]; local to: number?=nil
        for _, id in graph.neighbors[from] do if id~=center and adjacent(graph,id,center) then to=id; break end end
        local u=place(t,1,moverKind,from)
        return preview(t,u,to :: number)
    end
    assert(along(nil,true,"Warrior","War").zoneOfControl,"an enemy city exerts a zone of control")
    assert(along("Archer",false,"Warrior","War").zoneOfControl,"a ranged unit exerts a zone of control")
    assert(along("Warrior",false,"Archer","War").zoneOfControl,"a ranged unit obeys the zone of control")
    local civilian=along("Worker",false,"Warrior","War"); assert(not civilian.zoneOfControl and civilian.movesLeft==1,"enemy civilians exert none")
    local settler=along("Settler",false,"Warrior","War"); assert(not settler.zoneOfControl and settler.movesLeft==1)
    local worker=along("Warrior",false,"Worker","War"); assert(not worker.zoneOfControl and worker.movesLeft==1,"civilians ignore it")
    local peace=along("Warrior",false,"Warrior","Peace"); assert(not peace.zoneOfControl and peace.movesLeft==1,"only enemies at war exert it")
    local peaceCity=along(nil,true,"Warrior","Peace"); assert(not peaceCity.zoneOfControl and peaceCity.movesLeft==1)
    -- Fog: an enemy outside the mover's sight exerts no zone of control, so previews and results never reveal it.
    -- The scout sees two hexes; the hidden warrior is three away, next to two adjacent visible tiles t1 and t2. A road
    -- c5-x-t1-t2 is the only cheap route to t2 (every other nearby tile is Hills), so a zone of control on the step
    -- t1-t2 would change t2's preview from two moves left to none.
    local s5,c5,g5=arena(316); war(s5)
    local hidden: number?=nil; local t1: number?=nil; local t2: number?=nil; local x: number?=nil
    for _, h in WorldMap.range(g5,c5,3) do
        if WorldMap.distance(g5,h,c5)~=3 or hidden then continue end
        for _, ea in g5.neighbors[h] do
            for _, eb in g5.neighbors[h] do
                if hidden or ea==eb or WorldMap.distance(g5,ea,c5)~=2 or WorldMap.distance(g5,eb,c5)~=2 or not adjacent(g5,ea,eb) then continue end
                for _, m in g5.neighbors[c5] do
                    if adjacent(g5,m,ea) and not adjacent(g5,m,eb) then hidden=h; t1=ea; t2=eb; x=m; break end
                end
            end
        end
    end
    assert(hidden and t1 and t2 and x)
    for _, id in WorldMap.range(g5,c5,2) do s5.tiles[id].terrain="Hills" end
    for _, id in {c5,x :: number,t1 :: number,t2 :: number} do s5.tiles[id].terrain="Plains"; s5.tiles[id].road=true end
    local scout5=place(s5,1,"Scout",c5)
    local without=Game.snapshot(s5,1); local withoutPreviews=allPreviews(s5,without)
    local foe=place(s5,2,"Warrior",hidden :: number)
    local with=Game.snapshot(s5,1)
    for _, u in with.units do assert(u.id~=foe.id,"the enemy is hidden") end
    assert(equal(withoutPreviews,allPreviews(s5,with)) and equal(without.legalMoves,with.legalMoves),"a hidden enemy changes no move")
    local unseen=preview(s5,scout5,t2 :: number)
    assert(not unseen.zoneOfControl and unseen.movesLeft==2 and equal(unseen.path,{c5,x,t1,t2}),"no zone of control from a hidden enemy")
    -- Moving next to it reveals it; from then on it applies.
    local reach=move(s5,scout5,t1 :: number); assert(not reach.zoneOfControl and reach.movesLeft==14/6)
    local seen=false; for _, u in Game.snapshot(s5,1).units do if u.id==foe.id then seen=true end end; assert(seen)
    local blocked=preview(s5,scout5,t2 :: number); assert(blocked.zoneOfControl and blocked.movesLeft==0)
end

-- 3. Roads: a third of a move between two road tiles, whatever the terrain; terrain cost on and off the network.
do
    local s,c,g=arena(321)
    local ring=g.neighbors[c]; table.sort(ring)
    -- Order the six neighbours of `c` as a cycle and pave it; one stretch is Hills.
    local cycle={ring[1]}
    while #cycle<6 do
        local last=cycle[#cycle]
        for _, id in ring do if not table.find(cycle,id) and adjacent(g,last,id) then table.insert(cycle,id); break end end
    end
    for _, id in cycle do s.tiles[id].road=true end
    s.tiles[cycle[3]].terrain="Hills"; s.tiles[cycle[4]].terrain="Forest"
    local warrior=place(s,1,"Warrior",cycle[1])
    assert(preview(s,warrior,cycle[2]).movesLeft==10/6)
    assert(preview(s,warrior,cycle[3]).movesLeft==8/6,"Hills on a road cost a third")
    assert(preview(s,warrior,cycle[4]).movesLeft==1,"three road steps cost one move")
    -- The centre has no road: entering it costs its terrain (one), not a third.
    assert(preview(s,warrior,c).movesLeft==1 and preview(s,warrior,c).path[2]==c)
    -- Off the network from a road tile costs the terrain.
    local outside: number?=nil
    for _, id in g.neighbors[cycle[1]] do if WorldMap.distance(g,id,c)==2 then outside=id; break end end
    assert(preview(s,warrior,outside :: number).movesLeft==1)
    -- Step by step: each third is exact.
    move(s,warrior,cycle[2]); assert(warrior.moves==10/6)
    move(s,warrior,cycle[3]); assert(warrior.moves==8/6)
    move(s,warrior,cycle[4]); assert(warrior.moves==1)
    local saved=Game.serialize(s); assert(Save.valid(saved))
    -- The remaining move: three more road steps would cost exactly one; a non-road Hills tile ends movement.
    move(s,warrior,cycle[5]); assert(warrior.moves==4/6)
    local thirds=Game.serialize(s); assert(Save.valid(thirds) and thirds.state.units[1].moves==4/6)
    local back=Game.restore(thirds); assert(back and equal(Game.serialize(back),thirds),"a save holding thirds restores exactly")
    -- A road into a Hills tile without a road is a plain Hills step: partial, so movement ends.
    local hill: number?=nil
    for _, id in g.neighbors[cycle[5]] do if WorldMap.distance(g,id,c)==2 then hill=id; break end end
    s.tiles[hill :: number].terrain="Hills"
    local p=move(s,warrior,hill :: number); assert(p.movesLeft==0 and math.abs(p.movesSpent-4/6)<1e-12)
    -- Long road: a two-move unit makes six road steps.
    local s2,c2,g2=arena(322)
    local line={c2}
    for _=1,4 do
        local last=line[#line]
        for _, id in g2.neighbors[last] do
            if WorldMap.distance(g2,id,c2)==#line and not table.find(line,id) then table.insert(line,id); break end
        end
    end
    assert(#line==5)
    for _, id in line do s2.tiles[id].road=true end
    -- Keep the far end visible with a second unit next to it.
    local far=line[5]; local spot: number?=nil
    for _, id in g2.neighbors[far] do if not table.find(line,id) then spot=id; break end end
    place(s2,1,"Worker",spot :: number,0)
    local runner=place(s2,1,"Warrior",line[1])
    local p2=move(s2,runner,line[5]); assert(p2.movesLeft==4/6 and #p2.path==5)
end

-- 4. Legal moves equal applied results and an independent reference across random terrain, roads, territory,
-- enemies, cities, war and peace; hidden enemies never change a preview.
do
    local checked,controlled,exhausted,hiddenEnemies=0,0,0,0
    for scenario=1,36 do
        local s,c,g=arena(400+scenario%4)
        local state=scenario*7919
        local function rand(n: number): number state=(state*1103515245+12345)%2147483648; return state%n+1 end
        if scenario%3~=0 then war(s) end
        local area=WorldMap.range(g,c,4)
        local terrains={"Plains","Plains","Grassland","Hills","Forest","Desert","Tundra","Hills","Mountain","Water"}
        for _, id in area do
            local t=s.tiles[id]; t.terrain=terrains[rand(#terrains)]
            t.road=if Rules.terrains[t.terrain].passable and rand(5)<=2 then true else nil
            t.ownerId=if rand(9)==1 then 2 elseif rand(12)==1 then 1 else nil
        end
        -- Own units start within two hexes of the centre, enemies within three, so fronts are common.
        local used: {[number]: boolean}={}
        local function take(reach: number): number?
            local free: {number}={}
            for _, id in WorldMap.range(g,c,reach) do if not used[id] and Rules.terrains[s.tiles[id].terrain].passable then table.insert(free,id) end end
            if #free==0 then return nil end
            table.sort(free); local id=free[rand(#free)]; used[id]=true; return id
        end
        local own={}
        for _=1,rand(3) do
            local id=take(2); local kinds={"Warrior","Scout","Worker","Knight","Archer","Settler","Warrior","Knight"}
            if id then
                local kind=kinds[rand(#kinds)]; local full=Rules.units[kind].moves
                local options={0,1/3,2/3,1,7/6,1.5,full,full,full}
                table.insert(own,place(s,1,kind,id,math.min(full,options[rand(#options)])))
            end
        end
        if rand(3)==1 then local id=take(3); if id then placeCity(s,2,id) end end
        for _=1,1+rand(4) do
            local id=take(3); local kinds={"Warrior","Archer","Worker","Settler","Scout","Warrior"}
            if id then place(s,2,kinds[rand(#kinds)],id) end
        end
        -- Territory sight reveals more of the random front; retain a genuinely unseen enemy for fog coverage.
        local sight=Game.snapshot(s,1); local hidden=false
        for _, id in WorldMap.range(g,c,6) do
            if sight.tiles[id].visible or used[id] or not Rules.terrains[s.tiles[id].terrain].passable then continue end
            local city=false; for _, town in s.cities do if town.tileId==id then city=true end end
            if not city then place(s,2,"Warrior",id); hidden=true; break end
        end
        assert(hidden,"unseen enemy fixture")
        local view=Game.snapshot(s,1)
        for _, u in own do local a,b,c2=verifyUnit(s,view,u,g); checked += a; controlled += b; exhausted += c2 end
        -- Removing every enemy unit player 1 cannot see changes nothing it is shown.
        local hiddenless=deep(s); local seenTiles: {[number]: boolean}={}
        for _, t in view.tiles do if t.visible then seenTiles[t.id]=true end end
        for i=#hiddenless.units,1,-1 do local u=hiddenless.units[i]; if u.ownerId==2 and not seenTiles[u.tileId] then table.remove(hiddenless.units,i); hiddenEnemies += 1 end end
        local other=Game.snapshot(hiddenless,1)
        assert(equal(allPreviews(s,view),allPreviews(hiddenless,other)) and equal(view.legalMoves,other.legalMoves),"hidden enemies change no move")
    end
    assert(checked>=150 and controlled>=10 and exhausted>=10 and hiddenEnemies>=5,"coverage: "..checked.." destinations, "..controlled.." zone of control, "..exhausted.." exhausted, "..hiddenEnemies.." hidden enemies")
    print(string.format("  random scenarios: %d destinations, %d ended by the zone of control, %d others spending all movement, %d hidden enemies",checked,controlled,exhausted,hiddenEnemies))
end

-- 5. Saves written before these rules restore unchanged (whole and half moves) and then move under them.
do
    local map=WorldMap.generate(124,3)
    -- A save written before G4 has no features or rivers.
    for _, t in map.tiles do t.feature=nil; t.river=nil end
    local function at(x: number,y: number): number return WorldMap.tileId(map,x,y) :: number end
    local hub,west,east,rival=at(0,0),at(-2,0),at(1,0),at(3,0)
    local path={at(-2,1),at(-1,1),at(0,1)}
    for _, id in {hub,west,east,rival,path[1],path[2],path[3]} do local t=map.tiles[id]; t.terrain="Plains"; t.resource=nil; t.improvement=nil; t.road=nil; t.ownerId=nil end
    map.tiles[west].road=true; for _, id in path do map.tiles[id].road=true end; map.tiles[path[2]].terrain="Hills"
    map.tiles[hub].ownerId=1
    local explored={}; for id=1,#map.tiles do table.insert(explored,id) end
    local legacyState: any={seed=124,radius=3,difficulty="Normal",humanPlayers=2,forest=false,maxTurns=120,turn=5,revision=9,activePlayerId=1,phase="Playing",tiles=map.tiles,
        units={{id=1,ownerId=1,kind="Warrior",tileId=west,hp=100,moves=1.5,fortified=false,level=0},
            {id=2,ownerId=1,kind="Worker",tileId=east,hp=50,moves=2,fortified=false,level=0},
            {id=3,ownerId=2,kind="Settler",tileId=rival,hp=50,moves=2,fortified=false,level=0}},
        cities={{id=1,ownerId=1,originalOwnerId=1,capital=true,tileId=hub,name="Fixture",population=2,food=0,production=0,queue="Warrior",hp=150,buildings={},focus="Balanced"}},players={},
        diplomacy={status="Peace",peaceUntil=0},trades={},events={},nextEvent=1,nextUnit=4,nextCity=2,nextTrade=1,log={}}
    for id=1,2 do table.insert(legacyState.players,{id=id,human=true,gold=50,science=0,culture=0,happiness=9,technologies={},policies={},explored=table.clone(explored),resources={},income={food=0,production=0,gold=0,science=0,culture=0,maintenance=0}}) end
    local legacy={format="unciv-luau-base",version=1,state=legacyState}
    -- The pre-G3 validator accepted whole and half moves (moves*2 an integer); this fixture satisfies it.
    for _, u in legacyState.units do assert(u.moves*2%1==0) end
    assert(Save.valid(legacy),"a pre-G3 save stays valid")
    local before=deep(legacy)
    local restored: any,err=Game.restore(legacy); assert(restored and err==nil,err)
    local prior=Game.serialize(restored); prior.state.diplomacy.met=nil
    for _, c in prior.state.cities do
        assert(c.borderCulture==0 and c.borderTiles==0,"legacy fixture has no post-founding borders")
        c.borderCulture=nil; c.borderTiles=nil
    end
    if prior.state.events[#prior.state.events] and prior.state.events[#prior.state.events].kind=="Contact" then
        table.remove(prior.state.events); prior.state.nextEvent-=1
    end
    assert(equal(legacy,before),"restore does not modify the save it reads")
    assert(equal(prior,legacy),"restore preserves pre-contact fields while migrating contact")
    -- Half a move plus thirds: 1.5 - 1/3 - 1/3 = 5/6 along the road (the Hills road tile costs a third).
    local w=unitById(restored,1)
    move(restored,w,path[1]); assert(w.moves==7/6)
    move(restored,w,path[2]); assert(w.moves==5/6)
    -- The resulting sixths are valid and restore exactly.
    local after=Game.serialize(restored); assert(Save.valid(after))
    assert(equal(Game.serialize(Game.restore(after) :: any),after))
    -- Shortened encodings (six decimal places) are within 1e-6 of a move of a sixth: valid, and both restore paths
    -- snap them to the exact sixth.
    for _, case in {{0.333333,1/3},{0.666667,2/3},{1.666667,10/6}} do
        local short=deep(legacy); short.state.units[1].moves=case[1]; assert(Save.valid(short),"shortened moves "..case[1])
        local viaSave: any=Save.restore(short); local viaGame: any=Game.restore(short)
        assert(viaSave.units[1].moves==case[2] and unitById(viaGame,1).moves==case[2],"restore snaps "..case[1])
    end
    -- A negligible remainder restores as exactly no movement through either path, so the unit cannot fortify.
    local tiny=deep(legacy); tiny.state.units[1].moves=1e-16; assert(Save.valid(tiny))
    local tinySave: any=Save.restore(tiny); assert(tinySave.units[1].moves==0)
    rejected(tinySave,1,{kind="FortifyUnit",unitId=1})
    local tinyGame: any=Game.restore(tiny); assert(unitById(tinyGame,1).moves==0)
    rejected(tinyGame,1,{kind="FortifyUnit",unitId=1})
    assert(equal(Game.restore(legacy),Save.restore(legacy)),"both restore paths give the same state")
    -- Validation: multiples of a sixth within range pass; other fractions and out-of-range values fail.
    local function withMoves(value: number): boolean local copy=deep(legacy); copy.state.units[1].moves=value; return Save.valid(copy) end
    for _, value in {0,1/6,1/3,0.5,2/3,5/6,1,7/6,1.5,2} do assert(withMoves(value),"valid moves "..value) end
    for _, value in {0.25,0.1,0.4,2+1/3,-1/3,0/0} do assert(not withMoves(value),"invalid moves "..tostring(value)) end
    -- A third shortened by a host's encoding still validates and restores to the exact third.
    local shortened=deep(legacy); shortened.state.units[1].moves=0.3333333
    assert(Save.valid(shortened)); local snapped: any=Game.restore(shortened); assert(unitById(snapped,1).moves==1/3)
    assert(shortened.state.units[1].moves==0.3333333,"the save itself is untouched")
end

-- 6. Determinism: identical solo wars (the human marching along fronts, the AI moving under the same rules)
-- replay identically, with or without restoring saves between turns.
do
    local function run(resume: boolean): any
        local s: any=Game.new(77,{humanPlayers=1,radius=5,difficulty="Hard"})
        apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id})
        for turn=1,40 do
            if s.phase~="Playing" then break end
            if turn==2 and s.diplomacy.status~="War" then apply(s,1,{kind="DeclareWar",targetId=2}) end
            local view=Game.snapshot(s,1); local ids={}
            for id in view.legalMoves do table.insert(ids,tonumber(id) :: number) end; table.sort(ids)
            for _, id in ids do
                local choices=allPreviews(s,view)[tostring(id)]
                if #choices>0 then
                    -- Prefer a move the zone of control ends, else the farthest-numbered tile.
                    local pick=choices[#choices]; for _, p in choices do if p.zoneOfControl then pick=p end end
                    apply(s,1,{kind="MoveUnit",unitId=id,tileId=pick.tileId})
                    if s.phase~="Playing" then break end
                    view=Game.snapshot(s,1)
                end
            end
            if s.phase~="Playing" then break end
            apply(s,1,{kind="EndTurn"})
            if resume then s=Game.restore(Game.serialize(s)) end
        end
        return Game.serialize(s)
    end
    local first=run(false)
    assert(equal(first,run(false)) and equal(first,run(true)),"movement is deterministic")
    for _, u in first.state.units do assert(math.abs(u.moves*6-math.round(u.moves*6))<1e-9) end
end

-- 7. Scale: a paved Huge sphere at the unit cap. Every passable tile has a road and 169 scouts spread over the globe
-- give the largest move searches. Snapshots carry only legalMoves (no per-destination previews), so their size and
-- time stay bounded; the search is linear in the tiles it reaches. Bounds are generous for slow machines.
do
    local function bytes(v: any): number
        local t=type(v)
        if t=="number" then return #tostring(v) elseif t=="string" then return #v+2 elseif t=="boolean" then return if v then 4 else 5 end
        if t=="table" then local n=2; for k,c in v do n += (if type(k)=="string" then #k+3 else #tostring(k)+1)+bytes(c)+1 end; return n end
        return 4
    end
    local s: any=Game.new(5,{mapShape="Sphere",frequency=22,humanPlayers=2})
    local occupied={}; for _, u in s.units do occupied[u.tileId]=true end; for _, c in s.cities do occupied[c.tileId]=true end
    for _, t in s.tiles do if Rules.terrains[t.terrain].passable then t.road=true end end
    local passable={}; for _, t in s.tiles do if Rules.terrains[t.terrain].passable and not occupied[t.id] then table.insert(passable,t) end end
    local stride=math.max(1,math.floor(#passable/(Rules.maxUnits-#s.units)))
    for i, t in passable do
        if #s.units>=Rules.maxUnits then break end
        if (i-1)%stride==0 then place(s,1,"Scout",t.id) end
    end
    assert(#s.units==Rules.maxUnits)
    local started=os.clock(); local view: any=Game.snapshot(s,1); local elapsed=os.clock()-started
    local legal=0; for _, list in view.legalMoves do legal += #list end
    local size=bytes(view)
    assert(view.movePreviews==nil,"snapshots carry no per-destination move previews")
    assert(legal>10000,"the paved globe gives large searches: "..legal)
    assert(size<1500000,"snapshot size "..size)
    assert(elapsed<1.5,"snapshot time "..elapsed)
    -- On-demand previews for one scout's whole reach stay cheap too.
    local scout=s.units[#s.units]; local first=os.clock(); local count=0
    for _, tileId in view.legalMoves[tostring(scout.id)] do assert(Game.previewMove(s,1,scout.id,tileId)); count += 1 end
    assert(count>0 and os.clock()-first<1.5)
    print(string.format("  paved Huge sphere, %d units: snapshot %.0f ms, about %.2f MB, %d legal moves",#s.units,elapsed*1000,size/1e6,legal))
end

print("base movement: partial moves, zone of control (same enemy, cities, civilians, peace, fog), one-third roads, previews equal applied moves and a reference search, pre-G3 saves, shortened and negligible saved moves, determinism and Huge-map scale passed")
