--!strict
-- Generated module-only Roblox form. Source: src/simulation/BaseSave.luau
-- Source SHA-256: ccf3c73b50ac4d54ba2b5d29359e499d8f239e79ac13398d6257810a62b0891e
-- Reproduce with tools/roblox-export.mjs; preserve MPL notices below.
-- Covered source: https://github.com/RoryODonovan/unciv-luau
-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- Obtain a copy at https://mozilla.org/MPL/2.0/.
--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Provenance-Kind: original
-- Original exact bounded hex version-1 / sphere version-2 trust boundary; validates before copying.
local Rules=require(script.Parent.BaseRules)
local HexMath=require(script.Parent.Parent.map.HexMath)
local SphereTopology=require(script.Parent.Parent.map.SphereTopology)
local WorldMap=require(script.Parent.WorldMap)
local BaseSave={}
-- Structural work budget: 4,921 tiles with all 10 fields and two fully explored players,
-- plus independently bounded units/cities/events. This is a hard bound, not an unbounded traversal.
local maxTreeEntries=81920
local function number(value: any,low: number,high: number): boolean return type(value)=="number" and value==value and value>=low and value<=high end
local function integer(value: any,low: number,high: number): boolean return number(value,low,high) and value%1==0 end
-- Movement is a multiple of 1/6: whole and half moves (every earlier save) and the thirds a road step leaves.
-- A third has no exact binary form and an encoder may shorten it (0.333333), so a value within 1e-6 of a move of
-- a sixth is accepted; restore snaps it to that sixth.
local function nearestSixth(value: number): number return math.round(value*6)/6 end
local function sixths(value: number): boolean return math.abs(value-nearestSixth(value))<=1e-6 end
-- Derived cost pace, shared rule configuration with BaseGame; no save schema field.
local function researchCost(maxTurns: number, base: number, firstPass: boolean?): number
    local pace=Rules.costPace
    local c=if firstPass then {exponent=1.5,minPercent=30,maxPercent=200} else pace.tech
    local percent=math.clamp(math.floor(100*(maxTurns/pace.turns)^c.exponent+0.5),c.minPercent,c.maxPercent)
    return math.max(1,math.floor(base*percent/100+0.5))
end
local function owner(value: any): boolean return value==1 or value==2 end
-- Barbarian units and their events carry this owner id (0), which no civilization uses.
local BARBARIAN=Rules.barbarians.ownerId
local function id(value: any): boolean return integer(value,1,1000000) end
local function text(value: any,limit: number): boolean return type(value)=="string" and #value>0 and #value<=limit end
local schemas: {[string]: {[string]: boolean}}={}
local function object(value: any,keys: string): boolean
    if type(value)~="table" or getmetatable(value)~=nil then return false end
    local allowed=schemas[keys]
    if not allowed then
        allowed={}; for key in string.gmatch(keys,"%S+") do allowed[key]=true end; schemas[keys]=allowed
    end
    for key in value do if type(key)~="string" or not allowed[key] then return false end end
    return true
