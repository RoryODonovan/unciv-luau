--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original fixtures for G4 terrain features and rivers: the rules, deterministic generation with symmetric river edges
-- (hex boards and the sphere, pentagons included) that reach water, yields, movement costs and river crossings whose
-- previews equal applied moves and an independent reference search, feature defence and the river attack penalty in
-- exact previews, improvements and city founding on features, fog, saves written before features and rivers, save
-- validation, deterministic AI replays and the Huge-map snapshot payload.
local Game = require("../../src/simulation/BaseGame")
local Save = require("../../src/simulation/BaseSave")
local WorldMap = require("../../src/simulation/WorldMap")
local Rules = require("../../src/simulation/BaseRules")
local Sphere = require("../../src/map/SphereTopology")
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
    assert(equal(before,s),"a rejected command changed the state")
end
local function firstUnit(s: any,owner: number,kind: string): any
    for _, u in s.units do if u.ownerId==owner and u.kind==kind then return u end end; error("missing "..kind)
end
local function unitById(s: any,id: number): any
    for _, u in s.units do if u.id==id then return u end end; return nil
end
local function graphOf(s: any): any
    return if s.mapShape=="Sphere" then WorldMap.fromSphereTiles(s.tiles,s.frequency) else WorldMap.fromTiles(s.tiles,s.radius)
end
local function adjacent(g: any,a: number,b: number): boolean return table.find(g.neighbors[a],b)~=nil end
local function passable(tile: any): boolean return Rules.terrains[tile.terrain].passable end
-- Marks (or clears) the river on the edge between adjacent tiles a and b, on both sides.
local function setRiver(s: any,g: any,a: number,b: number,on: boolean)
    for _, pair in {{a,b},{b,a}} do
        local x,y=pair[1],pair[2]
        local index=table.find(g.neighbors[x],y); assert(index,"a river edge joins adjacent tiles")
        local bit=bit32.lshift(1,index-1); local mask=s.tiles[x].river or 0
        mask=if on then bit32.bor(mask,bit) else bit32.band(mask,bit32.bnot(bit))
        s.tiles[x].river=if mask==0 then nil else mask
    end
end
local function strip(s: any) for _, t in s.tiles do t.feature=nil; t.river=nil end end
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
local function move(s: any,u: any,tileId: number): any
    local p=preview(s,u,tileId)
    apply(s,u.ownerId,{kind="MoveUnit",unitId=u.id,tileId=tileId})
    assert(u.tileId==tileId and u.moves==p.movesLeft,"the applied move matches its preview")
    return p
