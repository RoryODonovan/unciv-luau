--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Provenance-Kind: original
-- Original deterministic civilization rules engine; not an Unciv parity implementation.
local Rules = require("./BaseRules")
local WorldMap = require("./WorldMap")
local Save = require("./BaseSave")
export type Options = {humanPlayers: number?, radius: number?, mapShape: string?, frequency: number?, difficulty: string?, forest: boolean?, maxTurns: number?, cultureVictoryPolicies: number?, policyCostIncrease: number?}
export type Command = {kind: "MoveUnit" | "RangedAttack", unitId: number, tileId: number}
    | {kind: "FoundCity" | "FortifyUnit" | "UpgradeUnit", unitId: number}
    | {kind: "BuildImprovement", unitId: number, improvement: string}
    | {kind: "SetProduction" | "Purchase", cityId: number, item: string}
    | {kind: "SetCityFocus", cityId: number, focus: string}
    | {kind: "Research", technology: string} | {kind: "AdoptPolicy", policy: string}
    | {kind: "DeclareWar" | "OfferPeace" | "AcceptPeace", targetId: number}
    | {kind: "ProposeTrade", targetId: number, giveGold: number, receiveGold: number}
    | {kind: "AcceptTrade" | "CancelTrade", tradeId: number} | {kind: "EndTurn"}
export type Tile = {id: number, x: number?, y: number?, terrain: string, resource: string?, ownerId: number?, improvement: string?, road: boolean?}
export type Unit = {id: number, ownerId: number, kind: string, tileId: number, hp: number, moves: number, fortified: boolean, level: number, work: {improvement: string, remaining: number}?}
export type City = {id: number, ownerId: number, originalOwnerId: number, capital: boolean, tileId: number, name: string, population: number, food: number, production: number, queue: string, hp: number, buildings: {string}, focus: string}
export type Research = {id: string, progress: number, cost: number}
export type Player = {id: number, human: boolean, gold: number, science: number, culture: number, happiness: number, technologies: {string}, policies: {string}, research: Research?, explored: {number}, resources: {[string]: number}, income: {food: number, production: number, gold: number, science: number, culture: number, maintenance: number}}
export type Event = {id: number, kind: string, message: string, tileId: number?, unitId: number?, ownerId: number?, amount: number?, public: boolean?, cause: string?, byOwnerId: number?, unitKind: string?}
export type Diplomacy = {status: string, peaceOfferBy: number?, peaceUntil: number}
export type Trade = {id: number, fromId: number, toId: number, giveGold: number, receiveGold: number, expires: number}
export type TileView = {id: number, x: number?, y: number?, visible: boolean, explored: boolean, terrain: string?, resource: string?, ownerId: number?, improvement: string?, road: boolean?, food: number?, production: number?, gold: number?}
export type CityView = {id: number, ownerId: number, originalOwnerId: number, capital: boolean, tileId: number, name: string, population: number, hp: number, food: number?, production: number?, queue: string?, buildings: {string}?, focus: string?}
export type Statistics = {cities: number, units: number, population: number, technologies: number, policies: number}
export type Progress = {cities: number, policies: number, era: number}
export type AttackPreview = {unitId: number, tileId: number, target: string, ranged: boolean, exact: boolean, hiddenDefense: boolean, dealt: number?, received: number?, dealtMin: number, dealtMax: number, receivedMin: number, receivedMax: number, attackerHp: number, defenderHp: number, attackerDefeated: string, defenderDefeated: string, captures: string}
export type Technology = Rules.Technology
export type Policy = Rules.Policy
export type State = {seed: number, radius: number?, mapShape: string?, frequency: number?, difficulty: string, humanPlayers: number, forest: boolean, maxTurns: number, cultureVictoryPolicies: number?, policyCostIncrease: number?, turn: number, revision: number, activePlayerId: number, phase: string, winner: number?, reason: string?, victoryType: string?, tiles: {Tile}, units: {Unit}, cities: {City}, players: {Player}, diplomacy: Diplomacy, trades: {Trade}, events: {Event}, nextEvent: number, nextUnit: number, nextCity: number, nextTrade: number, log: {string}}
export type View = {seed: number?, radius: number?, mapShape: string?, frequency: number?, difficulty: string, humanPlayers: number, turn: number, revision: number, activePlayerId: number, actorId: number, canAct: boolean, phase: string, winner: number?, reason: string?, victoryType: string?, gold: number, science: number, culture: number, happiness: number, research: Research?, technologies: {string}, policies: {string}, resources: {[string]: number}, income: {food: number, production: number, gold: number, science: number, culture: number, maintenance: number}, tiles: {TileView}, units: {Unit}, cities: {CityView}, events: {Event}, log: {string}, legalMoves: {[string]: {number}}, availableProduction: {string}, availableProductionByCity: {[string]: {string}}, availablePurchasesByCity: {[string]: {string}}, availableResearch: {Technology}, availablePolicies: {Policy}, availableImprovements: {[string]: {string}}, productionCosts: {[string]: number}, purchaseCosts: {[string]: number}, scores: {number}, statistics: {Statistics}, progress: {Progress}, cultureVictoryPolicies: number, policyCostIncrease: number, attackPreviews: {[string]: {AttackPreview}}, diplomacy: Diplomacy, trades: {Trade}, objectives: {string}}
local BaseGame = {}
local R: any = Rules
local W: any = WorldMap
local improvementOrder: {string} = R.improvementOrder or {"Farm","Mine","Pasture","Plantation","Camp","Road"}
local topology: {[any]: any} = setmetatable({}, {__mode = "k"}) :: any
local function copy(value: any): any
    if type(value) ~= "table" then return value end
    local result = {}; for key, child in value do result[key] = copy(child) end; return result
end
local function mapFor(s: any): any
    if topology[s] then return topology[s] end
    local map = if s.mapShape=="Sphere" then W.fromSphereTiles(s.tiles,s.frequency) else W.fromTiles(s.tiles,s.radius)
    topology[s] = map
    return map
end
local function distance(s: any, a: number, b: number): number return W.distance(mapFor(s), a, b) end
local function nearby(s: any, tileId: number, radius: number): {number}
    local map=mapFor(s); map.nearby=map.nearby or {}; map.nearbyOrder=map.nearbyOrder or {}
    local key=tostring(tileId)..":"..tostring(radius)
    if map.nearby[key] then return map.nearby[key] end
    if #map.nearbyOrder==64 then map.nearby[table.remove(map.nearbyOrder,1)]=nil end
    local ids=W.range(map,tileId,radius); map.nearby[key]=ids; table.insert(map.nearbyOrder,key); return ids
end
local function has(list: any, id: string): boolean return table.find(list, id) ~= nil end
local function unitById(s: any, id: number): any for _, unit in s.units do if unit.id == id then return unit end end; return nil end
local function cityById(s: any, id: number): any for _, city in s.cities do if city.id == id then return city end end; return nil end
local function occupants(s: any): (any, any)
    local units, cities = {}, {}; for _, u in s.units do units[u.tileId] = u end; for _, c in s.cities do cities[c.tileId] = c end; return units, cities