end
local function array(value: any,limit: number): boolean
    if type(value)~="table" or getmetatable(value)~=nil or #value>limit then return false end
    local count=0
    for key in value do if not integer(key,1,#value) then return false end; count+=1 end
    return count==#value
end
local function plainTree(root: any): boolean
    if type(root)~="table" then return false end
    local pending: {{value: any,depth: number}}={{value=root,depth=1}}
    local seen: {[any]: boolean}={[root]=true}
    local entries=0
    while #pending>0 do
        local node=table.remove(pending) :: {value: any,depth: number}
        if getmetatable(node.value)~=nil or node.depth>10 then return false end
        for key,child in node.value do
            entries+=1; if entries>maxTreeEntries then return false end
            if type(key)=="string" then if #key>128 then return false end elseif not integer(key,1,maxTreeEntries) then return false end
            local kind=type(child)
            if kind=="table" then
                if seen[child] then return false end
                seen[child]=true; table.insert(pending,{value=child,depth=node.depth+1})
            elseif kind=="number" then if not number(child,-9007199254740991,9007199254740991) then return false end
            elseif kind=="string" then if #child>512 then return false end
            elseif kind~="boolean" then return false end
        end
    end
    return true
end
local function strings(values: any,known: any,limit: number): boolean
    if not array(values,limit) then return false end
    local seen={}
    for _,value in values do if type(value)~="string" or not known[value] or seen[value] then return false end; seen[value]=true end
    return true
end
local function knowledge(values: any,rules: any): boolean
    for _,value in values do for _,prerequisite in rules[value].prerequisites do if not table.find(values,prerequisite) then return false end end end
    return true
end
local function improvement(tile: any,kind: string): boolean
    local rule=Rules.improvements[kind]
    if not rule or rule.road or not table.find(rule.terrains,tile.terrain) then return false end
    if tile.feature~=nil and not table.find(Rules.features[tile.feature].improvements,kind) then return false end
    if kind=="Farm" or kind=="Mine" then return tile.resource==nil or table.find(rule.resources,tile.resource)~=nil end
    return tile.resource~=nil and table.find(rule.resources,tile.resource)~=nil
end
-- River masks: bit k marks the edge to the tile's (k+1)-th neighbour in ascending id order. Each marked edge must exist,
-- join two passable tiles and be marked on both sides. Topology is derived only when a tile has a river, from the
-- validated coordinates (Hex) or the public sphere descriptor for the validated frequency (Sphere).
local hexOffsets={{1,0},{0,1},{1,1},{-1,0},{0,-1},{-1,-1}}
local function rivers(s: any,sphere: boolean): boolean
    local any=false
    for _,tile in s.tiles do if tile.river~=nil then any=true; break end end
    if not any then return true end
    -- Neighbour lists, built only for river tiles and the tiles across their marked edges. Hex coordinates are validated
    -- integers within the radius, so each has a distinct numeric key (outside coordinates map to nothing).
    local cells=if sphere then SphereTopology.generate(s.frequency).cells else nil
    local width=if sphere then 0 else 2*s.radius+3
    local function key(x: number,y: number): number return (x+s.radius+1)*width+(y+s.radius+1) end
    local ids: {[number]: number}={}
    if not sphere then for id,tile in s.tiles do ids[key(tile.x,tile.y)]=id end end
    local lists: {[number]: {number}}={}
    local function neighborsOf(id: number): {number}
        if cells then return cells[id].neighbors end
        local list=lists[id]
        if list then return list end
        local tile=s.tiles[id]; list={}
        for _,offset in hexOffsets do local other=ids[key(tile.x+offset[1],tile.y+offset[2])]; if other then table.insert(list,other) end end
        table.sort(list); lists[id]=list; return list
    end
    for id,tile in s.tiles do
        local mask=tile.river
        if mask==nil then continue end
        local list=neighborsOf(id)
        if mask>=bit32.lshift(1,#list) or not Rules.terrains[tile.terrain].passable then return false end
        for index,other in list do
            if not bit32.btest(mask,bit32.lshift(1,index-1)) then continue end
            local opposite=s.tiles[other]; local back=table.find(neighborsOf(other),id)
            if opposite.river==nil or not back or not bit32.btest(opposite.river,bit32.lshift(1,back-1)) or not Rules.terrains[opposite.terrain].passable then return false end
        end
    end
    return true
end
function BaseSave.valid(saved: any): boolean
    if not plainTree(saved) or not object(saved,"format version state") or saved.format~="unciv-luau-base" or (saved.version~=1 and saved.version~=2) then return false end
    local s=saved.state
    if type(s)~="table" then return false end
    local sphere=saved.version==2
    if sphere and (s.mapShape~="Sphere" or not integer(s.frequency,1,22) or s.radius~=nil) then return false end
    if not object(s,if sphere then "seed mapShape frequency difficulty humanPlayers forest maxTurns cultureVictoryPolicies policyCostIncrease barbarians turn revision activePlayerId phase winner reason victoryType tiles units cities players diplomacy trades events nextEvent nextUnit nextCity nextTrade log" else "seed radius difficulty humanPlayers forest maxTurns cultureVictoryPolicies policyCostIncrease barbarians turn revision activePlayerId phase winner reason victoryType tiles units cities players diplomacy trades events nextEvent nextUnit nextCity nextTrade log") then return false end
    if not integer(s.seed,-9007199254740991,9007199254740991) or (not sphere and not integer(s.radius,Rules.minRadius,Rules.maxRadius)) or not integer(s.maxTurns,20,500) or not integer(s.turn,1,s.maxTurns) or not integer(s.revision,0,1000000000) then return false end
    if not owner(s.humanPlayers) or not owner(s.activePlayerId) or type(s.forest)~="boolean" or (s.phase=="Playing" and s.humanPlayers==1 and s.activePlayerId~=1) then return false end
    if s.difficulty~="Easy" and s.difficulty~="Normal" and s.difficulty~="Hard" then return false end
    -- Optional culture rules (absent in saves written before they existed: flat costs, six policies).
    if s.cultureVictoryPolicies~=nil and not integer(s.cultureVictoryPolicies,1,#Rules.policyOrder) then return false end
    if s.policyCostIncrease~=nil and not integer(s.policyCostIncrease,0,400) then return false end
    -- Optional barbarian record (absent in a match without barbarians and in every save written before them).
    local barbarians=s.barbarians
    if barbarians~=nil and (not object(barbarians,"camps nextCamp") or not id(barbarians.nextCamp) or not array(barbarians.camps,Rules.barbarians.maxCamps)) then return false end
    if not id(s.nextUnit) or not id(s.nextCity) or not id(s.nextTrade) or not integer(s.nextEvent,1,1000000000) then return false end
    if s.phase=="Playing" then if s.winner~=nil or s.reason~=nil or s.victoryType~=nil then return false end
    elseif s.phase=="Finished" then
        if not text(s.reason,256) then return false end
        if s.victoryType=="Draw" then
            if s.winner~=nil then return false end
        elseif not owner(s.winner) or (s.victoryType~="Science" and s.victoryType~="Culture" and s.victoryType~="Domination" and s.victoryType~="Score") then return false end
    else return false end
    if not array(s.tiles,Rules.maxTiles) or #s.tiles~=(if sphere then 10*s.frequency*s.frequency+2 else 1+3*s.radius*(s.radius+1)) or not array(s.units,Rules.maxUnits) or not array(s.cities,Rules.maxCities) or not array(s.players,2) or #s.players~=2 then return false end
    local coordinates,tiles={},{}
    for index,tile in s.tiles do
        if not object(tile,if sphere then "id terrain resource ownerId improvement road feature river" else "id x y terrain resource ownerId improvement road feature river") or tile.id~=index then return false end
        if not sphere and (not integer(tile.x,-s.radius,s.radius) or not integer(tile.y,-s.radius,s.radius) or HexMath.getDistanceXY(0,0,tile.x,tile.y)>s.radius) then return false end
        if type(tile.terrain)~="string" or not Rules.terrains[tile.terrain] or (tile.resource~=nil and (type(tile.resource)~="string" or not Rules.resources[tile.resource])) then return false end
        -- Optional feature (absent in saves written before features: none): a known feature on one of its terrains.
        if tile.feature~=nil and (type(tile.feature)~="string" or not Rules.features[tile.feature] or not table.find(Rules.features[tile.feature].terrains,tile.terrain)) then return false end
        if tile.resource~=nil then
            local resource=Rules.resources[tile.resource]
            if not table.find(Rules.improvements[resource.improvement].terrains,tile.terrain) then return false end
            if tile.feature~=nil and not table.find(Rules.features[tile.feature].improvements,resource.improvement) then return false end
        end
        -- Optional river edge mask (absent in saves written before rivers: none), checked against the topology below.
        if tile.river~=nil and not integer(tile.river,1,63) then return false end
        if tile.ownerId~=nil and not owner(tile.ownerId) then return false end
        if tile.road~=nil and (type(tile.road)~="boolean" or (tile.road and not Rules.terrains[tile.terrain].passable)) then return false end
        if tile.improvement~=nil and (type(tile.improvement)~="string" or not improvement(tile,tile.improvement)) then return false end
        if not sphere then
            local coordinate=tostring(tile.x)..":"..tostring(tile.y)
            if coordinates[coordinate] then return false end; coordinates[coordinate]=true
        end
        tiles[index]=tile
    end
    if not rivers(s,sphere) then return false end
    for index,p in s.players do
        if not object(p,"id human gold science culture happiness technologies policies research explored resources income goldenAge") or p.id~=index or p.human~=(index<=s.humanPlayers) then return false end
        -- Optional golden-age record (absent in saves written before golden ages: an empty meter, none active, none so far).
        if p.goldenAge~=nil then
            local g=p.goldenAge
            if not object(g,"progress turnsLeft ages") or not integer(g.progress,0,1000000000) or not integer(g.turnsLeft,0,1000) or not integer(g.ages,0,1000) then return false end
            if g.turnsLeft>0 and g.ages==0 then return false end
        end
        if not integer(p.gold,0,1000000000) or not integer(p.science,0,1000000000) or not integer(p.culture,0,1000000000) or not integer(p.happiness,-10000,10000) then return false end
        if not strings(p.technologies,Rules.technologies,#Rules.technologyOrder) or not strings(p.policies,Rules.policies,#Rules.policyOrder) or not knowledge(p.technologies,Rules.technologies) or not knowledge(p.policies,Rules.policies) then return false end
        if not array(p.explored,#s.tiles) then return false end
        local previous=0; for _,tileId in p.explored do if not integer(tileId,previous+1,#s.tiles) then return false end; previous=tileId end
        -- Improved resource tiles per resource (G7 adds Saltpeter and Oil). Strategic quantities are derived, never stored.
        if not object(p.resources,"Wheat Iron Horses Saltpeter Oil Gold Spices Deer") then return false end
        for _,count in p.resources do if not integer(count,1,#s.tiles) then return false end end
        if not object(p.income,"food production gold science culture maintenance") then return false end
        for _,key in {"food","production","gold","science","culture","maintenance"} do if not integer(p.income[key],if key=="gold" then -1000000 else 0,1000000) then return false end end
        if p.research~=nil then
            local r=p.research
            if not object(r,"id progress cost") or type(r.id)~="string" or not Rules.technologies[r.id] or table.find(p.technologies,r.id) then return false end
            local rule=Rules.technologies[r.id]
            local cost=researchCost(s.maxTurns,rule.cost)
            -- Accept pre-pacing and first-pass W2-D research; restore preserves its completed fraction.
            if (r.cost~=cost and r.cost~=rule.cost and r.cost~=researchCost(s.maxTurns,rule.cost,true)) or not integer(r.progress,0,r.cost-1) then return false end
            for _,prerequisite in rule.prerequisites do if not table.find(p.technologies,prerequisite) then return false end end
        end
    end
    local units,occupancy={},{}; local barbarianUnits=0
    for _,u in s.units do
        -- The entry's shape is checked before any field is read. A barbarian unit (owner 0) needs a match with barbarians.
        if not object(u,"id ownerId kind tileId hp moves fortified level xp promotions work") then return false end
        local barbarian=u.ownerId==BARBARIAN and barbarians~=nil
        if not id(u.id) or u.id>=s.nextUnit or units[u.id] or not (owner(u.ownerId) or barbarian) or not integer(u.tileId,1,#s.tiles) or occupancy[u.tileId] then return false end
        if type(u.kind)~="string" or not Rules.units[u.kind] then return false end
        local rule=Rules.units[u.kind]
        -- Barbarians research nothing; their units are military, never work, gain no experience and take no promotions.
        if barbarian then
            barbarianUnits+=1
            if barbarianUnits>Rules.barbarians.maxUnits or rule.strength<=0 or u.work~=nil or (u.xp~=nil and u.xp~=0) or u.promotions~=nil or u.level~=0 then return false end
        elseif rule.technology and not table.find(s.players[u.ownerId].technologies,rule.technology) then return false end
        if not Rules.terrains[tiles[u.tileId].terrain].passable or not integer(u.hp,1,rule.hp) or not number(u.moves,0,rule.moves) or not sixths(u.moves) or type(u.fortified)~="boolean" or not integer(u.level,0,#Rules.experienceThresholds) then return false end
        if u.fortified and rule.strength==0 then return false end
        -- Optional experience and promotions (absent in saves written before them: 0 and none). Each promotion is a
        -- distinct known id open to the unit's class, with its prerequisites taken, and the unit's experience has
        -- earned at least that many levels. Level counts the promotions taken, so it is at least their number; a level
        -- above it is a veteran level from before promotions existed, which carries no effect.
        if u.xp~=nil and (not integer(u.xp,0,Rules.maxExperience) or (rule.unitClass=="Civilian" and u.xp>0)) then return false end
        if u.promotions~=nil then
            if not strings(u.promotions,Rules.promotions,#Rules.promotionOrder) or #u.promotions>u.level or not knowledge(u.promotions,Rules.promotions) then return false end
            local earned=0; for _,threshold in Rules.experienceThresholds do if (u.xp or 0)>=threshold then earned+=1 end end
            if #u.promotions>earned then return false end
            for _,promotion in u.promotions do if not table.find(Rules.promotions[promotion].classes,rule.unitClass) then return false end end
        end
        if u.work~=nil then
            local w=u.work
            if not object(w,"improvement remaining") or u.kind~="Worker" or u.moves~=0 or type(w.improvement)~="string" or not Rules.improvements[w.improvement] or not integer(w.remaining,1,Rules.improvements[w.improvement].turns) then return false end
            local imp=Rules.improvements[w.improvement]
            if imp.technology and not table.find(s.players[u.ownerId].technologies,imp.technology) then return false end
            if not imp.road and not improvement(tiles[u.tileId],w.improvement) then return false end
        end
        units[u.id]=u; occupancy[u.tileId]=u
    end
    local cities,cityTiles,capitalOwners,wonders={},{},{},{}
    local focuses={Balanced=true,Food=true,Production=true,Gold=true,Science=true,Culture=true}
    for _,c in s.cities do
        if not object(c,"id ownerId originalOwnerId capital tileId name population food production queue hp buildings focus strikeTurn borderCulture borderTiles") or not id(c.id) or c.id>=s.nextCity or cities[c.id] or not owner(c.ownerId) or not owner(c.originalOwnerId) or type(c.capital)~="boolean" or not integer(c.tileId,1,#s.tiles) or cityTiles[c.tileId] then return false end
        if not text(c.name,80) or not integer(c.population,1,100) or not integer(c.food,0,1000000) or not integer(c.production,0,1000000) or not integer(c.hp,0,Rules.cityHp) or type(c.queue)~="string" or (c.queue~="" and not Rules.productionCosts[c.queue]) or type(c.focus)~="string" or not (focuses :: any)[c.focus] or not strings(c.buildings,Rules.buildings,#Rules.buildingOrder) then return false end
        if not Rules.terrains[tiles[c.tileId].terrain].passable or tiles[c.tileId].ownerId~=c.ownerId or table.find(c.buildings,c.queue) or (occupancy[c.tileId] and occupancy[c.tileId].ownerId~=c.ownerId) then return false end
        -- Optional city-combat field (absent in saves written before it: the city has never used a strike): the round
        -- whose ranged strike the city used, never later than the current round.
        if c.strikeTurn~=nil and not integer(c.strikeTurn,1,s.turn) then return false end
        if c.borderCulture~=nil and not number(c.borderCulture,0,1000000000) then return false end
        if c.borderTiles~=nil and not integer(c.borderTiles,0,1000000) then return false end
        if c.capital then if capitalOwners[c.originalOwnerId] then return false end; capitalOwners[c.originalOwnerId]=true end
        -- A world wonder stands in at most one city of the world.
        for _,building in c.buildings do
            if Rules.buildings[building].wonder then if wonders[building] then return false end; wonders[building]=true end
        end
        cities[c.id]=c; cityTiles[c.tileId]=true
    end
    -- No city queues a wonder that has been completed (completion switches every such queue).
    for _,c in s.cities do if wonders[c.queue] then return false end end
    -- Barbarian camps: distinct issued ids and distinct passable tiles with no city and no civilization's unit (one that
    -- entered would have destroyed it); `founded` and `lastSpawn` are rounds, founded <= lastSpawn <= turn.
    if barbarians~=nil then
        local campIds,campTiles={},{}
        for _,camp in barbarians.camps do
            if not object(camp,"id tileId founded lastSpawn") or not id(camp.id) or camp.id>=barbarians.nextCamp or campIds[camp.id] or not integer(camp.tileId,1,#s.tiles) or campTiles[camp.tileId] then return false end
            if not Rules.terrains[tiles[camp.tileId].terrain].passable or cityTiles[camp.tileId] or (occupancy[camp.tileId] and occupancy[camp.tileId].ownerId~=BARBARIAN) then return false end
            if not integer(camp.founded,1,s.turn) or not integer(camp.lastSpawn,camp.founded,s.turn) then return false end
            campIds[camp.id]=true; campTiles[camp.tileId]=true
        end
    end
    local d=s.diplomacy
    if not object(d,"status peaceOfferBy peaceUntil met warPlan") or (d.status~="Peace" and d.status~="War") or not integer(d.peaceUntil,0,s.maxTurns+8) then return false end
    if d.peaceOfferBy~=nil and (not owner(d.peaceOfferBy) or d.status~="War") then return false end
    -- Optional contact and pending AI declaration. The treaty value is captured to detect any later change.
    if d.met~=nil and type(d.met)~="boolean" then return false end
    if d.warPlan~=nil then
        local plan=d.warPlan
        if not object(plan,"by at peaceUntil") or not owner(plan.by) or s.players[plan.by].human or d.met~=true or d.status~="Peace" or not integer(plan.at,15,s.maxTurns+3) or not integer(plan.peaceUntil,0,s.maxTurns+8) then return false end
    end
    if not array(s.trades,8) or (d.status=="War" and #s.trades>0) then return false end
    local trades={}
    for _,t in s.trades do
        if not object(t,"id fromId toId giveGold receiveGold expires") or not id(t.id) or t.id>=s.nextTrade or trades[t.id] or not owner(t.fromId) or not owner(t.toId) or t.fromId==t.toId or not integer(t.giveGold,0,100000) or not integer(t.receiveGold,0,100000) or t.giveGold+t.receiveGold==0 or not integer(t.expires,s.turn,s.maxTurns+3) then return false end
        trades[t.id]=true
    end
    if not array(s.log,24) or not array(s.events,64) then return false end
    for _,message in s.log do if not text(message,256) then return false end end
    local kinds={Move=true,Attack=true,Capture=true,FoundCity=true,Production=true,Research=true,Growth=true,Starvation=true,Victory=true,Purchase=true,Upgrade=true,Improvement=true,Policy=true,War=true,Peace=true,Trade=true,Defeat=true,RangedAttack=true,Disband=true,UnitLost=true,CityLost=true,Eliminated=true,Promotion=true,CityStrike=true,WonderBuilt=true,WonderLost=true,GoldenAgeStarted=true,GoldenAgeEnded=true,CampCleared=true,Contact=true,WarWarning=true,BorderGrowth=true}
    local causes={Combat=true,Ranged=true,Upkeep=true,Captured=true,NoCities=true,NeverFounded=true,CapitalsLost=true,CityStrike=true,Happiness=true,Wonder=true}
    local previous=0
    for _,e in s.events do
        if not object(e,"id kind message tileId unitId ownerId amount public cause byOwnerId unitKind cityId wonder") or not integer(e.id,previous+1,s.nextEvent-1) or type(e.kind)~="string" or not (kinds :: any)[e.kind] or not text(e.message,256) then return false end
        if e.tileId~=nil and not integer(e.tileId,1,#s.tiles) then return false end
        if e.unitId~=nil and (not id(e.unitId) or e.unitId>=s.nextUnit) then return false end
        -- The barbarian owner (0) appears only in a match with barbarians: as the owner of a barbarian's Attack or
        -- UnitLost, and as the civilization-unit loser's byOwnerId of a UnitLost.
        local barbarianEvent=barbarians~=nil and (e.kind=="Attack" or e.kind=="UnitLost")
        -- A cleared camp exists only in a match with barbarians.
        if e.kind=="CampCleared" and barbarians==nil then return false end
        if e.ownerId~=nil and not owner(e.ownerId) and not (barbarianEvent and e.ownerId==BARBARIAN) then return false end
        if e.amount~=nil and not integer(e.amount,0,1000000) then return false end
        if e.public~=nil and type(e.public)~="boolean" then return false end
        if e.cause~=nil and (type(e.cause)~="string" or not (causes :: any)[e.cause]) then return false end
        if e.byOwnerId~=nil and not owner(e.byOwnerId) and not (barbarians~=nil and e.kind=="UnitLost" and e.byOwnerId==BARBARIAN) then return false end
        if e.unitKind~=nil and (type(e.unitKind)~="string" or not Rules.units[e.unitKind]) then return false end
        if e.cityId~=nil and (not id(e.cityId) or e.cityId>=s.nextCity) then return false end
        -- Optional wonder id (WonderBuilt, WonderLost and a wonder's GoldenAgeStarted): a known world wonder.
        if e.wonder~=nil and (type(e.wonder)~="string" or not Rules.buildings[e.wonder] or not Rules.buildings[e.wonder].wonder) then return false end
        if e.kind=="BorderGrowth" and (not owner(e.ownerId) or e.public==true or e.tileId==nil or e.cityId==nil) then return false end
        if e.kind=="Contact" or e.kind=="WarWarning" then
            -- These announcements must never smuggle a location or an entity through fog, including in a save.
            if e.tileId~=nil or e.unitId~=nil or e.cityId~=nil or e.unitKind~=nil or e.wonder~=nil or e.cause~=nil or e.byOwnerId~=nil or e.amount~=nil then return false end
            if e.kind=="Contact" then
                if e.public~=true or e.ownerId~=nil then return false end
            elseif not owner(e.ownerId) or e.public==true then return false end
        end
        previous=e.id
    end
    if #s.events==0 then if s.nextEvent~=1 then return false end
    -- Ids strictly increase and end at the last issued id. Gaps exist only in a full ring, which
    -- evicts routine events before losses and outcomes; a partial ring is contiguous.
    elseif previous~=s.nextEvent-1 or (#s.events<64 and s.events[1].id~=s.nextEvent-#s.events) then return false end
    if s.phase=="Playing" then
        for player=1,2 do
            local survives=false
            for _,c in s.cities do if c.ownerId==player then survives=true end end
            for _,u in s.units do if u.ownerId==player and u.kind=="Settler" then survives=true end end
            if not survives then return false end
        end
    end
    return true
end
local function copy(value: any): any
    if type(value)~="table" then return value end
    local result={}; for key,child in value do result[key]=copy(child) end; return result
end
function BaseSave.serialize(state: any): any
    local saved={format="unciv-luau-base",version=if state.mapShape=="Sphere" then 2 else 1,state=state}
    assert(BaseSave.valid(saved),"cannot serialize invalid base state")
    return copy(saved)
end
function BaseSave.restore(saved: any): (any?,string?)
    if not BaseSave.valid(saved) then return nil,"Unsupported or corrupt base-game save." end
    local state=copy(saved.state)
    -- Legacy borders: assign each owned tile within three to its nearest own city (lowest city id on a tie),
    -- then subtract the seven founding tiles. Never change ownership, including old population-radius territory.
    local needsBorders=false
    for _, c in state.cities do if c.borderTiles==nil then needsBorders=true end; if c.borderCulture==nil then c.borderCulture=0 end end
    if needsBorders then
        local map=if state.mapShape=="Sphere" then WorldMap.fromSphereTiles(state.tiles,state.frequency) else WorldMap.fromTiles(state.tiles,state.radius)
        local counts: {[number]: number}={}
        for _, c in state.cities do
            for _, tileId in WorldMap.range(map,c.tileId,3) do
                if state.tiles[tileId].ownerId~=c.ownerId then continue end
                local d=WorldMap.distance(map,c.tileId,tileId); local nearest=true
                for _, other in state.cities do
                    if other.ownerId~=c.ownerId or other.id==c.id then continue end
                    local od=WorldMap.cappedDistance(map,other.tileId,tileId,d+1)
                    if od<d or (od==d and other.id<c.id) then nearest=false; break end
                end
                if nearest then counts[c.id]=(counts[c.id] or 0)+1 end
            end
        end
        for _, c in state.cities do if c.borderTiles==nil then c.borderTiles=math.max(0,(counts[c.id] or 0)-7) end end
    end
    if state.diplomacy.met==nil then
        -- Old war saves imply contact. Peace saves use current sight, never the historical explored set.
        state.diplomacy.met=state.diplomacy.status=="War"
        if not state.diplomacy.met then
            local map=if state.mapShape=="Sphere" then WorldMap.fromSphereTiles(state.tiles,state.frequency) else WorldMap.fromTiles(state.tiles,state.radius)
            for actor=1,2 do
                local centers={}; for _, entities in {state.units,state.cities} do for _, entity in entities do if entity.ownerId==actor then table.insert(centers,entity.tileId) end end end
                local seen={}; for _, tileId in WorldMap.visibility(map,centers,2) do seen[tileId]=true end
                for _, entities in {state.units,state.cities} do for _, entity in entities do if entity.ownerId==3-actor and seen[entity.tileId] then state.diplomacy.met=true end end end
            end
            if state.diplomacy.met then
                table.insert(state.events,{id=state.nextEvent,kind="Contact",message="Contact established with the rival civilization.",public=true}); state.nextEvent+=1
                if #state.events>64 then
                    local retained={UnitLost=true,CityLost=true,Eliminated=true,Victory=true,WonderBuilt=true,WonderLost=true,GoldenAgeStarted=true,GoldenAgeEnded=true,CampCleared=true,Contact=true,WarWarning=true}
                    local drop=1; for i=1,#state.events-1 do local e=state.events[i]; if not (retained :: any)[e.kind] or e.ownerId==BARBARIAN then drop=i; break end end
                    table.remove(state.events,drop)
                end
            end
        end
    end
    local plan=state.diplomacy.warPlan
    if plan and (state.diplomacy.peaceUntil~=plan.peaceUntil or state.turn<state.diplomacy.peaceUntil) then state.diplomacy.warPlan=nil end
    -- Migrate legacy research to the derived cost, preserving its completed fraction (rounded down).
    -- Full and already-paced research are byte-identical; accumulated food/production stay absolute.
    for _, p in state.players do
        local r=p.research
        if r then
            local cost=researchCost(state.maxTurns,Rules.technologies[r.id].cost)
            if r.cost~=cost then r.progress=math.floor(r.progress*cost/r.cost); r.cost=cost end
        end
    end
    -- Canonical movement: each unit's moves becomes its exact sixth (1e-16 becomes 0, 0.333333 becomes 1/3).
    for _, u in state.units do u.moves=nearestSixth(u.moves) end
    return state,nil
end
return table.freeze(BaseSave)