end
-- Checks the snapshot's riverMoves for one actor: for each of its units, exactly the legal destinations whose on-demand
-- preview reports riverCrossing, ascending, under the unit's id only when there are any; every listed tile is a legal
-- move; no other unit (a rival's) has an entry; nothing while the actor cannot act. Returns the number listed.
local function checkRiverMoves(s: any,actor: number,view: any?): number
    local v=view or Game.snapshot(s,actor); local listed=0
    for id,list in v.riverMoves do
        local u=unitById(s,tonumber(id) :: number); assert(u and u.ownerId==actor and v.canAct,"riverMoves lists only the actor's units while it can act")
        assert(#list>0,"a unit without river moves has no entry")
        for i=2,#list do assert(list[i-1]<list[i],"ascending tile ids") end
        for _, tileId in list do assert(table.find(v.legalMoves[id],tileId),"a river move is a legal move") end
    end
    for id,tiles in v.legalMoves do
        local expected={}
        for _, tileId in tiles do
            local p=Game.previewMove(s,actor,tonumber(id) :: number,tileId)
            if p and p.riverCrossing then table.insert(expected,tileId) end
        end
        table.sort(expected)
        if #expected==0 then assert(v.riverMoves[id]==nil) else assert(equal(v.riverMoves[id],expected),"riverMoves equals the previews' riverCrossing"); listed += #expected end
    end
    return listed
end
-- A two-human game on a radius-12 map with both capitals founded, features and rivers removed, every unit removed and a
-- cleared arena: unowned Plains without roads in radius 4 around `center`, at least seven hexes from each city.
local function arena(seed: number): (any,number,any)
    local s: any=Game.new(seed,{humanPlayers=2,radius=12})
    strip(s)
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
local function sorted(list: {number}): {number} local copy=table.clone(list); table.sort(copy); return copy end

-- 0. Rules: Civ V-flavoured feature values, the river values, and the legacy Forest terrain unchanged.
do
    local F=Rules.features
    assert(equal(Rules.featureOrder,{"Forest","Jungle","Marsh","Oasis"}))
    assert(F.Forest.movement==2 and F.Forest.defensePercent==25 and F.Forest.rough and F.Forest.overrideYields and F.Forest.yields.food==1 and F.Forest.yields.production==2)
    assert(equal(F.Forest.terrains,{"Plains","Grassland","Tundra"}) and equal(F.Forest.improvements,{"Camp","Plantation"}))
    assert(F.Jungle.movement==2 and F.Jungle.defensePercent==25 and F.Jungle.rough and F.Jungle.overrideYields and F.Jungle.yields.food==2 and F.Jungle.yields.production==0)
    assert(equal(F.Jungle.terrains,{"Plains","Grassland"}) and equal(F.Jungle.improvements,{"Plantation"}))
    assert(F.Marsh.movement==2 and F.Marsh.defensePercent==-15 and F.Marsh.rough and not F.Marsh.overrideYields and F.Marsh.yields.food==-1)
    assert(equal(F.Marsh.terrains,{"Grassland"}) and #F.Marsh.improvements==0)
    assert(F.Oasis.movement==1 and F.Oasis.defensePercent==-10 and not F.Oasis.rough and F.Oasis.overrideYields and F.Oasis.yields.food==3 and F.Oasis.yields.gold==1)
    assert(equal(F.Oasis.terrains,{"Desert"}) and #F.Oasis.improvements==0)
    assert(Rules.riverGold==1 and Rules.riverFarmFood==1 and Rules.riverAttackPercent==20)
    assert(table.isfrozen(F) and table.isfrozen(F.Forest.terrains))
    local copy=Game.getRules(); assert(equal(copy.features,F) and copy.riverAttackPercent==20)
    -- The legacy Forest terrain (earlier generators, older saves) keeps its values.
    local legacy=Rules.terrains.Forest
    assert(legacy.movement==2 and legacy.defensePercent==25 and legacy.rough and legacy.yields.food==1 and legacy.yields.production==2)
    assert(table.find(Rules.improvements.Camp.terrains,"Grassland") and not table.find(Rules.improvements.Farm.terrains,"Tundra"))
    -- The generic per-tile cost counts features (a road still costs one).
    assert(WorldMap.movementCost({id=1,terrain="Plains",feature="Forest"})==2 and WorldMap.movementCost({id=1,terrain="Desert",feature="Oasis"})==1)
    assert(WorldMap.movementCost({id=1,terrain="Grassland",feature="Marsh",road=true})==1)
end

-- 1. Generation: deterministic features and rivers; river edges are symmetric, join passable land, follow real polygon
-- edges (pentagons included) and every river network reaches water.
local pentagonRivers,riverNetworks,mapsWithRivers=0,0,0
do
    local function checkMap(map: any,sphere: boolean,frequency: number?): (number,number)
        local tiles=map.tiles; local edges: {{number}}={}
        local cells=if sphere then Sphere.generate(frequency :: number).cells else nil
        for id,tile in tiles do
            if tile.feature then
                local rule=Rules.features[tile.feature]; assert(rule and table.find(rule.terrains,tile.terrain),"a feature stands on one of its terrains")
                if tile.resource then assert(table.find(rule.improvements,Rules.resources[tile.resource].improvement),"a resource under a feature keeps its improvement") end
            end
            local mask=tile.river
            if mask==nil then continue end
            local list=map.neighbors[id]
            assert(mask%1==0 and mask>=1 and mask<bit32.lshift(1,#list),"a river mask indexes existing edges")
            assert(passable(tile),"rivers border passable land")
            for index,other in list do
                if not bit32.btest(mask,bit32.lshift(1,index-1)) then continue end
                assert(WorldMap.riverBetween(map,other,id),"a river edge is marked on both sides")
                assert(passable(tiles[other]))
                if other>id then table.insert(edges,{id,other}) end
                if cells then
                    -- The edge is a real polygon edge: the two cells share exactly two corners.
                    local shared=0; for _, corner in cells[id].corners do if table.find(cells[other].corners,corner) then shared += 1 end end
                    assert(shared==2,"a river runs along a shared polygon edge")
                    if #list==5 then pentagonRivers += 1 end
                end
            end
            assert(equal(WorldMap.riverNeighbors(map,id),(function() local ids={}; for index,other in list do if bit32.btest(mask,bit32.lshift(1,index-1)) then table.insert(ids,other) end end; return ids end)()))
        end
        -- River corners: three mutually adjacent tiles. Edges sharing a corner form one network; each network has a
        -- corner touching water (its mouth).
        local function corners(a: number,b: number): {string}
            local keys={}
            for _, c in map.neighbors[a] do if c~=b and adjacent(map,b,c) then local t=sorted({a,b,c}); table.insert(keys,t[1]..":"..t[2]..":"..t[3]) end end
            return keys
        end
        local parent: {number}={}; for i=1,#edges do parent[i]=i end
        local function find(i: number): number while parent[i]~=i do parent[i]=parent[parent[i]]; i=parent[i] end; return i end
        local byCorner: {[string]: number}={}; local wet: {[number]: boolean}={}
        for i,edge in edges do
            for _, key in corners(edge[1],edge[2]) do
                local other=byCorner[key]; if other then parent[find(i)]=find(other) else byCorner[key]=i end
                local water=false
                for part in string.gmatch(key,"%d+") do if tiles[tonumber(part) :: number].terrain=="Water" then water=true end end
                if water then wet[i]=true end
            end
        end
        local roots: {[number]: boolean}={}; local reaches: {[number]: boolean}={}
        for i=1,#edges do local r=find(i); roots[r]=true; if wet[i] then reaches[r]=true end end
        local networks=0; for r in roots do networks += 1; assert(reaches[r],"every river network reaches water") end
        return #edges,networks
    end
    local function same(a: any,b: any): boolean
        for id,tile in a.tiles do local t=b.tiles[id]; if tile.terrain~=t.terrain or tile.feature~=t.feature or tile.river~=t.river or tile.resource~=t.resource then return false end end
        return true
    end
    local featureKinds: {[string]: boolean}={}
    for _, seed in {1,42,99991,-7} do
        for _, radius in {10,20,40} do
            local map=WorldMap.generate(seed,radius); local edges,networks=checkMap(map,false,nil)
            assert(same(map,WorldMap.generate(seed,radius)),"hex features and rivers are deterministic")
            for _, t in map.tiles do if t.feature then featureKinds[t.feature]=true end end
            if edges>0 then mapsWithRivers += 1 end; riverNetworks += networks
        end
        for _, frequency in {6,12,22} do
            local map=WorldMap.generateSphere(seed,frequency); local edges,networks=checkMap(map,true,frequency)
            assert(same(map,WorldMap.generateSphere(seed,frequency)),"sphere features and rivers are deterministic")
            for _, t in map.tiles do if t.feature then featureKinds[t.feature]=true end end
            if edges>0 then mapsWithRivers += 1 end; riverNetworks += networks
        end
    end
    for _, id in Rules.featureOrder do assert(featureKinds[id],"generation places "..id) end
    assert(mapsWithRivers==24 and riverNetworks>=200,"every sampled map has rivers: "..mapsWithRivers.." maps, "..riverNetworks.." networks")
    assert(pentagonRivers>0,"rivers also run along pentagon edges")
    -- Generated hex ids run by x and then y, so an interior tile's ascending neighbours (bits 0-5) sit at the offsets
    -- (-1,-1), (-1,0), (0,-1), (0,1), (1,0), (1,1), as the documentation tells renderers.
    local hexMap=WorldMap.generate(3,10); local origin=WorldMap.tileId(hexMap,2,-1) :: number
    local expectedOrder={}
    for _, offset in {{-1,-1},{-1,0},{0,-1},{0,1},{1,0},{1,1}} do table.insert(expectedOrder,WorldMap.tileId(hexMap,2+offset[1],-1+offset[2]) :: number) end
    assert(equal(hexMap.neighbors[origin],expectedOrder),"interior hex neighbour order")
    -- A different seed changes the rivers.
    local a,b=WorldMap.generate(5,15),WorldMap.generate(6,15); local differ=0
    for id,t in a.tiles do if t.river~=b.tiles[id].river then differ += 1 end end
    assert(differ>20)
    -- Tiny maps hold no rivers (too little land for one), and the toy globe stays valid.
    for _, seed in {1,2,3} do
        for _, t in WorldMap.generateSphere(seed,1).tiles do assert(t.river==nil) end
        assert(Save.valid(Game.serialize(Game.new(seed,{mapShape="Sphere",frequency=1,humanPlayers=2}))))
    end
    -- A new game keeps the generated features and rivers; a saved game restores them exactly.
    local s=Game.new(42,{radius=20,humanPlayers=2})
    assert(same(s,WorldMap.generate(42,20)))
    local saved=Game.serialize(s); local back=Game.restore(saved); assert(back and equal(Game.serialize(back),saved))
    print(string.format("  generation: 24 maps, %d river networks all reaching water, %d river edges on pentagons",riverNetworks,pentagonRivers))
end

-- 2. Yields: features replace (Forest, Jungle, Oasis) or reduce (Marsh) the terrain's yields; a river adds a gold and a
-- Farm on a river a food. Explored but unseen tiles show their natural yields with the feature and river.
do
    local s,c,g=arena(501)
    local probe=g.neighbors[c][1]; local partner: number?=nil
    for _, id in g.neighbors[probe] do if id~=c and adjacent(g,id,c) then partner=id; break end end
    assert(partner)
    s.tiles[probe].ownerId=1; place(s,1,"Worker",c)
    -- A command refreshes exploration; this fixture adds the worker's sight to the explored list directly.
    local explored=s.players[1].explored
    for _, id in WorldMap.range(g,c,2) do if not table.find(explored,id) then table.insert(explored,id) end end
    table.sort(explored)
    local function yields(terrain: string,feature: string?,resource: string?,improvement: string?,river: boolean): (number,number,number)
        local t=s.tiles[probe]; t.terrain=terrain; t.feature=feature; t.resource=resource; t.improvement=improvement
        setRiver(s,g,probe,partner :: number,river)
        assert(Save.valid(Game.serialize(s)),"a valid fixture")
        local view=Game.snapshot(s,1).tiles[probe]
        assert(view.visible and view.feature==feature and view.river==t.river)
        return view.food :: number,view.production :: number,view.gold :: number
    end
    local cases: {{any}}={
        {"Plains",nil,nil,nil,false,2,1,0},{"Plains","Forest",nil,nil,false,1,2,0},{"Grassland","Forest",nil,nil,false,1,2,0},
        {"Tundra","Forest",nil,nil,false,1,2,0},{"Grassland","Jungle",nil,nil,false,2,0,0},{"Plains","Jungle",nil,nil,false,2,0,0},
        {"Grassland","Marsh",nil,nil,false,2,0,0},{"Desert","Oasis",nil,nil,false,3,0,1},{"Plains","Forest","Deer",nil,false,2,2,0},
        {"Grassland","Jungle","Spices",nil,false,2,0,1},{"Plains","Forest","Deer","Camp",false,3,2,0},{"Plains",nil,nil,nil,true,2,1,1},
        {"Plains",nil,nil,"Farm",false,3,1,0},{"Plains",nil,nil,"Farm",true,4,1,1},{"Grassland","Marsh",nil,nil,true,2,0,1},
        {"Desert","Oasis",nil,nil,true,3,0,2},{"Hills",nil,nil,"Mine",true,1,3,1},{"Grassland","Jungle","Spices","Plantation",true,2,0,4},
    }
    for _, case in cases do
        local f,p,gold=yields(case[1],case[2],case[3],case[4],case[5])
        assert(f==case[6] and p==case[7] and gold==case[8],string.format("%s %s %s %s river=%s: %d/%d/%d",case[1],tostring(case[2]),tostring(case[3]),tostring(case[4]),tostring(case[5]),f,p,gold))
    end
    -- A city working a river tile earns its gold: with every owned tile bare Plains and a Gold focus, a river along two
    -- of its tiles adds exactly one gold to the forecast.
    local t,cc,gg=arena(502)
    local city=placeCity(t,1,cc); for _, id in gg.neighbors[cc] do t.tiles[id].ownerId=1 end
    apply(t,1,{kind="SetCityFocus",cityId=city.id,focus="Gold"})
    local before=Game.snapshot(t,1).cityForecasts[tostring(city.id)].gold
    local ring=gg.neighbors[cc]; local second: number?=nil
    for _, id in ring do if id~=ring[1] and adjacent(gg,id,ring[1]) then second=id; break end end
    setRiver(t,gg,ring[1],second :: number,true)
    assert(Game.snapshot(t,1).cityForecasts[tostring(city.id)].gold==before+1,"a worked river tile adds one gold")
    -- Explored but not visible: the natural yields include the feature and the river (no improvement is shown).
    local far: number?=nil
    for _, id in WorldMap.range(g,c,6) do if WorldMap.distance(g,id,c)==6 then far=id; break end end
    local farTile=s.tiles[far :: number]; farTile.terrain="Desert"; farTile.feature="Oasis"; farTile.resource=nil; farTile.improvement=nil; farTile.road=nil
    local farPartner=g.neighbors[far :: number][1]; s.tiles[farPartner].terrain="Plains"; s.tiles[farPartner].feature=nil
    setRiver(s,g,far :: number,farPartner,true)
    if not table.find(explored,far :: number) then table.insert(explored,far :: number); table.sort(explored) end
    local view=Game.snapshot(s,1).tiles[far :: number]
    assert(view.explored and not view.visible and view.feature=="Oasis" and view.river==farTile.river and view.food==3 and view.production==0 and view.gold==2)
    assert(view.ownerId==nil and view.improvement==nil and view.road==nil)
end

-- 3. Movement: features cost their movement, a river crossing spends all remaining movement (a road on both tiles
-- bridges it), civilians obey both, and previews equal the applied move.
do
    local s,c,g=arena(511)
    local n=sorted(g.neighbors[c])
    s.tiles[n[1]].feature="Forest"; s.tiles[n[2]].terrain="Grassland"; s.tiles[n[2]].feature="Marsh"
    s.tiles[n[3]].terrain="Desert"; s.tiles[n[3]].feature="Oasis"; s.tiles[n[4]].terrain="Grassland"; s.tiles[n[4]].feature="Jungle"
    local w=place(s,1,"Warrior",c)
    for i,left in {0,0,1,0,1} do
        local p=preview(s,w,n[i]); assert(p.movesLeft==left and not p.riverCrossing and not p.zoneOfControl,"feature cost "..i)
    end
    -- A third of a move still enters a Forest (a partial move).
    local spot: number?=nil
    for _, id in g.neighbors[n[1]] do if WorldMap.distance(g,id,c)==2 then spot=id; break end end
    local third=place(s,1,"Warrior",spot :: number,1/3)
    local p=move(s,third,n[1]); assert(p.movesLeft==0 and math.abs(p.movesSpent-1/3)<1e-12)
    assert(Save.valid(Game.serialize(s)))
    -- River crossings.
    local r,rc,rg=arena(512)
    local m=sorted(rg.neighbors[rc])
    setRiver(r,rg,rc,m[1],true)
    local warrior=place(r,1,"Warrior",rc)
    local cross=preview(r,warrior,m[1]); assert(cross.movesLeft==0 and cross.riverCrossing and cross.endsMovement and not cross.zoneOfControl and cross.movesSpent==2)
    local dry=preview(r,warrior,m[2]); assert(dry.movesLeft==1 and not dry.riverCrossing)
    -- Beyond the crossing nothing is reachable through it; a tile two steps away arrives with no movement.
    local legal=Game.snapshot(r,1).legalMoves[tostring(warrior.id)]; assert(table.find(legal,m[1]))
    move(r,warrior,m[1]); assert(warrior.moves==0)
    rejected(r,1,{kind="MoveUnit",unitId=warrior.id,tileId=rg.neighbors[m[1]][1]})
    -- Civilians obey the crossing too.
    setRiver(r,rg,rc,m[3],true)
    local worker=place(r,1,"Worker",rc); local wp=preview(r,worker,m[3]); assert(wp.riverCrossing and wp.movesLeft==0)
    -- A Scout with three moves walks around a river rather than cross it: two dry steps leave a move, the crossing none.
    local scout=place(r,1,"Scout",m[2])
    local beyond: number?=nil
    for _, id in rg.neighbors[m[2]] do if id~=rc and id~=m[1] and not adjacent(rg,id,rc) then beyond=id; break end end
    setRiver(r,rg,m[2],beyond :: number,true)
    local sp=preview(r,scout,beyond :: number); assert(not sp.riverCrossing and sp.movesLeft==1 and #sp.path==3)
    -- Roads on both tiles bridge the river: a third of a move and no crossing; a road on one side does not.
    local b,bc,bg=arena(513)
    local k=sorted(bg.neighbors[bc])
    -- k2 is not next to k[1], so no road route reaches it without crossing.
    local k2: number?=nil; for _, id in k do if id~=k[1] and not adjacent(bg,id,k[1]) then k2=id; break end end
    setRiver(b,bg,bc,k[1],true); setRiver(b,bg,bc,k2 :: number,true)
    b.tiles[bc].road=true; b.tiles[k[1]].road=true
    local runner=place(b,1,"Warrior",bc)
    local bridged=preview(b,runner,k[1]); assert(not bridged.riverCrossing and bridged.movesLeft==10/6)
    local unbridged=preview(b,runner,k2 :: number); assert(unbridged.riverCrossing and unbridged.movesLeft==0)
    move(b,runner,k[1]); assert(runner.moves==10/6)
    assert(Save.valid(Game.serialize(b)))
    -- The river and the zone of control can both end a step.
    local z,zc,zg=arena(514); war(z)
    place(z,2,"Warrior",zc)
    local zr=sorted(zg.neighbors[zc]); local from=zr[1]; local to: number?=nil
    for _, id in zg.neighbors[from] do if id~=zc and adjacent(zg,id,zc) then to=id; break end end
    setRiver(z,zg,from,to :: number,true)
    local both=place(z,1,"Warrior",from); local bp=preview(z,both,to :: number)
    assert(bp.riverCrossing and bp.zoneOfControl and bp.movesLeft==0)
end

-- 4. Random scenarios: legal moves equal applied results and an independent reference over features, rivers, roads,
-- territory, enemies and war.
do
    local function reference(s: any,unit: any,g: any): {[number]: number}
        local seen: {[number]: boolean}={}
        for _, u in s.units do if u.ownerId==unit.ownerId then for _, id in WorldMap.range(g,u.tileId,2) do seen[id]=true end end end
        for _, c in s.cities do if c.ownerId==unit.ownerId then for _, id in WorldMap.range(g,c.tileId,2) do seen[id]=true end end end
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
            if not seen[id] or not passable(t) then return false end
            if unitAt[id]~=nil and unitAt[id]~=unit then return false end
            if cityAt[id]~=nil and cityAt[id].ownerId~=unit.ownerId then return false end
            if t.ownerId~=nil and t.ownerId~=unit.ownerId and not atWar then return false end
            return true
        end
        local function river(a: number,b: number): boolean
            local mask=s.tiles[a].river; if not mask then return false end
            local index=table.find(g.neighbors[a],b) :: number
            return bit32.band(mask,2^(index-1))~=0
        end
        local start=math.round(unit.moves*6); local best: {[number]: number}={[unit.tileId]=start}
        local function walk(from: number,left: number)
            for _, to in g.neighbors[from] do
                if not enterable(to) then continue end
                local t=s.tiles[to]; local roads=s.tiles[from].road and t.road
                local moves=Rules.terrains[t.terrain].movement
                if t.feature then moves=math.max(moves,Rules.features[t.feature].movement) end
                local cost=if roads then 2 else moves*6
                local stop=river(from,to) and not roads
                if military and atWar then for _, n in g.neighbors[to] do if adjacent(g,from,n) and source(n) then stop=true end end end
                local after=if stop or cost>=left then 0 else left-cost
                if best[to]==nil or after>best[to] then best[to]=after; if after>0 then walk(to,after) end end
            end
        end
        if start>0 then walk(unit.tileId,start) end
        best[unit.tileId]=nil
        return best
    end
    local checked,crossings,featureSteps,riverListed=0,0,0,0
    for scenario=1,30 do
        local s,c,g=arena(520+scenario%3)
        local state=scenario*104729
        local function rand(n: number): number state=(state*1103515245+12345)%2147483648; return state%n+1 end
        if scenario%3~=0 then war(s) end
        local area=WorldMap.range(g,c,4)
        local terrains={"Plains","Plains","Grassland","Grassland","Hills","Desert","Tundra","Mountain","Water"}
        for _, id in area do
            local t=s.tiles[id]; t.terrain=terrains[rand(#terrains)]; t.feature=nil
            local options={}
            for _, f in Rules.featureOrder do if table.find(Rules.features[f].terrains,t.terrain) then table.insert(options,f) end end
            if #options>0 and rand(5)<=3 then t.feature=options[rand(#options)] end
            t.road=if passable(t) and rand(5)==1 then true else nil
            t.ownerId=if rand(10)==1 then 2 else nil
        end
        -- Rivers on random edges between passable tiles of the arena.
        for _, id in area do
            for _, other in g.neighbors[id] do
                if other>id and table.find(area,other) and passable(s.tiles[id]) and passable(s.tiles[other]) and rand(9)==1 then setRiver(s,g,id,other,true) end
            end
        end
        local used: {[number]: boolean}={}
        local function take(reach: number): number?
            local free: {number}={}
            for _, id in WorldMap.range(g,c,reach) do if not used[id] and passable(s.tiles[id]) then table.insert(free,id) end end
            if #free==0 then return nil end
            table.sort(free); local id=free[rand(#free)]; used[id]=true; return id
        end
        local own={}
        for _=1,1+rand(2) do
            local id=take(2); local kinds={"Warrior","Scout","Worker","Settler","Warrior"}
            if id then
                local kind=kinds[rand(#kinds)]; local full=Rules.units[kind].moves
                local options={1/3,1,1.5,full,full,full}
                table.insert(own,place(s,1,kind,id,math.min(full,options[rand(#options)])))
            end
        end
        for _=1,rand(3) do local id=take(3); if id then place(s,2,({"Warrior","Scout","Worker"})[rand(3)],id) end end
        assert(Save.valid(Game.serialize(s)),"a valid scenario")
        local view=Game.snapshot(s,1)
        riverListed += checkRiverMoves(s,1,view)
        -- Removing every enemy unit player 1 cannot see changes no river move.
        local hiddenless=deep(s); local seenTiles: {[number]: boolean}={}
        for _, tv in view.tiles do if tv.visible then seenTiles[tv.id]=true end end
        for i=#hiddenless.units,1,-1 do local hu=hiddenless.units[i]; if hu.ownerId==2 and not seenTiles[hu.tileId] then table.remove(hiddenless.units,i) end end
        assert(equal(Game.snapshot(hiddenless,1).riverMoves,view.riverMoves),"hidden enemies change no river move")
        for _, u in own do
            local expected=reference(s,u,g)
            local attacks: {[number]: boolean}={}; for _, a in view.attackPreviews[tostring(u.id)] do attacks[a.tileId]=true end
            local listed: {[number]: boolean}={}
            for _, tileId in view.legalMoves[tostring(u.id)] do
                if attacks[tileId] then continue end
                local p=preview(s,u,tileId); listed[tileId]=true; checked += 1
                assert(expected[tileId]~=nil and p.movesLeft==expected[tileId]/6,"a preview differs from the reference")
                if p.riverCrossing then crossings += 1; assert(p.movesLeft==0 and WorldMap.riverBetween(g,p.path[#p.path-1],tileId)) end
                for i=2,#p.path do if s.tiles[p.path[i]].feature then featureSteps += 1 end end
                local clone=deep(s); local mover=unitById(clone,u.id)
                apply(clone,1,{kind="MoveUnit",unitId=u.id,tileId=tileId})
                assert(mover.tileId==tileId and mover.moves==p.movesLeft,"the applied move equals its preview")
            end
            for tileId in expected do assert(listed[tileId] or attacks[tileId],"a destination the rules allow is missing") end
        end
    end
    assert(riverListed==crossings,"every crossing destination is listed in riverMoves")
    assert(checked>=200 and crossings>=20 and featureSteps>=50,"coverage: "..checked.." destinations, "..crossings.." crossings, "..featureSteps.." feature steps")
    print(string.format("  random scenarios: %d destinations, %d ended by a river crossing, %d path steps onto features",checked,crossings,featureSteps))
end

-- 5. Combat: feature defence and roughness, and the -20% river penalty on melee attacks, in exact previews that equal
-- the applied result and an independent statement of the formula.
do
    local function formula(attacker: any,defender: any,feature: string?,terrain: string,river: boolean): (number,number)
        local ranged=Rules.units[attacker.kind].range>1
        local base=if ranged then Rules.units[attacker.kind].rangedStrength else Rules.units[attacker.kind].strength
        local rough=Rules.terrains[terrain].rough or (feature~=nil and Rules.features[feature].rough)
        local promo=0; for _, id in attacker.promotions or {} do promo += if rough then Rules.promotions[id].roughPercent else Rules.promotions[id].openPercent end
        local attack=base*(0.5+attacker.hp/200)*(100+promo-(if river and not ranged then 20 else 0))/100
        local percent=Rules.terrains[terrain].defensePercent+(if feature then Rules.features[feature].defensePercent else 0)+(if defender.fortified then 50 else 0)
        local defense=math.max(3,Rules.units[defender.kind].strength)*(100+percent)/100*(0.5+defender.hp/200)
        local dealt=math.clamp(math.floor(30*attack/defense+0.5),8,65)
        local received=if ranged then 0 else math.clamp(math.floor(25*defense/attack+0.5),8,65)
        return dealt,received
    end
    local worked: {[string]: {number}}={}
    local cases,acrossCount=0,0
    local base,c,g=arena(531); war(base)
    local ring=sorted(g.neighbors[c])
    local saved=Game.serialize(base)
    local variants: {{any}}={{"Plains",nil},{"Plains","Forest"},{"Grassland","Jungle"},{"Grassland","Marsh"},{"Desert","Oasis"},{"Hills",nil},{"Tundra","Forest"}}
    for index,variant in variants do
        for _, river in {false,true} do
            for _, kind in {"Warrior","Archer","Swordsman"} do
                for _, fortified in {false,true} do
                    for _, drill in {false,true} do
                        if drill and kind=="Archer" then continue end
                        local s: any=Game.restore(saved); assert(s)
                        local target=ring[1+(index+cases)%6]
                        local t=s.tiles[target]; t.terrain=variant[1]; t.feature=variant[2]
                        setRiver(s,g,c,target,river)
                        local attacker=place(s,1,kind,c); attacker.hp=Rules.units[kind].hp-(cases%4)*10
                        if drill then attacker.xp=10; attacker.promotions={"Drill1"}; attacker.level=1 end
                        for _, tech in {"Agriculture","Archery","Mining","BronzeWorking","IronWorking"} do table.insert(s.players[1].technologies,tech) end
                        local defender=place(s,2,"Warrior",target); defender.hp=100-(cases%3)*15; defender.fortified=fortified
                        assert(Save.valid(Game.serialize(s)),"a valid combat fixture")
                        local expectedDealt,expectedReceived=formula(attacker,defender,variant[2],variant[1],river)
                        local p: any,message=Game.previewAttack(s,1,attacker.id,target); assert(p,message)
                        assert(p.exact and p.dealt==expectedDealt and p.received==expectedReceived,tostring(variant[1]).." "..tostring(variant[2]).." river="..tostring(river).." "..kind..": preview "..tostring(p.dealt).."/"..tostring(p.received).." formula "..expectedDealt.."/"..expectedReceived)
                        assert(p.acrossRiver==(river and kind~="Archer"))
                        if p.acrossRiver then acrossCount += 1 end
                        local listed: any=nil; for _, q in Game.snapshot(s,1).attackPreviews[tostring(attacker.id)] do if q.tileId==target then listed=q end end
                        assert(equal(listed,p),"the snapshot lists the same preview")
                        local before,own=defender.hp,attacker.hp
                        apply(s,1,{kind=if kind=="Archer" then "RangedAttack" else "MoveUnit",unitId=attacker.id,tileId=target})
                        local after=unitById(s,defender.id)
                        assert((after and before-after.hp==p.dealt) or (not after and before<=p.dealt),"applied damage equals the preview")
                        local survivor=unitById(s,attacker.id); assert(survivor and survivor.hp==own-p.received)
                        cases += 1
                    end
                end
            end
        end
    end
    assert(cases==140 and acrossCount==56)
    -- Worked examples at full health, Warrior against Warrior: Forest and Jungle defend like Hills (24/31), Marsh -15%
    -- gives 35/21, an Oasis -10% gives 33/23, and across a river the attack loses 20%: 24/31 on open ground and 19/39
    -- into a Forest.
    local examples: {any}={{"Plains",nil,false,30,25},{"Plains",nil,true,24,31},{"Plains","Forest",false,24,31},{"Grassland","Jungle",false,24,31},
        {"Grassland","Marsh",false,35,21},{"Desert","Oasis",false,33,23},{"Plains","Forest",true,19,39}}
    for _, example in examples do
        local s: any=Game.restore(saved); assert(s)
        local target=ring[4]; s.tiles[target].terrain=example[1]; s.tiles[target].feature=example[2]; setRiver(s,g,c,target,example[3])
        local attacker=place(s,1,"Warrior",c); place(s,2,"Warrior",target)
        local p=Game.previewAttack(s,1,attacker.id,target) :: any
        assert(p.dealt==example[4] and p.received==example[5],tostring(example[1]).." "..tostring(example[2]).." river="..tostring(example[3])..": "..tostring(p.dealt).."/"..tostring(p.received))
    end
    -- A melee attack on a city across a river: the preview range still contains the applied result and is lower than
    -- without the river; ranged attacks on cities keep no penalty.
    for _, river in {false,true} do
        local s: any=Game.restore(saved); assert(s)
        local target=ring[2]; setRiver(s,g,c,target,river)
        placeCity(s,2,target)
        local attacker=place(s,1,"Warrior",c)
        local p=Game.previewAttack(s,1,attacker.id,target) :: any; assert(p.target=="City" and p.acrossRiver==river)
        apply(s,1,{kind="MoveUnit",unitId=attacker.id,tileId=target})
        local city: any=nil; for _, cc in s.cities do if cc.tileId==target then city=cc end end
        local dealt=Rules.cityHp-city.hp
        assert(dealt>=p.dealtMin and dealt<=p.dealtMax)
        worked["city:"..tostring(river)]={p.dealtMax}
    end
    assert(worked["city:true"][1]<worked["city:false"][1],"a river weakens a melee attack on a city")
    -- Drill reads a rough feature; Shock reads an open one (Oasis).
    do
        local s: any=Game.restore(saved); assert(s)
        local target=ring[3]; s.tiles[target].terrain="Desert"; s.tiles[target].feature="Oasis"
        local attacker=place(s,1,"Warrior",c); attacker.xp=10; attacker.level=1; attacker.promotions={"Shock1"}
        place(s,2,"Warrior",target)
        local shock=Game.previewAttack(s,1,attacker.id,target) :: any
        attacker.promotions={"Drill1"}; local drill=Game.previewAttack(s,1,attacker.id,target) :: any
        assert(shock.dealt>drill.dealt,"an Oasis is open terrain")
        s.tiles[target].terrain="Grassland"; s.tiles[target].feature="Marsh"
        local drillMarsh=Game.previewAttack(s,1,attacker.id,target) :: any
        attacker.promotions={"Shock1"}; local shockMarsh=Game.previewAttack(s,1,attacker.id,target) :: any
        assert(drillMarsh.dealt>shockMarsh.dealt,"a Marsh is rough terrain")
    end
    print(string.format("  combat: %d previews equal to the applied result and the formula, %d melee attacks across a river",cases,acrossCount))
end

-- 6. Improvements and founding: only a feature's listed improvements may be built on it (roads anywhere); founding a
-- city keeps the feature, the resource and the river.
do
    local s,c=arena(541)
    for _, id in {"Agriculture","Mining","Archery","Writing","Currency","BronzeWorking","Masonry","Engineering"} do table.insert(s.players[1].technologies,id) end
    local worker=place(s,1,"Worker",c); s.tiles[c].ownerId=1
    local function choices(terrain: string,feature: string?,resource: string?): {string}
        local t=s.tiles[c]; t.terrain=terrain; t.feature=feature; t.resource=resource; t.improvement=nil; t.road=nil
        assert(Save.valid(Game.serialize(s)))
        return Game.snapshot(s,1).availableImprovements[tostring(worker.id)]
    end
    assert(equal(choices("Plains",nil,nil),{"Farm","Mine","Road"}))
    assert(equal(choices("Plains","Forest",nil),{"Road"}),"no Farm or Mine in a Forest")
    assert(equal(choices("Plains","Forest","Deer"),{"Camp","Road"}))
    assert(equal(choices("Grassland","Forest","Deer"),{"Camp","Road"}))
    assert(equal(choices("Grassland","Jungle","Spices"),{"Plantation","Road"}))
    assert(equal(choices("Grassland","Marsh",nil),{"Road"}))
    assert(equal(choices("Desert","Oasis",nil),{"Road"}))
    choices("Plains","Forest",nil)
    rejected(s,1,{kind="BuildImprovement",unitId=worker.id,improvement="Farm"})
    apply(s,1,{kind="BuildImprovement",unitId=worker.id,improvement="Road"})
    -- A Farm on a river tile gains fresh-water food once complete.
    local f,fc,fg=arena(542)
    for _, id in {"Agriculture"} do table.insert(f.players[1].technologies,id) end
    local farmer=place(f,1,"Worker",fc); f.tiles[fc].ownerId=1
    setRiver(f,fg,fc,fg.neighbors[fc][1],true)
    apply(f,1,{kind="BuildImprovement",unitId=farmer.id,improvement="Farm"})
    for _=1,2 do apply(f,1,{kind="EndTurn"}); apply(f,2,{kind="EndTurn"}) end
    assert(f.tiles[fc].improvement=="Farm")
    local view=Game.snapshot(f,1).tiles[fc]; assert(view.food==4 and view.gold==1)
    -- Founding on a Forest with Deer and a river keeps all three: features never change after generation (see the fog
    -- regression below). An undefended city there defends with the Forest's +25%.
    local h,hc,hg=arena(543)
    local t=h.tiles[hc]; t.terrain="Grassland"; t.feature="Forest"; t.resource="Deer"
    setRiver(h,hg,hc,hg.neighbors[hc][1],true)
    local mask=t.river
    local settler=place(h,1,"Settler",hc)
    apply(h,1,{kind="FoundCity",unitId=settler.id})
    assert(t.feature=="Forest" and t.resource=="Deer" and t.river==mask and Save.valid(Game.serialize(h)))
    -- Warrior against the undefended size-1 city: defence (14 + 1) x 1.25 = 18.75, so 30 x 10 / 18.75 rounds to 16 (12
    -- across the river, attack 8).
    war(h)
    local raider=place(h,2,"Warrior",hg.neighbors[hc][2])
    local forestCity=Game.previewAttack(h,2,raider.id,hc) :: any
    assert(forestCity.target=="City" and forestCity.dealtMax==16 and not forestCity.acrossRiver)
    -- Legacy Forest terrain keeps Camp, Plantation and Road and refuses a feature.
    local l,lc=arena(544)
    local lt=l.tiles[lc]; lt.terrain="Forest"; lt.resource="Deer"; lt.improvement="Camp"
    assert(Save.valid(Game.serialize(l)))
    lt.feature="Forest"; assert(not Save.valid({format="unciv-luau-base",version=1,state=deep(l)}),"no feature on the legacy Forest terrain")
end

-- 7. Fog: an unexplored tile never shows a feature or river; explored tiles show exactly the stored values; changing an
-- unexplored tile changes nothing either actor is shown.
do
    -- Regression: a rival founding a city out of sight on an explored Forest changes nothing the observer is shown. An
    -- explored tile projects only fields that never change after generation (terrain, resource, feature, river and the
    -- natural yields derived from them); owner, improvement and road need sight. Founding once cleared the feature, which
    -- turned the observer's unseen Forest (1/2) into bare Grassland (3/0) and revealed the hidden city and its timing.
    local s: any=Game.new(61,{humanPlayers=2,radius=12}); strip(s)
    apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id}); apply(s,1,{kind="EndTurn"})
    local g=graphOf(s)
    local sight: {[number]: boolean}={}
    for _, u in s.units do if u.ownerId==1 then for _, id in WorldMap.range(g,u.tileId,2) do sight[id]=true end end end
    for _, c in s.cities do if c.ownerId==1 then for _, id in WorldMap.range(g,c.tileId,2) do sight[id]=true end end end
    local site: number?=nil
    for _, t in s.tiles do
        if sight[t.id] or t.ownerId or not passable(t) then continue end
        local clear=true
        for _, c in s.cities do if WorldMap.distance(g,c.tileId,t.id)<5 then clear=false end end
        for _, u in s.units do if WorldMap.distance(g,u.tileId,t.id)<3 then clear=false end end
        if clear then site=t.id; break end
    end
    assert(site)
    local t=s.tiles[site :: number]; t.terrain="Grassland"; t.feature="Forest"; t.resource=nil; t.improvement=nil; t.road=nil
    local explored=s.players[1].explored
    for _, id in WorldMap.range(g,site :: number,1) do if not table.find(explored,id) then table.insert(explored,id) end end
    table.sort(explored)
    local settler=place(s,2,"Settler",site :: number)
    assert(Save.valid(Game.serialize(s)) and s.activePlayerId==2)
    local before=Game.snapshot(s,1).tiles
    assert(before[site :: number].explored and not before[site :: number].visible and before[site :: number].feature=="Forest")
    apply(s,2,{kind="FoundCity",unitId=settler.id})
    local after=Game.snapshot(s,1).tiles
    assert(not after[site :: number].visible,"the founding stays out of sight")
    assert(after[site :: number].feature=="Forest" and after[site :: number].food==1 and after[site :: number].production==2)
    assert(equal(before,after),"an unseen rival city changes no explored tile the observer is shown")
end
do
    local fogOptions: {any}={{radius=10,humanPlayers=2},{mapShape="Sphere",frequency=8,humanPlayers=2}}
    for _, options in fogOptions do
        local s: any=Game.new(17,options)
        local shownFeatures,shownRivers=0,0
        for owner=1,2 do
            local view=Game.snapshot(s,owner)
            for _, tv in view.tiles do
                local tile=s.tiles[tv.id]
                if not tv.explored then assert(tv.feature==nil and tv.river==nil and tv.terrain==nil,"no feature or river on an unexplored tile")
                else
                    assert(tv.feature==tile.feature and tv.river==tile.river)
                    if tv.feature then shownFeatures += 1 end; if tv.river then shownRivers += 1 end
                end
            end
            -- Changing every unexplored tile's feature and river changes nothing this actor is shown.
            local hidden=deep(s); local explored: {[number]: boolean}={}
            for _, id in s.players[owner].explored do explored[id]=true end
            for _, t in hidden.tiles do if not explored[t.id] then t.feature=if t.terrain=="Grassland" then "Marsh" else nil; t.river=if passable(t) then 1 else nil end end
            assert(equal(Game.snapshot(hidden,owner),view),"unexplored features and rivers are never projected")
        end
        -- Explore everything: every feature and river is then shown.
        for _, p in s.players do p.explored={}; for id=1,#s.tiles do table.insert(p.explored,id) end end
        local all=Game.snapshot(s,1); local features,rivers=0,0
        for _, tv in all.tiles do if tv.feature then features += 1 end; if tv.river then rivers += 1 end end
        local stored,storedRivers=0,0; for _, t in s.tiles do if t.feature then stored += 1 end; if t.river then storedRivers += 1 end end
        assert(features==stored and rivers==storedRivers and stored>0 and storedRivers>0)
    end
    -- The generic projection follows the same rule.
    local map=WorldMap.generate(9,10); local known: number?=nil; local unknown: number?=nil
    for _, t in map.tiles do if t.feature and t.river then if not known then known=t.id elseif not unknown then unknown=t.id end end end
    assert(known and unknown)
    local rows=WorldMap.projectTiles(map,{known :: number},{})
    assert(rows[known :: number].feature==map.tiles[known :: number].feature and rows[known :: number].river==map.tiles[known :: number].river)
    assert(rows[unknown :: number].feature==nil and rows[unknown :: number].river==nil)
end

-- 8. Saves: a save written before features and rivers restores unchanged through both paths and plays on; a G4 save
-- round-trips; validation accepts and rejects the new fields case by case.
do
    local map=WorldMap.generate(124,3)
    strip(map)
    local function at(x: number,y: number): number return WorldMap.tileId(map,x,y) :: number end
    local hub,west,east,rival=at(0,0),at(-2,0),at(1,0),at(3,0)
    for _, id in {hub,west,east,rival} do local t=map.tiles[id]; t.terrain="Plains"; t.resource=nil; t.improvement=nil; t.road=nil; t.ownerId=nil end
    -- A legacy Forest terrain tile with a Camp on Deer, as earlier generators made.
    local woods=at(-1,1); local wt=map.tiles[woods]; wt.terrain="Forest"; wt.resource="Deer"; wt.improvement="Camp"; wt.ownerId=1; wt.road=nil
    map.tiles[hub].ownerId=1
    local explored={}; for id=1,#map.tiles do table.insert(explored,id) end
    local legacyState: any={seed=124,radius=3,difficulty="Normal",humanPlayers=2,forest=false,maxTurns=120,turn=5,revision=9,activePlayerId=1,phase="Playing",tiles=map.tiles,
        units={{id=1,ownerId=1,kind="Warrior",tileId=west,hp=100,moves=2,fortified=false,level=0},
            {id=2,ownerId=1,kind="Worker",tileId=east,hp=50,moves=2,fortified=false,level=0},
            {id=3,ownerId=2,kind="Settler",tileId=rival,hp=50,moves=2,fortified=false,level=0}},
        cities={{id=1,ownerId=1,originalOwnerId=1,capital=true,tileId=hub,name="Fixture",population=2,food=0,production=0,queue="Warrior",hp=150,buildings={},focus="Balanced"}},players={},
        diplomacy={status="Peace",peaceUntil=0},trades={},events={},nextEvent=1,nextUnit=4,nextCity=2,nextTrade=1,log={}}
    for id=1,2 do table.insert(legacyState.players,{id=id,human=true,gold=50,science=0,culture=0,happiness=9,technologies={},policies={},explored=table.clone(explored),resources={},income={food=0,production=0,gold=0,science=0,culture=0,maintenance=0}}) end
    local legacy={format="unciv-luau-base",version=1,state=legacyState}
    for _, t in legacyState.tiles do assert(t.feature==nil and t.river==nil) end
    assert(Save.valid(legacy),"a pre-G4 save stays valid")
    local before=deep(legacy)
    local restored: any,err=Game.restore(legacy); assert(restored and err==nil,err)
    assert(equal(legacy,before) and equal(Game.serialize(restored),legacy),"restore keeps every stored field and adds none")
    assert(equal(Game.restore(legacy),Save.restore(legacy)),"both restore paths give the same state")
    -- The legacy Forest terrain still costs two moves and yields 1/2 (+1 Deer, +1 Camp food).
    local w=unitById(restored,1)
    local g=graphOf(restored)
    if adjacent(g,west,woods) then local p=preview(restored,w,woods); assert(p.movesLeft==0 and not p.riverCrossing) end
    local wv=Game.snapshot(restored,1).tiles[woods]; assert(wv.feature==nil and wv.river==nil and wv.food==3 and wv.production==2)
    apply(restored,1,{kind="EndTurn"}); apply(restored,2,{kind="EndTurn"})
    local after=Game.serialize(restored); assert(Save.valid(after))
    for _, t in after.state.tiles do assert(t.feature==nil and t.river==nil,"playing on adds no feature or river") end
    -- A G4 save from a generated game round-trips exactly, hex and sphere.
    local saveOptions: {any}={{radius=12,humanPlayers=2},{mapShape="Sphere",frequency=6,humanPlayers=2}}
    for _, options in saveOptions do
        local s=Game.new(31,options); local saved=Game.serialize(s); local back=Game.restore(saved)
        assert(back and equal(Game.serialize(back),saved))
        local features,rivers=0,0; for _, t in saved.state.tiles do if t.feature then features += 1 end; if t.river then rivers += 1 end end
        assert(features>0 and rivers>0)
    end
    -- Validation, on a fixture with a known river edge and a known pentagon edge.
    local s=Game.new(31,{radius=12,humanPlayers=2}); strip(s)
    local hg=graphOf(s)
    local a: number?=nil; local b: number?=nil
    for _, t in s.tiles do
        if t.terrain~="Plains" or t.resource or t.ownerId then continue end
        for _, other in hg.neighbors[t.id] do local o=s.tiles[other]; if o.terrain=="Plains" and not o.resource and not o.ownerId then a=t.id; b=other; break end end
        if a then break end
    end
    assert(a and b)
    setRiver(s,hg,a :: number,b :: number,true)
    local good=Game.serialize(s); assert(Save.valid(good))
    local function variant(change: (any)->()): boolean local copy=deep(good); change(copy.state); return Save.valid(copy) end
    local ta,tb=a :: number,b :: number
    local water: number?=nil; for _, t in s.tiles do if t.terrain=="Water" then water=t.id; break end end
    local boundary: number?=nil; for id,list in hg.neighbors do if #list<6 and s.tiles[id].terrain=="Plains" then boundary=id; break end end
    assert(water and boundary)
    -- Accepted.
    for _, case in {{"Plains","Forest"},{"Grassland","Forest"},{"Tundra","Forest"},{"Plains","Jungle"},{"Grassland","Jungle"},{"Grassland","Marsh"},{"Desert","Oasis"}} do
        assert(variant(function(st) st.tiles[ta].terrain=case[1]; st.tiles[ta].feature=case[2] end),"accepts "..case[2].." on "..case[1])
    end
    assert(variant(function(st) st.tiles[ta].feature="Forest"; st.tiles[ta].resource="Deer"; st.tiles[ta].improvement="Camp" end))
    assert(variant(function(st) st.tiles[ta].terrain="Grassland"; st.tiles[ta].feature="Jungle"; st.tiles[ta].resource="Spices"; st.tiles[ta].improvement="Plantation" end))
    assert(variant(function(st) st.tiles[ta].feature="Marsh"; st.tiles[ta].terrain="Grassland"; st.tiles[ta].road=true end),"roads on any feature")
    assert(variant(function(st) setRiver({tiles=st.tiles},hg,ta,tb,false) end),"no river at all")
    -- Rejected.
    local bad: {(any)->()}={
        function(st) st.tiles[ta].feature="Volcano" end,
        function(st) st.tiles[ta].feature=7 end,
        function(st) st.tiles[ta].feature="Oasis" end,
        function(st) st.tiles[ta].feature="Marsh" end,
        function(st) st.tiles[ta].terrain="Hills"; st.tiles[ta].feature="Forest" end,
        function(st) st.tiles[ta].terrain="Forest"; st.tiles[ta].feature="Forest" end,
        function(st) st.tiles[water :: number].feature="Forest" end,
        function(st) st.tiles[ta].feature="Forest"; st.tiles[ta].resource="Wheat" end,
        function(st) st.tiles[ta].feature="Jungle"; st.tiles[ta].resource="Deer" end,
        function(st) st.tiles[ta].feature="Forest"; st.tiles[ta].improvement="Farm" end,
        function(st) st.tiles[ta].feature="Forest"; st.tiles[ta].improvement="Mine" end,
        function(st) st.tiles[ta].river=0 end,
        function(st) st.tiles[ta].river=64 end,
        function(st) st.tiles[ta].river=1.5 end,
        function(st) st.tiles[ta].river="1" end,
        function(st) st.tiles[ta].river=-1 end,
        function(st) st.tiles[tb].river=nil end,
        function(st) st.tiles[ta].river=63; st.tiles[tb].river=63 end,
        function(st) st.tiles[boundary :: number].river=32 end,
        function(st) st.tiles[ta].terrain="Water" end,
        function(st) st.tiles[tb].terrain="Mountain" end,
    }
    for index,change in bad do assert(not variant(change),"rejects case "..index) end
    for index,change in bad do local copy=deep(good); change(copy.state); assert(Game.restore(copy)==nil,"restore rejects case "..index) end
    -- Sphere: pentagon edges carry rivers like any other; an asymmetric pentagon edge and a sixth bit are rejected.
    local sp=Game.new(31,{mapShape="Sphere",frequency=6,humanPlayers=2}); strip(sp)
    local sg=graphOf(sp); local pentagon: number?=nil
    for id,list in sg.neighbors do
        if #list~=5 then continue end
        local occupied=false; for _, u in sp.units do if u.tileId==id or table.find(list,u.tileId) then occupied=true end end
        if not occupied then pentagon=id; break end
    end
    assert(pentagon)
    local pn=sg.neighbors[pentagon :: number]
    for _, id in {pentagon :: number,pn[5],pn[4]} do local t=sp.tiles[id]; t.terrain="Plains"; t.resource=nil; t.improvement=nil end
    setRiver(sp,sg,pentagon :: number,pn[5],true)
    assert(sp.tiles[pentagon :: number].river==16,"the fifth neighbour of a pentagon is bit 4")
    local sphereGood=Game.serialize(sp); assert(Save.valid(sphereGood))
    local back=Game.restore(sphereGood); assert(back and equal(Game.serialize(back),sphereGood))
    local asym=deep(sphereGood); asym.state.tiles[pn[5]].river=nil; assert(not Save.valid(asym))
    local sixth=deep(sphereGood); sixth.state.tiles[pentagon :: number].river=48; assert(not Save.valid(sixth),"a pentagon has no sixth edge")
    -- A unit crossing that pentagon edge stops; one moving along a dry pentagon edge does not.
    local walker=place(sp,1,"Warrior",pentagon :: number)
    local cp=preview(sp,walker,pn[5]); assert(cp.riverCrossing and cp.movesLeft==0)
    local dp=preview(sp,walker,pn[4]); assert(not dp.riverCrossing and dp.movesLeft==1)
    -- The pentagon edge appears in the snapshot's riverMoves.
    local sv=Game.snapshot(sp,1); assert(table.find(sv.riverMoves[tostring(walker.id)],pn[5]) and not table.find(sv.riverMoves[tostring(walker.id)],pn[4]))
    checkRiverMoves(sp,1,sv)
end

-- 9. Determinism: solo games on generated maps with features and rivers (the AI paths with the same movement code)
-- replay identically, with or without saves between turns, and terminate.
do
    local function run(options: any,resume: boolean): any
        local s: any=Game.new(88,options)
        apply(s,1,{kind="FoundCity",unitId=firstUnit(s,1,"Settler").id})
        for turn=1,30 do
            if s.phase~="Playing" then break end
            if turn==3 and s.diplomacy.status~="War" then apply(s,1,{kind="DeclareWar",targetId=2}) end
            local view=Game.snapshot(s,1)
            local ids={}; for id in view.legalMoves do table.insert(ids,tonumber(id) :: number) end; table.sort(ids)
            for _, id in ids do
                local u=unitById(s,id); if not u or u.kind=="Worker" then continue end
                local list=Game.snapshot(s,1).legalMoves[tostring(id)]
                if list and #list>0 then apply(s,1,{kind="MoveUnit",unitId=id,tileId=list[#list]}) end
                if s.phase~="Playing" then break end
            end
            if s.phase~="Playing" then break end
            apply(s,1,{kind="EndTurn"})
            if resume then s=Game.restore(Game.serialize(s)) end
        end
        return Game.serialize(s)
    end
    for _, options in {{humanPlayers=1,radius=10,difficulty="Hard"},{humanPlayers=1,mapShape="Sphere",frequency=8,difficulty="Hard"}} do
        local first=run(options,false)
        local rivers,features=0,0; for _, t in first.state.tiles do if t.river then rivers += 1 end; if t.feature then features += 1 end end
        assert(rivers>0 and features>0)
        assert(equal(first,run(options,false)) and equal(first,run(options,true)),"features and rivers keep play deterministic")
    end
end

-- 10. Payload: a fully explored Huge map (hex radius 40 and sphere frequency 22) stays well inside the snapshot bounds;
-- features and rivers add a few percent.
do
    local function bytes(v: any): number
        local t=type(v)
        if t=="number" then return #tostring(v) elseif t=="string" then return #v+2 elseif t=="boolean" then return if v then 4 else 5 end
        if t=="table" then local n=2; for k,c in v do n += (if type(k)=="string" then #k+3 else #tostring(k)+1)+bytes(c)+1 end; return n end
        return 4
    end
    local hugeOptions: {any}={{radius=40,humanPlayers=2},{mapShape="Sphere",frequency=22,humanPlayers=2}}
    for _, options in hugeOptions do
        local s: any=Game.new(5,options)
        for _, p in s.players do p.explored={}; for id=1,#s.tiles do table.insert(p.explored,id) end end
        local started=os.clock(); local view=Game.snapshot(s,1); local elapsed=os.clock()-started
        local size=bytes(view)
        local bare=deep(s); strip(bare); local bareSize=bytes(Game.snapshot(bare,1))
        local save=bytes(Game.serialize(s)); local bareSave=bytes(Game.serialize(bare))
        assert(size<1500000 and elapsed<1.5,"snapshot "..size.." bytes in "..elapsed.." s")
        assert(size-bareSize<0.15*bareSize,"features and rivers add little to the snapshot")
        print(string.format("  %s Huge fully explored: snapshot %d bytes (%d without features and rivers, +%.1f%%) in %.0f ms; save %d bytes (%d without)",
            if options.mapShape then "Sphere" else "Hex",size,bareSize,(size-bareSize)/bareSize*100,elapsed*1000,save,bareSave))
    end
end

-- 11. riverMoves: the snapshot lists, for the actor's own units, the legal destinations whose move ends by crossing an
-- unbridged river, from the same search as legalMoves.
do
    -- Roads on both tiles suppress the crossing; a road on one side does not; partial moves and the zone of control.
    local s,c,g=arena(551); war(s)
    local k=sorted(g.neighbors[c])
    local k2: number?=nil; for _, id in k do if id~=k[1] and not adjacent(g,id,k[1]) then k2=id; break end end
    setRiver(s,g,c,k[1],true); setRiver(s,g,c,k2 :: number,true)
    s.tiles[c].road=true; s.tiles[k[1]].road=true
    local w=place(s,1,"Warrior",c)
    local view=Game.snapshot(s,1); local list=view.riverMoves[tostring(w.id)]
    assert(list and table.find(list,k2 :: number) and not table.find(list,k[1]),"a bridged crossing is not a river move")
    checkRiverMoves(s,1,view)
    -- With both roads removed both crossings are listed; with a third of a move the crossing still ends the move.
    s.tiles[c].road=nil; s.tiles[k[1]].road=nil
    view=Game.snapshot(s,1); list=view.riverMoves[tostring(w.id)]; assert(table.find(list,k[1]) and table.find(list,k2 :: number))
    w.moves=1/3; assert(checkRiverMoves(s,1)>=2)
    -- Zone of control and a river on the same step: listed (the preview reports both).
    local z,zc,zg=arena(552); war(z)
    place(z,2,"Warrior",zc)
    local zr=sorted(zg.neighbors[zc]); local from=zr[1]; local to: number?=nil
    for _, id in zg.neighbors[from] do if id~=zc and adjacent(zg,id,zc) then to=id; break end end
    setRiver(z,zg,from,to :: number,true)
    local mover=place(z,1,"Warrior",from); local zv=Game.snapshot(z,1)
    assert(table.find(zv.riverMoves[tostring(mover.id)],to :: number))
    checkRiverMoves(z,1,zv)
    -- No movement: no entry. Out of turn: nothing for either actor; the rival's units never appear.
    mover.moves=0; assert(Game.snapshot(z,1).riverMoves[tostring(mover.id)]==nil)
    local rivalView=Game.snapshot(z,2); assert(next(rivalView.riverMoves)==nil and not rivalView.canAct)
    -- Generated maps (hex and sphere): both actors over several rounds of moves.
    local total=0
    local options: {any}={{humanPlayers=2,radius=12},{humanPlayers=2,mapShape="Sphere",frequency=8}}
    for _, option in options do
        local t: any=Game.new(19,option)
        for _=1,6 do
            for owner=1,2 do
                total += checkRiverMoves(t,owner); assert(next(Game.snapshot(t,3-owner).riverMoves)==nil)
                local tv=Game.snapshot(t,owner); local ids={}
                for id in tv.legalMoves do table.insert(ids,tonumber(id) :: number) end; table.sort(ids)
                for _, id in ids do
                    local legal=Game.snapshot(t,owner).legalMoves[tostring(id)]
                    if legal and #legal>0 then apply(t,owner,{kind="MoveUnit",unitId=id,tileId=legal[1+(id*7)%#legal]}) end
                end
                apply(t,owner,{kind="EndTurn"})
            end
        end
    end
    -- Payload: 169 unpaved scouts on generated Huge maps; riverMoves adds a small fraction of the snapshot.
    local function bytes(v: any): number
        local kind=type(v)
        if kind=="number" then return #tostring(v) elseif kind=="string" then return #v+2 elseif kind=="boolean" then return if v then 4 else 5 end
        if kind=="table" then local n=2; for key,child in v do n += (if type(key)=="string" then #key+3 else #tostring(key)+1)+bytes(child)+1 end; return n end
        return 4
    end
    local huge: {any}={{radius=40,humanPlayers=2},{mapShape="Sphere",frequency=22,humanPlayers=2}}
    for _, option in huge do
        local h: any=Game.new(5,option)
        local occupied: {[number]: boolean}={}; for _, u in h.units do occupied[u.tileId]=true end
        local open={}; for _, tile in h.tiles do if passable(tile) and not occupied[tile.id] then table.insert(open,tile.id) end end
        local stride=math.max(1,math.floor(#open/(Rules.maxUnits-#h.units)))
        for i, id in open do if #h.units>=Rules.maxUnits then break end; if (i-1)%stride==0 then place(h,1,"Scout",id) end end
        local started=os.clock(); local hv=Game.snapshot(h,1); local elapsed=os.clock()-started
        local size,river=bytes(hv),bytes(hv.riverMoves); local units=0; for _ in hv.riverMoves do units += 1 end
        assert(size<1500000 and elapsed<1.5 and river<0.05*size,"riverMoves payload "..river.." of "..size)
        print(string.format("  %s Huge, %d units: snapshot %d bytes in %.0f ms, riverMoves %d bytes (%d units listed)",if option.mapShape then "Sphere" else "Hex",#h.units,size,elapsed*1000,river,units))
    end
    print(string.format("  riverMoves: equal to the previews' riverCrossing on fixtures and %d listed destinations over generated turns",total))
end

print("base features: rules, deterministic generation with symmetric river edges reaching water (pentagons included), yields, feature movement and river crossings equal to a reference search, feature defence and the river attack penalty in exact previews, improvements and founding, fog, pre-G4 saves and validation, deterministic AI replays and Huge-map payload passed")