end
local function event(s: any, kind: string, message: string, tileId: number?, unitId: number?, ownerId: number?, amount: number?, public: boolean?, cause: string?, byOwnerId: number?, unitKind: string?)
    table.insert(s.events, {id=s.nextEvent, kind=kind, message=message, tileId=tileId, unitId=unitId, ownerId=ownerId, amount=amount, public=public, cause=cause, byOwnerId=byOwnerId, unitKind=unitKind})
    s.nextEvent += 1; if #s.events > 64 then table.remove(s.events, 1) end
end
-- Loss events are owned by the losing civilization, so its projection includes them whatever
-- its current fog. Saves written before these fields existed simply lack them.
local function unitLost(s: any, u: any, tileId: number, cause: string, byOwnerId: number?, damage: number?)
    event(s,"UnitLost","Your "..u.kind.." was destroyed.",tileId,u.id,u.ownerId,damage,nil,cause,byOwnerId,u.kind)
end
-- The culture victory threshold and per-adoption policy cost growth are stored per game.
-- A state without them (saved by an earlier library version) keeps the original flat rule.
local function cultureThreshold(s: any): number return s.cultureVictoryPolicies or R.cultureVictoryPolicies or 6 end
local function policyCost(s: any, p: any, policy: any): number
    return math.floor(policy.cost*(100+(s.policyCostIncrease or 0)*#p.policies)/100)
end
local function visible(s: any, owner: number): any
    local centers = {}; for _, u in s.units do if u.ownerId == owner then table.insert(centers, u.tileId) end end
    for _, c in s.cities do if c.ownerId == owner then table.insert(centers, c.tileId) end end
    local set = {}; for _, center in centers do for _, id in nearby(s,center,2) do set[id]=true end end; return set
end
local function refreshVision(s: any)
    for owner=1,2 do
        local discovered = {}; for _, id in s.players[owner].explored do discovered[id] = true end
        for id in visible(s,owner) do discovered[id] = true end
        local ids = {}; for id in discovered do table.insert(ids,id) end; table.sort(ids); s.players[owner].explored = ids
    end
end
local function removeUnit(s: any, id: number)
    for i,u in s.units do if u.id == id then table.remove(s.units,i); return end end
end
local function addUnit(s: any, owner: number, kind: string, tileId: number)
    local stats = R.units[kind]
    table.insert(s.units, {id=s.nextUnit, ownerId=owner, kind=kind, tileId=tileId, hp=stats.hp, moves=0, fortified=false, level=0})
    s.nextUnit += 1
end
local function claim(s: any, city: any)
    local ids = nearby(s,city.tileId,if city.population>=3 then R.cityWorkRadius else 1)
    for _, id in ids do local t=s.tiles[id]; if not t.ownerId or id==city.tileId then t.ownerId=city.ownerId end end
end
local function addCity(s: any, owner: number, tileId: number): any
    local capital=true; for _, c in s.cities do if c.originalOwnerId == owner and c.capital then capital=false end end
    local c = {id=s.nextCity, ownerId=owner, originalOwnerId=owner, capital=capital, tileId=tileId, name="City "..s.nextCity, population=1, food=0, production=0, queue="Warrior", hp=R.cityHp, buildings={}, focus="Balanced"}
    s.nextCity += 1; table.insert(s.cities,c); claim(s,c); return c
end
local function eligible(player: any, entry: any, list: any): boolean
    if has(list,entry.id) then return false end
    for _, prerequisite in entry.prerequisites do if not has(list,prerequisite) then return false end end
    return true
end
local function resourceInventory(s: any, owner: number): any
    local result: {[string]: number} = {}
    for _, tile in s.tiles do
        if tile.ownerId ~= owner or not tile.resource then continue end
        local resource=R.resources[tile.resource]
        if tile.improvement == resource.improvement then result[tile.resource]=(result[tile.resource] or 0)+1 end
    end
    return result
end
local function refreshEconomyState(s: any)
    for owner=1,2 do
        local p=s.players[owner]; p.resources=resourceInventory(s,owner); local happiness=R.baseHappiness
        for resource,count in p.resources do if count>0 then happiness += R.resources[resource].happiness end end
        for _, c in s.cities do if c.ownerId==owner then happiness -= R.unhappinessPerCity+c.population*R.unhappinessPerPopulation; for _, id in c.buildings do happiness += R.buildings[id].happiness end end end
        for _, id in p.policies do happiness += R.policies[id].happiness end
        p.happiness=happiness
    end
end
local function productionAvailable(s: any, city: any, item: string): boolean
    local entry=R.units[item] or R.buildings[item]
    if not entry then return false end
    local player=s.players[city.ownerId]
    if entry.technology and not has(player.technologies,entry.technology) then return false end
    if R.buildings[item] and has(city.buildings,item) then return false end
    if R.units[item] and #s.units >= R.maxUnits then return false end
    if entry.resource then
        local used=0; for _, u in s.units do if u.ownerId==city.ownerId and R.units[u.kind].resource==entry.resource then used += R.units[u.kind].resourceAmount or 1 end end
        if (resourceInventory(s,city.ownerId)[entry.resource] or 0) < used+(entry.resourceAmount or 1) then return false end
    end
    return true
end
local function spawnTile(s: any, city: any): number?
    local units,cities=occupants(s)
    local ids={city.tileId}; for _, id in mapFor(s).neighbors[city.tileId] do table.insert(ids,id) end; table.sort(ids)
    for _, id in ids do
        local tile=s.tiles[id]
        local territoryAllowed=not tile.ownerId or tile.ownerId==city.ownerId or s.diplomacy.status=="War"
        if not units[id] and R.terrains[tile.terrain].passable and territoryAllowed and (not cities[id] or cities[id].ownerId==city.ownerId) then return id end
    end
    return nil
end
local function complete(s: any, city: any, item: string, spawn: number?)
    if R.buildings[item] then table.insert(city.buildings,item); if city.queue==item then city.queue="Warrior" end
    else assert(spawn); addUnit(s,city.ownerId,item,spawn) end
    event(s,"Production","Completed "..item..".",city.tileId,nil,city.ownerId)
end
local function finish(s: any, winner: number, kind: string)
    s.phase="Finished"; s.winner=winner; s.victoryType=kind; s.reason=kind.." victory for civilization "..winner.."."
    event(s,"Victory",s.reason,nil,nil,winner,nil,true)
end
local function scores(s: any): (any,any)
    local values,stats={0,0},{}
    for owner=1,2 do
        local p=s.players[owner]; stats[owner]={cities=0,units=0,population=0,technologies=#p.technologies,policies=#p.policies}
        values[owner]=#p.technologies*R.score.technology+#p.policies*R.score.policy
    end
    for _, c in s.cities do stats[c.ownerId].cities += 1; stats[c.ownerId].population += c.population; values[c.ownerId] += R.score.city+c.population*R.score.population end
    for _, u in s.units do stats[u.ownerId].units += 1; values[u.ownerId] += R.score.unit end
    return values,stats
end
local function evaluate(s: any)
    if s.phase=="Finished" then return end
    for owner=1,2 do
        local cities,settlers,capitals,otherCapital=0,0,0,false
        for _, c in s.cities do
            if c.ownerId==owner then cities += 1 end
            if c.capital then capitals += 1; if c.originalOwnerId~=owner and c.ownerId==owner then otherCapital=true end end
        end
        for _, u in s.units do if u.ownerId==owner and u.kind=="Settler" then settlers += 1 end end
        if cities==0 and settlers==0 then
            local founded=false; for _, c in s.cities do if c.originalOwnerId==owner then founded=true end end
            event(s,"Eliminated","Civilization "..owner.." was eliminated.",nil,nil,owner,nil,true,if founded then "NoCities" else "NeverFounded",3-owner)
            finish(s,3-owner,"Domination"); return
        end
        if capitals==2 and otherCapital then
            local controls=true; for _, c in s.cities do if c.capital and c.ownerId~=owner then controls=false end end
            if controls then
                event(s,"Eliminated","Civilization "..(3-owner).." lost its capital.",nil,nil,3-owner,nil,true,"CapitalsLost",owner)
                finish(s,owner,"Domination"); return
            end
        end
        local p=s.players[owner]
        if #p.policies >= cultureThreshold(s) then finish(s,owner,"Culture"); return end
        if has(p.technologies,R.scienceVictoryTechnology or "Rocketry") then
            for _, c in s.cities do if c.ownerId==owner and has(c.buildings,R.scienceVictoryBuilding or "SpaceProject") then finish(s,owner,"Science"); return end end
        end
    end
end
local function movementCost(s: any, unit: any, fromId: number, toId: number, seen: any, units: any, cities: any): number?
    if not seen[toId] then return nil end
    local tile=s.tiles[toId]; local terrain=R.terrains[tile.terrain]
    if not terrain.passable then return nil end
    local occupant,city=units[toId],cities[toId]
    if occupant and occupant.id~=unit.id then return nil end
    if city and city.ownerId~=unit.ownerId then return nil end
    if tile.ownerId and tile.ownerId~=unit.ownerId and s.diplomacy.status~="War" then return nil end
    if tile.road and s.tiles[fromId].road then return R.roadMovement end
    return terrain.movement
end
local function reachable(s: any, unit: any, vision: any?, occupancyUnits: any?, occupancyCities: any?): any
    if unit.moves<=0 then return {} end
    local seen=vision or visible(s,unit.ownerId); local units,cities=occupancyUnits,occupancyCities
    if not units or not cities then units,cities=occupants(s) end
    return W.reachable(mapFor(s),unit.tileId,unit.moves,function(a: number,b: number) return movementCost(s,unit,a,b,seen,units,cities) end)
end
local function attackable(s: any, unit: any, target: number, seen: any, occupancyUnits: any?, occupancyCities: any?): boolean
    if not seen[target] or unit.moves<=0 or R.units[unit.kind].strength<=0 or s.diplomacy.status~="War" then return false end
    local units,cities=occupancyUnits,occupancyCities; if not units or not cities then units,cities=occupants(s) end
    local enemy=units[target] or cities[target]
    if not enemy or enemy.ownerId==unit.ownerId then return false end
    return W.inRange(mapFor(s),unit.tileId,target,math.max(1,R.units[unit.kind].range or 1))
end
local function attackTargets(s: any, unit: any, seen: any, units: any, cities: any): {number}
    if unit.moves<=0 or R.units[unit.kind].strength<=0 or s.diplomacy.status~="War" then return {} end
    local set={}
    for tileId in units do if attackable(s,unit,tileId,seen,units,cities) then set[tileId]=true end end
    for tileId in cities do if attackable(s,unit,tileId,seen,units,cities) then set[tileId]=true end end
    local ids={}; for tileId in set do table.insert(ids,tileId) end; table.sort(ids); return ids
end
local function buildingDefense(city: any): number
    local total=0; for _, b in city.buildings do total += R.buildings[b].defense or 0 end; return total
end
-- The most defence any city can gain from buildings. An enemy city's buildings are hidden.
local hiddenCityDefense=0; for _, id in R.buildingOrder do hiddenCityDefense += R.buildings[id].defense or 0 end
-- Deterministic damage for one strike, given the target city's building defence.
local function strike(s: any, unit: any, defender: any, city: any, target: number, cityDefense: number): (number, number, boolean)
    local ranged=(R.units[unit.kind].range or 1)>1
    local attack=if ranged then R.units[unit.kind].rangedStrength else R.units[unit.kind].strength
    attack=math.max(1,attack+unit.level*3)*(0.5+unit.hp/200)
    local defense=if defender then math.max(3,R.units[defender.kind].strength)+(if defender.fortified then 5 else 0) else 14+(city.population or 1)
    if city then defense += cityDefense end
    defense += R.terrains[s.tiles[target].terrain].defense or 0
    local dealt=math.clamp(math.floor(30*attack/math.max(1,defense)+0.5),8,65)
    local received=if ranged or (defender and R.units[defender.kind].strength==0) then 0 else math.clamp(math.floor(25*defense/attack+0.5),8,65)
    return dealt,received,ranged
end
local function combat(s: any, unit: any, target: number)
    local units,cities=occupants(s); local defender,city=units[target],cities[target]
    local dealt,received,ranged=strike(s,unit,defender,city,target,if city then buildingDefense(city) else 0)
    local enemyOwner=if defender then defender.ownerId else city.ownerId
    unit.hp -= received; unit.moves=0; unit.fortified=false; unit.work=nil
    if defender then defender.hp -= dealt
    else city.hp=math.max(0,city.hp-dealt) end
    event(s,"Attack","Battle dealt "..dealt.." damage.",target,unit.id,unit.ownerId,dealt)
    if defender and defender.hp<=0 then removeUnit(s,defender.id); unitLost(s,defender,target,if ranged then "Ranged" else "Combat",unit.ownerId,dealt) end
    if unit.hp<=0 then removeUnit(s,unit.id); unitLost(s,unit,unit.tileId,"Combat",enemyOwner,received); return end
    if not ranged and not select(1,occupants(s))[target] then
        if city and city.ownerId~=unit.ownerId then
            if city.hp==0 then
                local loser=city.ownerId
                city.ownerId=unit.ownerId; city.hp=50; city.population=math.max(1,city.population-1); city.production=0; city.queue="Warrior"; city.food=0
                local ids={target}; for _, id in mapFor(s).neighbors[target] do table.insert(ids,id) end
                for _, id in ids do s.tiles[id].ownerId=unit.ownerId end
                unit.tileId=target; event(s,"Capture","City captured.",target,unit.id,unit.ownerId)
                event(s,"CityLost",city.name.." was captured.",target,nil,loser,nil,nil,"Captured",unit.ownerId)
            end
        else unit.tileId=target end
    end
end
local function outcome(low: boolean, high: boolean): string return if low~=high then "Maybe" elseif low then "Yes" else "No" end
-- Fog-safe preview. It reads only the actor's unit, the visible defender (kind, hp and
-- fortification), the visible city population/hp and visible terrain. Hidden city buildings
-- widen the result to a range. Damage is monotonic in defence, so the bounds are exact.
local function previewFor(s: any, unit: any, target: number, units: any, cities: any): AttackPreview
    local defender,city=units[target],cities[target]
    local high=if city then hiddenCityDefense else 0
    local dealtMax,receivedMin,ranged=strike(s,unit,defender,city,target,0)
    local dealtMin,receivedMax=strike(s,unit,defender,city,target,high)
    local function result(dealt: number, received: number): (boolean, boolean, boolean)
        local attackerDead=unit.hp-received<=0
        local defenderDead=defender~=nil and defender.hp-dealt<=0
        local cityHp=if not city then 1 elseif defender then city.hp else math.max(0,city.hp-dealt)
        return attackerDead,defenderDead,not ranged and not attackerDead and city~=nil and (defender==nil or defenderDead) and cityHp==0
    end
    local attackerLow,defenderLow,captureLow=result(dealtMin,receivedMax)
    local attackerHigh,defenderHigh,captureHigh=result(dealtMax,receivedMin)
    local exact=dealtMin==dealtMax and receivedMin==receivedMax
    return {unitId=unit.id,tileId=target,target=if defender then "Unit" else "City",ranged=ranged,exact=exact,hiddenDefense=high>0,
        dealt=if exact then dealtMin else nil,received=if exact then receivedMin else nil,
        dealtMin=dealtMin,dealtMax=dealtMax,receivedMin=receivedMin,receivedMax=receivedMax,
        attackerHp=unit.hp,defenderHp=if defender then defender.hp else city.hp,
        attackerDefeated=outcome(attackerLow,attackerHigh),defenderDefeated=if defender then outcome(defenderLow,defenderHigh) else "No",
        captures=outcome(captureLow,captureHigh)}
end
local function moveUnit(s: any, unit: any, target: number): boolean
    local seen=visible(s,unit.ownerId)
    if attackable(s,unit,target,seen) then combat(s,unit,target); return true end
    local targets=reachable(s,unit); local cost=targets[target]
    if target==unit.tileId or not cost or cost>unit.moves then return false end
    unit.tileId=target; unit.moves -= cost; unit.fortified=false; unit.work=nil
    event(s,"Move","Unit moved.",target,unit.id,unit.ownerId); return true
end
local function improvementAvailable(s: any, unit: any, improvement: string): boolean
    local rule=R.improvements[improvement]; if not rule or unit.kind~="Worker" or unit.moves<=0 or unit.work then return false end
    local tile=s.tiles[unit.tileId]; if tile.ownerId~=unit.ownerId then return false end
    if rule.technology and not has(s.players[unit.ownerId].technologies,rule.technology) then return false end
    if rule.road then return not tile.road end
    if tile.improvement==improvement or not has(rule.terrains,tile.terrain) then return false end
    if #rule.resources>0 and tile.resource and not has(rule.resources,tile.resource) then return false end
    if (improvement=="Pasture" or improvement=="Plantation" or improvement=="Camp") and not tile.resource then return false end
    return true
end
local function yieldFor(tile: any): any
    local result=copy(R.terrains[tile.terrain].yields)
    for _, key in {"food","production","gold","science","culture"} do result[key]=result[key] or 0 end
    if tile.resource then for key,value in R.resources[tile.resource].yields do result[key] += value end end
    if tile.improvement then for key,value in R.improvements[tile.improvement].yields do result[key] += value end end
    return result
end
local function economy(s: any, owner: number)
    local p=s.players[owner]; p.resources=resourceInventory(s,owner)
    local population,cityCount,happiness=0,0,R.baseHappiness
    for resource,count in p.resources do if count>0 then happiness += R.resources[resource].happiness or 0 end end
    for _, c in s.cities do if c.ownerId==owner then cityCount += 1; population += c.population; for _, b in c.buildings do happiness += R.buildings[b].happiness or 0 end end end
    local discount=0; for _, policy in p.policies do happiness += R.policies[policy].happiness or 0; discount += R.policies[policy].maintenanceDiscount or 0 end
    p.happiness=happiness-cityCount*R.unhappinessPerCity-population*R.unhappinessPerPopulation
    local income: {[string]: number}={food=0,production=0,gold=0,science=0,culture=0,maintenance=0}
    local worked={}; local _,cityTiles=occupants(s)
    local cityOrder: {any}={}; for _, city in s.cities do table.insert(cityOrder,city) end
    table.sort(cityOrder,function(a: any,b: any) return a.id<b.id end)
    for _, c in cityOrder do
        if c.ownerId~=owner then continue end
        -- The city center is free; each citizen works one distinct nearby owned tile.
        local candidates: {any}={}
        claim(s,c)
        for _, id in nearby(s,c.tileId,R.cityWorkRadius) do
            local tile=s.tiles[id]; if tile.ownerId==owner and not cityTiles[id] and not worked[id] then table.insert(candidates,{id=id,yields=yieldFor(tile)}) end
        end
        local focus=c.focus
        local function rank(y: any): number
            local weight: {[string]: number}={food=2,production=2,gold=1,science=1,culture=1}; local key=string.lower(focus)
            if weight[key] then weight[key]=6 end
            local total=0; for k,w in weight do total += y[k]*w end; return total
        end
        table.sort(candidates,function(a: any,b: any) local first,second=rank(a.yields),rank(b.yields); return if first==second then a.id<b.id else first>second end)
        local yields: {[string]: number}=copy(R.cityBaseYields); yields.science += c.population
        for index=1,math.min(c.population,#candidates) do local row=candidates[index]; worked[row.id]=true; for key,value in row.yields do yields[key] += value end end
        for _, building in c.buildings do local b=R.buildings[building]; income.maintenance += b.maintenance; for key,value in b.yields do yields[key] += value end end
        for _, policy in p.policies do for key,value in R.policies[policy].yields do yields[key] += value end end
        if c.focus=="Science" or c.focus=="Culture" then
            local converted=math.floor(yields.production/2); yields.production -= converted; yields[string.lower(c.focus)] += converted
        end
        local food=yields.food-c.population*R.foodPerPopulation
        if p.happiness<0 and food>0 then food=math.floor(food/2) end
        c.food += food
        local threshold=R.growthBase+c.population*R.growthPerPopulation
        if c.food>=threshold and p.happiness>=0 and c.population<R.maxPopulation then c.food -= threshold; c.population += 1; event(s,"Growth","City grew.",c.tileId,nil,owner,c.population)
        elseif c.food<0 then
            if c.population>1 then c.population -= 1; event(s,"Starvation","City lost population.",c.tileId,nil,owner,c.population) end
            c.food=0
        end
        local production=yields.production
        if p.happiness<=-5 then production=math.max(1,math.floor(production/2)) end
        if not p.human then production=math.max(1,math.floor(production*(if s.difficulty=="Easy" then 0.75 elseif s.difficulty=="Hard" then 1.25 else 1))) end
        c.production += production; c.hp=math.min(R.cityHp,c.hp+5)
        for key,value in yields do income[key] += value end
        if productionAvailable(s,c,c.queue) and c.production>=(R.productionCosts[c.queue] or math.huge) then
            local spawn=spawnTile(s,c)
            if R.buildings[c.queue] or spawn then local item=c.queue; c.production -= R.productionCosts[item]; complete(s,c,item,spawn) end
        end
    end
    for _, u in s.units do if u.ownerId==owner then income.maintenance += R.units[u.kind].maintenance end end
    local rawMaintenance=income.maintenance
    local multiplier=1-math.min(0.75,discount)
    income.maintenance=math.max(0,math.floor(rawMaintenance*multiplier))
    income.gold -= income.maintenance
    -- Insolvency retires the newest maintained military units before applying a
    -- science penalty for any remaining building deficit. Zero gold cannot
    -- sustain an army whose upkeep exceeds recurring income.
    while p.gold+income.gold<0 do
        local candidate: any=nil
        for _, u in s.units do if u.ownerId==owner and R.units[u.kind].maintenance>0 and (not candidate or u.id>candidate.id) then candidate=u end end
        if not candidate then break end
        local prior=income.maintenance
        rawMaintenance -= R.units[candidate.kind].maintenance
        income.maintenance=math.max(0,math.floor(rawMaintenance*multiplier))
        income.gold += prior-income.maintenance
        removeUnit(s,candidate.id); event(s,"Disband","Unit retired because upkeep exceeds available gold.",candidate.tileId,candidate.id,owner,nil,nil,"Upkeep",nil,candidate.kind)
    end
    if p.gold+income.gold<0 then income.science=math.max(0,income.science+p.gold+income.gold) end
    p.gold=math.max(0,p.gold+income.gold); p.science += income.science; p.culture += income.culture; p.income=income
    if p.research then
        p.research.progress += income.science
        if p.research.progress>=p.research.cost then local technology=p.research.id; table.insert(p.technologies,technology); p.research=nil; event(s,"Research","Technology completed: "..technology,nil,nil,owner) end
    end
    for _, u in s.units do
        if u.ownerId~=owner or not u.work then continue end
        local tile=s.tiles[u.tileId]
        if tile.ownerId~=owner then u.work=nil; continue end
        u.work.remaining -= 1
        if u.work.remaining<=0 then
            local id=u.work.improvement; if R.improvements[id].road then tile.road=true else tile.improvement=id end
            u.work=nil; event(s,"Improvement","Completed "..id..".",tile.id,u.id,owner)
        end
    end
    p.resources=resourceInventory(s,owner)
end
local function beginTurn(s: any, owner: number)
    s.activePlayerId=owner
    for _, u in s.units do
        if u.ownerId~=owner then continue end
        u.moves=if u.work then 0 else R.units[u.kind].moves
        if u.fortified then u.hp=math.min(R.units[u.kind].hp,u.hp+15)
        elseif s.tiles[u.tileId].ownerId==owner then u.hp=math.min(R.units[u.kind].hp,u.hp+5) end
    end
    refreshVision(s)
end
local function foundAllowed(s: any, unit: any): boolean
    if #s.cities>=R.maxCities or unit.kind~="Settler" or unit.moves<=0 or not R.terrains[s.tiles[unit.tileId].terrain].passable then return false end
    local t=s.tiles[unit.tileId]; if t.ownerId and t.ownerId~=unit.ownerId then return false end
    for _, c in s.cities do if W.inRange(mapFor(s),c.tileId,unit.tileId,2) then return false end end
    return true
end
local function ai(s: any, owner: number)
    local p=s.players[owner]
    if not p.research then for _, id in R.technologyOrder do local tech=R.technologies[id]; if eligible(p,tech,p.technologies) then p.research={id=id,progress=0,cost=tech.cost}; break end end end
    for _, id in R.policyOrder do local policy=R.policies[id]; local cost=policyCost(s,p,policy); if eligible(p,policy,p.policies) and p.culture>=cost then p.culture -= cost; table.insert(p.policies,id); event(s,"Policy","Policy adopted: "..id,nil,nil,owner); break end end
    if s.diplomacy.peaceOfferBy and s.diplomacy.peaceOfferBy~=owner then
        local own,enemy=0,0; for _, u in s.units do if R.units[u.kind].strength>0 then if u.ownerId==owner then own += 1 else enemy += 1 end end end
        if own<=enemy or s.turn%4==0 then s.diplomacy.status="Peace"; s.diplomacy.peaceOfferBy=nil; s.diplomacy.peaceUntil=s.turn+8; event(s,"Peace","Peace agreed.",nil,nil,nil,nil,true) end
    end
    for i=#s.trades,1,-1 do
        local trade=s.trades[i]
        if trade.toId==owner and s.diplomacy.status=="Peace" and trade.giveGold>=trade.receiveGold and p.gold>=trade.receiveGold and s.players[trade.fromId].gold>=trade.giveGold then
            s.players[trade.fromId].gold += trade.receiveGold-trade.giveGold; p.gold += trade.giveGold-trade.receiveGold
            table.remove(s.trades,i); event(s,"Trade","Trade accepted.",nil,nil,nil,nil,true)
        end
    end
    if s.diplomacy.status=="Peace" and s.turn>=15 and s.turn>=s.diplomacy.peaceUntil and s.turn%5==0 then s.diplomacy.status="War"; s.diplomacy.peaceOfferBy=nil; s.trades={}; event(s,"War","War declared.",nil,nil,nil,nil,true) end
    local units={}; for _, u in s.units do if u.ownerId==owner then table.insert(units,u.id) end end
    for _, id in units do
        local u=unitById(s,id); if not u then continue end
        if foundAllowed(s,u) then local c=addCity(s,owner,u.tileId); removeUnit(s,u.id); event(s,"FoundCity","City founded.",c.tileId,nil,owner); continue end
        if u.kind=="Worker" and not u.work then
            local chosen: string?=nil
            for _, improvement in improvementOrder do if (not s.tiles[u.tileId].improvement or improvement=="Road") and improvementAvailable(s,u,improvement) then chosen=improvement; break end end
            if chosen then u.work={improvement=chosen,remaining=R.improvements[chosen].turns}; u.moves=0
            else
                local targets=reachable(s,u); local best: number?=nil
                for _, tile in s.tiles do if targets[tile.id] and tile.id~=u.tileId and tile.ownerId==owner and not tile.improvement and (not best or tile.resource) then best=tile.id; if tile.resource then break end end end
                if best then moveUnit(s,u,best) end
            end
            continue
        end
        if u.work or u.moves<=0 then continue end
        if R.units[u.kind].strength>0 and u.hp<40 then u.fortified=true; u.moves=0; continue end
        local seen=visible(s,owner); local occupiedUnits,occupiedCities=occupants(s)
        local attack=attackTargets(s,u,seen,occupiedUnits,occupiedCities)[1]
        if attack then combat(s,u,attack); continue end
        local targets=reachable(s,u); local best: number?=nil; local bestRank=-math.huge
        local discovered={}; for _, tileId in p.explored do discovered[tileId]=true end
        for tileId in targets do
            if tileId==u.tileId then continue end
            local rank=0
            for _, neighbor in mapFor(s).neighbors[tileId] do if not discovered[neighbor] then rank += 10 end end
            if s.diplomacy.status=="War" then for _, c in s.cities do if c.ownerId~=owner and seen[c.tileId] then rank += 30-distance(s,tileId,c.tileId)*5 end end end
            if u.kind=="Settler" then for _, c in s.cities do if c.ownerId==owner or seen[c.tileId] then rank += W.cappedDistance(mapFor(s),tileId,c.tileId,4)*4 end end end
            rank += (tileId+s.turn)%3
            if rank>bestRank or (rank==bestRank and (not best or tileId<best)) then best=tileId; bestRank=rank end
        end
        if best then moveUnit(s,u,best) end
    end
    for _, c in s.cities do
        if c.ownerId~=owner then continue end
        local counts: {[string]: number}={}; for _, u in s.units do if u.ownerId==owner then counts[u.kind]=(counts[u.kind] or 0)+1 end end
        local priorities: {string}={}
        if has(p.technologies,"Rocketry") then table.insert(priorities,"SpaceProject") end
        if not counts.Worker then table.insert(priorities,"Worker") end
        for _, item in {"Monument","Granary","Library","Market","Colosseum","Workshop","University"} do table.insert(priorities,item) end
        local ownCities=0; for _, city in s.cities do if city.ownerId==owner then ownCities += 1 end end
        if ownCities<3 and not counts.Settler then table.insert(priorities,"Settler") end
        for i=#R.unitOrder,1,-1 do local item=R.unitOrder[i]; if R.units[item].strength>0 then table.insert(priorities,item) end end
        for _, item in priorities do if productionAvailable(s,c,item) then c.queue=item; break end end
    end
    refreshVision(s)
end
local function endTurn(s: any, owner: number)
    economy(s,owner); refreshVision(s); evaluate(s)
    if s.phase=="Finished" then return end
    if owner==1 then
        beginTurn(s,2)
        if s.players[2].human then return end
        ai(s,2); economy(s,2); refreshVision(s); evaluate(s)
        s.activePlayerId=1
        if s.phase=="Finished" then return end
    end
    for i=#s.trades,1,-1 do if s.trades[i].expires<=s.turn then table.remove(s.trades,i) end end
    if s.turn>=s.maxTurns then local values=scores(s); finish(s,if values[1]>=values[2] then 1 else 2,"Score"); return end
    s.turn += 1; beginTurn(s,1)
end
function BaseGame.new(seed: number?, options: Options?): State
    local o: Options=options or {}; local supplied=seed or 1; local radius=o.radius or 4; local humans=o.humanPlayers or 1; local difficulty=o.difficulty or "Normal"; local turns=o.maxTurns or 120
    local threshold=o.cultureVictoryPolicies or R.cultureVictoryPolicies or 6; local increase=o.policyCostIncrease or 50
    assert(type(supplied)=="number" and supplied==supplied and math.abs(supplied)<=9007199254740991 and supplied%1==0,"seed must be a finite integer")
    assert(radius%1==0 and radius>=R.minRadius and radius<=R.maxRadius,"radius must be 3 to 40")
    assert(humans==1 or humans==2,"humanPlayers must be 1 or 2")
    assert(difficulty=="Easy" or difficulty=="Normal" or difficulty=="Hard","unknown difficulty")
    assert(turns%1==0 and turns>=20 and turns<=500,"maxTurns must be 20 to 500")
    assert(type(threshold)=="number" and threshold%1==0 and threshold>=1 and threshold<=#R.policyOrder,"cultureVictoryPolicies must be 1 to "..#R.policyOrder)
    assert(type(increase)=="number" and increase%1==0 and increase>=0 and increase<=400,"policyCostIncrease must be 0 to 400")
    assert(o.mapShape==nil or o.mapShape=="Hex" or o.mapShape=="Sphere","unknown map shape")
    assert(o.mapShape=="Sphere" or o.frequency==nil,"frequency requires Sphere")
    local map=if o.mapShape=="Sphere" then W.generateSphere(supplied,o.frequency or 2) else W.generate(supplied,radius)
    local s: any={seed=supplied,radius=radius,difficulty=difficulty,humanPlayers=humans,forest=o.forest==true,maxTurns=turns,cultureVictoryPolicies=threshold,policyCostIncrease=increase,turn=1,revision=0,activePlayerId=1,phase="Playing",tiles=map.tiles,units={},cities={},players={},diplomacy={status="Peace",peaceUntil=0},trades={},events={},nextEvent=1,nextUnit=1,nextCity=1,nextTrade=1,log={}}
    if o.mapShape=="Sphere" then s.mapShape="Sphere"; s.frequency=map.frequency; s.radius=nil end
    topology[s]=map
    for owner=1,2 do table.insert(s.players,{id=owner,human=owner<=humans,gold=30,science=0,culture=0,happiness=9,technologies={},policies={},explored={},resources={},income={food=0,production=0,gold=0,science=0,culture=0,maintenance=0}}) end
    local starts=map.startIds
    assert(starts and #starts==2 and W.distance(map,starts[1],starts[2])>=3,"missing or adjacent starting sites")
    local deployed={[starts[1]]=true,[starts[2]]=true}
    for owner=1,2 do
        local start=starts[owner]; assert(s.tiles[start] and R.terrains[s.tiles[start].terrain].passable,"invalid starting tile")
        if owner==2 and humans==1 then addCity(s,owner,start) else addUnit(s,owner,"Settler",start) end
        for _,kind in {"Warrior","Worker"} do
            local deployment=nil
            for _,id in map.neighbors[start] do
                if not deployed[id] and R.terrains[s.tiles[id].terrain].passable then deployment=id; break end
            end
            assert(deployment,"starting site needs free passable deployment neighbors")
            deployed[deployment]=true; addUnit(s,owner,kind,deployment)
        end
    end
    for _, unit in s.units do unit.moves=R.units[unit.kind].moves end
    refreshVision(s); refreshEconomyState(s); return s :: State
end
local function finiteId(value: any): boolean return type(value)=="number" and value==value and value%1==0 and value>=1 and value<=1000000 end
local schemas: any={MoveUnit={unitId=true,tileId=true},RangedAttack={unitId=true,tileId=true},FoundCity={unitId=true},FortifyUnit={unitId=true},UpgradeUnit={unitId=true},BuildImprovement={unitId=true,improvement=true},SetProduction={cityId=true,item=true},Purchase={cityId=true,item=true},SetCityFocus={cityId=true,focus=true},Research={technology=true},AdoptPolicy={policy=true},DeclareWar={targetId=true},OfferPeace={targetId=true},AcceptPeace={targetId=true},ProposeTrade={targetId=true,giveGold=true,receiveGold=true},AcceptTrade={tradeId=true},CancelTrade={tradeId=true},EndTurn={}}
function BaseGame.apply(state: State, actorId: number, command: Command): {ok: boolean, message: string}
    local s: any=state; local cmd: any=command
    local function reject(message: string): {ok: boolean,message: string} return {ok=false,message=message} end
    if s.phase~="Playing" then return reject("The match has finished.") end
    if actorId~=s.activePlayerId or not s.players[actorId] or not s.players[actorId].human then return reject("Wait for your civilization's turn.") end
    if type(cmd)~="table" or getmetatable(cmd)~=nil or type(cmd.kind)~="string" or not schemas[cmd.kind] then return reject("Invalid command.") end
    local schema=schemas[cmd.kind]
    for key,value in cmd do if key~="kind" and (not schema[key] or (type(value)~="string" and type(value)~="number")) then return reject("Invalid command fields.") end end
    for key in schema do if cmd[key]==nil then return reject("Missing command field.") end end
    local p=s.players[actorId]
    if cmd.unitId~=nil then
        if not finiteId(cmd.unitId) then return reject("Invalid unit identifier.") end
        local u=unitById(s,cmd.unitId); if not u or u.ownerId~=actorId then return reject("Select your unit.") end
        if cmd.kind=="RangedAttack" then
            if not finiteId(cmd.tileId) or not s.tiles[cmd.tileId] or (R.units[u.kind].range or 1)<=1 or not attackable(s,u,cmd.tileId,visible(s,actorId)) then return reject("Choose a visible enemy within ranged attack distance.") end
            combat(s,u,cmd.tileId)
        elseif cmd.kind=="MoveUnit" then
            if not finiteId(cmd.tileId) or not s.tiles[cmd.tileId] or not moveUnit(s,u,cmd.tileId) then return reject("Destination is unavailable or movement is insufficient.") end
        elseif cmd.kind=="FoundCity" then
            if not foundAllowed(s,u) then return reject("A settler needs a free site at least three tiles from cities.") end
            local c=addCity(s,actorId,u.tileId); removeUnit(s,u.id); event(s,"FoundCity","City founded.",c.tileId,nil,actorId)
        elseif cmd.kind=="FortifyUnit" then
            if u.moves<=0 or u.fortified or R.units[u.kind].strength<=0 then return reject("A military unit needs movement to fortify.") end
            u.fortified=true; u.moves=0
        elseif cmd.kind=="UpgradeUnit" then
            local nextKind=R.units[u.kind].upgradeTo
            if not nextKind or u.moves<=0 or not has(p.technologies,R.units[nextKind].technology or "") then return reject("Upgrade technology is unavailable.") end
            local city={ownerId=actorId,buildings={}}
            local cost=math.max(20,R.units[nextKind].cost-R.units[u.kind].cost)*2
            if not productionAvailable(s,city,nextKind) or p.gold<cost then return reject("Upgrade requires gold and strategic resources.") end
            p.gold -= cost; u.kind=nextKind; u.moves=0; event(s,"Upgrade","Unit upgraded.",u.tileId,u.id,actorId)
        elseif cmd.kind=="BuildImprovement" then
            if type(cmd.improvement)~="string" or not improvementAvailable(s,u,cmd.improvement) then return reject("Improvement is unavailable on this tile.") end
            u.work={improvement=cmd.improvement,remaining=R.improvements[cmd.improvement].turns}; u.moves=0
        end
    elseif cmd.cityId~=nil then
        if not finiteId(cmd.cityId) then return reject("Invalid city identifier.") end
        local c=cityById(s,cmd.cityId); if not c or c.ownerId~=actorId then return reject("Select your city.") end
        if cmd.kind=="SetCityFocus" then
            if not has({"Balanced","Food","Production","Gold","Science","Culture"},cmd.focus) or c.focus==cmd.focus then return reject("Choose a different valid city focus.") end
            c.focus=cmd.focus
        else
            if type(cmd.item)~="string" or not productionAvailable(s,c,cmd.item) then return reject("Production item is unavailable.") end
            if cmd.kind=="Purchase" then
                local cost=R.purchaseCosts[cmd.item]; local spawn=spawnTile(s,c)
                if p.gold<cost or (not R.buildings[cmd.item] and not spawn) then return reject("Purchase needs gold and a free deployment tile.") end
                p.gold -= cost; complete(s,c,cmd.item,spawn)
            else
                if c.queue==cmd.item then return reject("Already producing this item.") end; c.queue=cmd.item
            end
        end
    elseif cmd.kind=="Research" then
        local tech=if type(cmd.technology)=="string" then R.technologies[cmd.technology] else nil
        if not tech or not eligible(p,tech,p.technologies) or (p.research and p.research.id==tech.id) then return reject("Research is unavailable.") end
        p.research={id=tech.id,progress=0,cost=tech.cost}
    elseif cmd.kind=="AdoptPolicy" then
        local policy=if type(cmd.policy)=="string" then R.policies[cmd.policy] else nil
        if not policy or not eligible(p,policy,p.policies) or p.culture<policyCost(s,p,policy) then return reject("Policy requires culture and prerequisites.") end
        p.culture -= policyCost(s,p,policy); table.insert(p.policies,policy.id); event(s,"Policy","Policy adopted: "..policy.id,nil,nil,actorId)
    elseif cmd.targetId~=nil then
        if cmd.targetId~=3-actorId then return reject("Choose the other civilization.") end
        if cmd.kind=="DeclareWar" then
            if s.diplomacy.status=="War" or s.turn<s.diplomacy.peaceUntil then return reject("War is unavailable during this peace treaty.") end
            s.diplomacy.status="War"; s.diplomacy.peaceOfferBy=nil; s.trades={}; event(s,"War","War declared.",nil,nil,nil,nil,true)
        elseif cmd.kind=="OfferPeace" then
            if s.diplomacy.status~="War" or s.diplomacy.peaceOfferBy==actorId then return reject("A peace offer is unavailable.") end
            s.diplomacy.peaceOfferBy=actorId
        elseif cmd.kind=="AcceptPeace" then
            if s.diplomacy.status~="War" or s.diplomacy.peaceOfferBy~=cmd.targetId then return reject("No peace offer to accept.") end
            s.diplomacy.status="Peace"; s.diplomacy.peaceOfferBy=nil; s.diplomacy.peaceUntil=s.turn+8; event(s,"Peace","Peace agreed.",nil,nil,nil,nil,true)
        else
            local give,receive=cmd.giveGold,cmd.receiveGold
            if s.diplomacy.status~="Peace" or type(give)~="number" or type(receive)~="number" or give%1~=0 or receive%1~=0 or give<0 or receive<0 or give>100000 or receive>100000 or give+receive==0 or give>p.gold or #s.trades>=8 then return reject("A trade needs valid gold amounts and peaceful relations.") end
            table.insert(s.trades,{id=s.nextTrade,fromId=actorId,toId=cmd.targetId,giveGold=give,receiveGold=receive,expires=s.turn+3}); s.nextTrade += 1
        end
    elseif cmd.tradeId~=nil then
        if not finiteId(cmd.tradeId) then return reject("Invalid trade identifier.") end
        local index: number?=nil; for i,t in s.trades do if t.id==cmd.tradeId then index=i; break end end
        if not index then return reject("Trade is unavailable.") end
        local trade=s.trades[index]
        if cmd.kind=="AcceptTrade" then
            if trade.toId~=actorId or s.diplomacy.status~="Peace" or p.gold<trade.receiveGold or s.players[trade.fromId].gold<trade.giveGold then return reject("Trade cannot be accepted.") end
            p.gold += trade.giveGold-trade.receiveGold; s.players[trade.fromId].gold += trade.receiveGold-trade.giveGold
            event(s,"Trade","Trade accepted.",nil,nil,nil,nil,true)
        elseif trade.fromId~=actorId and trade.toId~=actorId then return reject("This is not your trade.") end
        table.remove(s.trades,index)
    elseif cmd.kind=="EndTurn" then endTurn(s,actorId)
    else return reject("Unknown command.") end
    refreshVision(s); refreshEconomyState(s); evaluate(s); s.revision += 1
    return {ok=true,message="Command completed."}
end
function BaseGame.snapshot(state: State, actorId: number): View
    assert(actorId==1 or actorId==2,"unknown actor")
    local s: any=state; local p=s.players[actorId]; local seen=visible(s,actorId); local discovered={}; for _, id in p.explored do discovered[id]=true end
    local tiles={}
    for _, tile in s.tiles do
        local projected: any={id=tile.id,x=tile.x,y=tile.y,visible=seen[tile.id]==true,explored=discovered[tile.id]==true}
        if discovered[tile.id] then
            projected.terrain=tile.terrain; projected.resource=tile.resource
            local yields=yieldFor({terrain=tile.terrain,resource=tile.resource})
            projected.food=yields.food; projected.production=yields.production; projected.gold=yields.gold
        end
        if seen[tile.id] then
            projected.ownerId=tile.ownerId; projected.improvement=tile.improvement; projected.road=tile.road
            local yields=yieldFor(tile); projected.food=yields.food; projected.production=yields.production; projected.gold=yields.gold
        end
        table.insert(tiles,projected)
    end
    local units,cities,events,legal,improvements,previews={},{},{},{},{},{}
    local occupancyUnits,occupancyCities=occupants(s)
    local canAct=s.phase=="Playing" and s.activePlayerId==actorId and p.human
    for _, u in s.units do
        if u.ownerId==actorId or seen[u.tileId] then table.insert(units,copy(u)) end
        if u.ownerId==actorId then
            local targets,unitPreviews={},{}
            if canAct then
                for tileId in reachable(s,u,seen,occupancyUnits,occupancyCities) do if tileId~=u.tileId then table.insert(targets,tileId) end end
                for _, tileId in attackTargets(s,u,seen,occupancyUnits,occupancyCities) do table.insert(targets,tileId); table.insert(unitPreviews,previewFor(s,u,tileId,occupancyUnits,occupancyCities)) end
            end
            table.sort(targets); legal[tostring(u.id)]=targets; previews[tostring(u.id)]=unitPreviews
            local choices={}; if canAct then for _, id in improvementOrder do if improvementAvailable(s,u,id) then table.insert(choices,id) end end end
            improvements[tostring(u.id)]=choices
        end
    end
    for _, c in s.cities do
        if c.ownerId==actorId then table.insert(cities,copy(c))
        elseif seen[c.tileId] then table.insert(cities,{id=c.id,ownerId=c.ownerId,tileId=c.tileId,name=c.name,population=c.population,hp=c.hp,capital=c.capital,originalOwnerId=c.originalOwnerId}) end
    end
    for _, e in s.events do if e.public or e.ownerId==actorId then table.insert(events,copy(e)) elseif e.tileId and seen[e.tileId] then table.insert(events,copy(e)) end end
    local research,policies,production={},{},{}
    local productionByCity: {[string]: {string}},purchasesByCity: {[string]: {string}}={},{}
    for _, c in s.cities do if c.ownerId==actorId then productionByCity[tostring(c.id)]={}; purchasesByCity[tostring(c.id)]={} end end
    for _, id in R.technologyOrder do if eligible(p,R.technologies[id],p.technologies) then table.insert(research,copy(R.technologies[id])) end end
    for _, id in R.policyOrder do if eligible(p,R.policies[id],p.policies) then local entry=copy(R.policies[id]); entry.cost=policyCost(s,p,R.policies[id]); table.insert(policies,entry) end end
    local productionOrder=copy(R.unitOrder); for _, id in R.buildingOrder do table.insert(productionOrder,id) end
    for _, id in productionOrder do
        local added=false
        for _, c in s.cities do
            if c.ownerId==actorId and productionAvailable(s,c,id) then
                table.insert(productionByCity[tostring(c.id)],id)
                if p.gold>=R.purchaseCosts[id] and (R.buildings[id] or spawnTile(s,c)) then table.insert(purchasesByCity[tostring(c.id)],id) end
                if not added then table.insert(production,id); added=true end
            end
        end
    end
    local score,stats=scores(s)
    -- Rival economy, research and score are private during play, even after meeting that
    -- civilization. Final scores and statistics are revealed once the match has finished.
    if s.phase~="Finished" then score[3-actorId]=0; stats[3-actorId]={cities=0,units=0,population=0,technologies=0,policies=0} end
    -- Coarse public progress for both civilizations: city count, adopted policy count and an
    -- era index (one era per four technologies). Exact technologies and economy stay private.
    local progress={}
    for owner=1,2 do
        local cityCount=0; for _, c in s.cities do if c.ownerId==owner then cityCount += 1 end end
        local player=s.players[owner]
        progress[owner]={cities=cityCount,policies=#player.policies,era=1+math.floor(#player.technologies/4)}
    end
    local threshold=cultureThreshold(s)
    return {seed=if s.humanPlayers==1 or s.phase=="Finished" then s.seed else nil,radius=s.radius,mapShape=s.mapShape,frequency=s.frequency,difficulty=s.difficulty,humanPlayers=s.humanPlayers,turn=s.turn,revision=s.revision,activePlayerId=s.activePlayerId,actorId=actorId,canAct=canAct,phase=s.phase,winner=s.winner,reason=s.reason,victoryType=s.victoryType,gold=p.gold,science=p.science,culture=p.culture,happiness=p.happiness,research=copy(p.research),technologies=copy(p.technologies),policies=copy(p.policies),resources=copy(resourceInventory(s,actorId)),income=copy(p.income),tiles=tiles,units=units,cities=cities,events=events,log={},legalMoves=legal,availableProduction=production,availableProductionByCity=productionByCity,availablePurchasesByCity=purchasesByCity,availableResearch=research,availablePolicies=policies,availableImprovements=improvements,productionCosts=copy(R.productionCosts),purchaseCosts=copy(R.purchaseCosts),scores=score,statistics=stats,progress=progress,cultureVictoryPolicies=threshold,policyCostIncrease=s.policyCostIncrease or 0,attackPreviews=previews,diplomacy=copy(s.diplomacy),trades=copy(s.trades),objectives={"Found cities, develop resources and maintain happiness.","Control both original capitals for domination.","Build SpaceProject after Rocketry for science victory.","Adopt "..threshold.." "..(if threshold==1 then "policy" else "policies").." for culture victory.","Highest score wins at the round limit; ties favor civilization 1."}}
end
-- Pure, fog-safe query for one attack the actor's unit could make now. It never mutates the
-- state and answers the same generic message for hidden, empty or out-of-range targets.
-- Turn ownership is not required; the snapshot only lists previews for legal attacks.
function BaseGame.previewAttack(state: State, actorId: number, unitId: number, tileId: number): (AttackPreview?, string?)
    local s: any=state
    if (actorId~=1 and actorId~=2) or s.phase~="Playing" then return nil,"No attack preview is available." end
    if not finiteId(unitId) or not finiteId(tileId) or not s.tiles[tileId] then return nil,"No attack preview is available." end
    local u=unitById(s,unitId); if not u or u.ownerId~=actorId then return nil,"Select your unit." end
    local units,cities=occupants(s)
    if not attackable(s,u,tileId,visible(s,actorId),units,cities) then return nil,"Choose a visible enemy within attack range." end
    return previewFor(s,u,tileId,units,cities),nil
end
function BaseGame.serialize(state: State): any
    local saved={format="unciv-luau-base",version=if state.mapShape=="Sphere" then 2 else 1,state=state}
    assert(Save.valid(saved),"cannot serialize an invalid base-game state"); return copy(saved)
end
function BaseGame.restore(saved: any): (State?,string?)
    if not Save.valid(saved) then return nil,"Unsupported or corrupt base-game save." end
    local s=copy(saved.state); mapFor(s); return s :: State,nil
end
function BaseGame.getRules(): typeof(Rules) return copy(Rules) end
return table.freeze(BaseGame)
