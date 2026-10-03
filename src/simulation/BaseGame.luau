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
    | {kind: "PromoteUnit", unitId: number, promotion: string}
    | {kind: "CityRangedStrike", cityId: number, targetUnitId: number}
export type Tile = {id: number, x: number?, y: number?, terrain: string, resource: string?, ownerId: number?, improvement: string?, road: boolean?}
-- `xp` and `promotions` are optional (absent means 0 and none). `level` counts the promotions taken.
export type Unit = {id: number, ownerId: number, kind: string, tileId: number, hp: number, moves: number, fortified: boolean, level: number, xp: number?, promotions: {string}?, work: {improvement: string, remaining: number}?}
-- A unit in a snapshot. Every listed unit carries `level` and `promotions` (visible, as in Civ V). Only the actor's own
-- units carry `xp`, `nextLevelXp` (the next threshold, absent at the last level) and `promotionsAvailable` (the ids
-- PromoteUnit accepts now, empty while the actor cannot act).
export type UnitView = {id: number, ownerId: number, kind: string, tileId: number, hp: number, moves: number, fortified: boolean, level: number, promotions: {string}, xp: number?, nextLevelXp: number?, promotionsAvailable: {string}?, work: {improvement: string, remaining: number}?}
-- `strikeTurn` is optional: the round whose ranged strike the city has used (it struck, or it was captured, that
-- round). Absent means the city has never used one.
export type City = {id: number, ownerId: number, originalOwnerId: number, capital: boolean, tileId: number, name: string, population: number, food: number, production: number, queue: string, hp: number, buildings: {string}, focus: string, strikeTurn: number?}
export type Research = {id: string, progress: number, cost: number}
export type Player = {id: number, human: boolean, gold: number, science: number, culture: number, happiness: number, technologies: {string}, policies: {string}, research: Research?, explored: {number}, resources: {[string]: number}, income: {food: number, production: number, gold: number, science: number, culture: number, maintenance: number}}
export type Event = {id: number, kind: string, message: string, tileId: number?, unitId: number?, ownerId: number?, amount: number?, public: boolean?, cause: string?, byOwnerId: number?, unitKind: string?, cityId: number?}
export type Diplomacy = {status: string, peaceOfferBy: number?, peaceUntil: number}
export type Trade = {id: number, fromId: number, toId: number, giveGold: number, receiveGold: number, expires: number}
export type TileView = {id: number, x: number?, y: number?, visible: boolean, explored: boolean, terrain: string?, resource: string?, ownerId: number?, improvement: string?, road: boolean?, food: number?, production: number?, gold: number?}
-- A city in a snapshot. Only the actor's own cities carry the economy fields and the city-combat fields: `strength`
-- (combat strength), `rangedStrength` (what its strike uses), `strikeReady` (its strike for this round is unused),
-- `canStrike` (ready, the actor can act now and at least one target is legal) and `strikeTargets` (the unit ids
-- CityRangedStrike accepts now, ascending; empty while the actor cannot act).
export type CityView = {id: number, ownerId: number, originalOwnerId: number, capital: boolean, tileId: number, name: string, population: number, hp: number, food: number?, production: number?, queue: string?, buildings: {string}?, focus: string?, strength: number?, rangedStrength: number?, strikeReady: boolean?, canStrike: boolean?, strikeTargets: {number}?}
export type Statistics = {cities: number, units: number, population: number, technologies: number, policies: number}
export type Progress = {cities: number, policies: number, era: number}
export type AttackPreview = {unitId: number, tileId: number, target: string, ranged: boolean, exact: boolean, hiddenDefense: boolean, dealt: number?, received: number?, dealtMin: number, dealtMax: number, receivedMin: number, receivedMax: number, attackerHp: number, defenderHp: number, attackerDefeated: string, defenderDefeated: string, captures: string}
-- One legal move: the path from the unit's tile (first) to the destination (last), the movement it spends and keeps,
-- whether it ends the unit's movement and whether the zone of control ended it. Values are in moves (multiples of 1/6).
export type MovePreview = {unitId: number, tileId: number, path: {number}, movesSpent: number, movesLeft: number, endsMovement: boolean, zoneOfControl: boolean}
-- One legal city strike: the striking city, the target unit and its tile, the city's ranged strength, the exact damage
-- (a strike is deterministic and reads only visible facts, so `exact` is always true), `received` (always 0: the
-- city takes no damage), the target's hit points before the strike and whether it dies ("Yes" or "No").
export type CityStrikePreview = {cityId: number, unitId: number, tileId: number, rangedStrength: number, exact: boolean, dealt: number, received: number, defenderHp: number, defenderDefeated: string}
export type Technology = Rules.Technology
export type Policy = Rules.Policy
export type Promotion = Rules.Promotion
export type State = {seed: number, radius: number?, mapShape: string?, frequency: number?, difficulty: string, humanPlayers: number, forest: boolean, maxTurns: number, cultureVictoryPolicies: number?, policyCostIncrease: number?, turn: number, revision: number, activePlayerId: number, phase: string, winner: number?, reason: string?, victoryType: string?, tiles: {Tile}, units: {Unit}, cities: {City}, players: {Player}, diplomacy: Diplomacy, trades: {Trade}, events: {Event}, nextEvent: number, nextUnit: number, nextCity: number, nextTrade: number, log: {string}}
export type CityForecast = {food: number, production: number, gold: number, science: number, culture: number, growthTurns: number?, productionTurns: number?, productionBlocked: ("NotAvailable" | "NoSpace")?}
export type View = {cityForecasts: {[string]: CityForecast}, seed: number?, radius: number?, mapShape: string?, frequency: number?, difficulty: string, humanPlayers: number, turn: number, revision: number, activePlayerId: number, actorId: number, canAct: boolean, phase: string, winner: number?, reason: string?, victoryType: string?, gold: number, science: number, culture: number, happiness: number, research: Research?, technologies: {string}, policies: {string}, resources: {[string]: number}, income: {food: number, production: number, gold: number, science: number, culture: number, maintenance: number}, tiles: {TileView}, units: {UnitView}, cities: {CityView}, events: {Event}, log: {string}, legalMoves: {[string]: {number}}, availableProduction: {string}, availableProductionByCity: {[string]: {string}}, availablePurchasesByCity: {[string]: {string}}, availableResearch: {Technology}, availablePolicies: {Policy}, availableImprovements: {[string]: {string}}, productionCosts: {[string]: number}, purchaseCosts: {[string]: number}, scores: {number}, statistics: {Statistics}, progress: {Progress}, cultureVictoryPolicies: number, policyCostIncrease: number, attackPreviews: {[string]: {AttackPreview}}, cityStrikePreviews: {[string]: {CityStrikePreview}}, diplomacy: Diplomacy, trades: {Trade}, objectives: {string}}
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
-- Event kinds the ring keeps longest (each player must reliably learn of its losses and the result).
local RETAINED={UnitLost=true, CityLost=true, Eliminated=true, Victory=true}
local function event(s: any, kind: string, message: string, tileId: number?, unitId: number?, ownerId: number?, amount: number?, public: boolean?, cause: string?, byOwnerId: number?, unitKind: string?, cityId: number?)
    table.insert(s.events, {id=s.nextEvent, kind=kind, message=message, tileId=tileId, unitId=unitId, ownerId=ownerId, amount=amount, public=public, cause=cause, byOwnerId=byOwnerId, unitKind=unitKind, cityId=cityId})
    s.nextEvent += 1
    if #s.events > 64 then
        -- One command (an EndTurn running the AI and both economies) can emit more than 64 events, so
        -- routine events go first: the oldest one that is not a loss or outcome, never the event just added.
        local drop=1
        for i=1,#s.events-1 do if not RETAINED[s.events[i].kind] then drop=i; break end end
        table.remove(s.events, drop)
    end
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
-- Claims unowned tiles around a city for its owner. With `overlay`, the state is untouched and each tile the
-- claim would take is marked in the overlay instead (the forecast's virtual claims for the city's own owner).
local function claim(s: any, city: any, overlay: {[number]: boolean}?)
    local ids = nearby(s,city.tileId,if city.population>=3 then R.cityWorkRadius else 1)
    for _, id in ids do
        local t=s.tiles[id]
        if not t.ownerId or id==city.tileId then if overlay then overlay[id]=true else t.ownerId=city.ownerId end end
    end
end
-- Original city names, one list per civilization in founding order; "City <id>" once a list runs out.
-- A city keeps its founding name when captured.
local CITY_NAMES: {{string}} = {
    {"Sunhaven","Brightwater","Oakridge","Goldcrest","Pinehollow","Stonebridge","Amberfall","Willowmere","Highmoor","Copperton","Larkspur","Mistvale"},
    {"Ironcliff","Embermark","Duskwall","Redspire","Ashford","Thornkeep","Cinderholm","Ravenrock","Blackwater","Flintgate","Shadowfen","Coldforge"},
}
local function addCity(s: any, owner: number, tileId: number): any
    local capital=true; local founded=0
    for _, c in s.cities do if c.originalOwnerId == owner then founded += 1; if c.capital then capital=false end end end
    local names=CITY_NAMES[owner]; local name=names and names[founded+1] or "City "..s.nextCity
    local c = {id=s.nextCity, ownerId=owner, originalOwnerId=owner, capital=capital, tileId=tileId, name=name, population=1, food=0, production=0, queue="Warrior", hp=R.cityHp, buildings={}, focus="Balanced"}
    s.nextCity += 1; table.insert(s.cities,c); claim(s,c); return c
end
local function eligible(player: any, entry: any, list: any): boolean
    if has(list,entry.id) then return false end
    for _, prerequisite in entry.prerequisites do if not has(list,prerequisite) then return false end end
    return true
end
-- `claimed` marks tiles counted as the owner's (the forecast's virtual claims); the state is not read for them.
local function resourceInventory(s: any, owner: number, claimed: {[number]: boolean}?): any
    local result: {[string]: number} = {}
    for _, tile in s.tiles do
        if (tile.ownerId ~= owner and not (claimed ~= nil and claimed[tile.id] == true)) or not tile.resource then continue end
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
-- For the forecast, `extra` lists the city owner's units that do not exist yet but would by then (earlier
-- completions this step) and `claimed` the tiles its claims would own by then. Neither changes the global unit
-- cap check, which counts every unit (including unseen rival units) and so stays at the current count.
local function productionAvailable(s: any, city: any, item: string, extra: {any}?, claimed: {[number]: boolean}?): boolean
    local entry=R.units[item] or R.buildings[item]
    if not entry then return false end
    local player=s.players[city.ownerId]
    if entry.technology and not has(player.technologies,entry.technology) then return false end
    if R.buildings[item] and has(city.buildings,item) then return false end
    if R.units[item] and #s.units >= R.maxUnits then return false end
    if entry.resource then
        local used=0; for _, u in s.units do if u.ownerId==city.ownerId and R.units[u.kind].resource==entry.resource then used += R.units[u.kind].resourceAmount or 1 end end
        if extra then for _, u in extra do if u.ownerId==city.ownerId and R.units[u.kind].resource==entry.resource then used += R.units[u.kind].resourceAmount or 1 end end end
        if (resourceInventory(s,city.ownerId,claimed)[entry.resource] or 0) < used+(entry.resourceAmount or 1) then return false end
    end
    return true
end
local function spawnTile(s: any, city: any, extra: {any}?): number?
    local units,cities=occupants(s)
    if extra then for _, u in extra do units[u.tileId]=u end end
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
-- Movement is counted in sixths of a move inside the engine. A sixth holds both the 1/3 road step and the
-- half moves older saves may store, so movement arithmetic is exact integer arithmetic; a unit's `moves`
-- field stores the canonical value sixths/6.
local SIXTHS=6
local function toSixths(moves: number): number return math.round(moves*SIXTHS) end
local function fromSixths(sixths: number): number return sixths/SIXTHS end
local roadSixths=toSixths(R.roadMovement)
-- The cost in sixths of stepping from `fromId` into the adjacent `toId`, or nil when the step is not allowed. Only
-- tiles the mover can see may be entered. Between two road tiles a step costs a third of a move, whatever the terrain.
local function movementCost(s: any, unit: any, fromId: number, toId: number, seen: any, units: any, cities: any): number?
    if not seen[toId] then return nil end
    local tile=s.tiles[toId]; local terrain=R.terrains[tile.terrain]
    if not terrain.passable then return nil end
    local occupant,city=units[toId],cities[toId]
    if occupant and occupant.id~=unit.id then return nil end
    if city and city.ownerId~=unit.ownerId then return nil end
    if tile.ownerId and tile.ownerId~=unit.ownerId and s.diplomacy.status~="War" then return nil end
    if tile.road and s.tiles[fromId].road then return roadSixths end
    return terrain.movement*SIXTHS
end
-- Tiles that exert a zone of control on this unit: enemy military units (strength above zero) and enemy cities,
-- only while at war and only where the moving civilization can see them, so a move never reveals a hidden unit.
-- Civilians neither exert nor feel a zone of control (nil: none applies).
local function zoneSources(s: any, unit: any, seen: any, units: any, cities: any): {[number]: boolean}?
    if R.units[unit.kind].strength<=0 or s.diplomacy.status~="War" then return nil end
    local sources={}
    for tileId,u in units do if u.ownerId~=unit.ownerId and seen[tileId] and R.units[u.kind].strength>0 then sources[tileId]=true end end
    for tileId,c in cities do if c.ownerId~=unit.ownerId and seen[tileId] then sources[tileId]=true end end
    return sources
end
-- Civ V's rule: a step from a tile next to an enemy source into another tile next to that same source spends all
-- remaining movement. Two adjacent hexes share two neighbours, so the source is one of those.
local function zoneOfControl(s: any, sources: {[number]: boolean}?, fromId: number, toId: number): boolean
    if not sources then return false end
    local neighbors=mapFor(s).neighbors; local into=neighbors[toId]
    for _, id in neighbors[fromId] do if sources[id] and table.find(into,id) then return true end end
    return false
end
-- One turn of movement for a unit. Returns, for every tile it can reach, the sixths spent getting there (the start
-- costs 0), the previous tile on the cheapest path, and whether the zone of control ended the final step.
-- A unit with any movement left may always enter an adjacent allowed tile: when the step costs at least what remains
-- or the zone of control applies, the unit arrives with no movement left. Arrival never decreases as the spent
-- amount grows, so Dijkstra's order stays exact. Ties settle the lowest tile id first and keep the first path found.
-- Costs are whole sixths and every step arrives strictly later than it leaves, so a bucket per spent sixth (at most
-- the unit's maximum moves times six) is complete when reached; sorting it settles that cost's tiles by id. The search
-- is therefore linear in the tiles it reaches, apart from those small sorts.
local function movementSearch(s: any, unit: any, seen: any, units: any, cities: any): ({[number]: number}, {[number]: number}, {[number]: boolean})
    local budget=toSixths(unit.moves)
    local spent: {[number]: number}={[unit.tileId]=0}; local previous: {[number]: number}={}; local zoc: {[number]: boolean}={}
    if budget<=0 then return spent,previous,zoc end
    local sources=zoneSources(s,unit,seen,units,cities); local neighbors=mapFor(s).neighbors; local settled: {[number]: boolean}={}
    local buckets: {[number]: {number}}={[0]={unit.tileId}}
    for here=0,budget do
        local bucket=buckets[here]
        if not bucket then continue end
        table.sort(bucket)
        for _, current in bucket do
            -- A tile appears again in a later bucket only after a cheaper arrival replaced it; skip the stale entry.
            if settled[current] or spent[current]~=here then continue end
            settled[current]=true
            if here>=budget then continue end
            for _, nextId in neighbors[current] do
                if settled[nextId] then continue end
                local step=movementCost(s,unit,current,nextId,seen,units,cities)
                if step==nil then continue end
                local controlled=zoneOfControl(s,sources,current,nextId)
                local arrival=if controlled then budget else math.min(budget,here+step)
                if spent[nextId]==nil or arrival<spent[nextId] then
                    spent[nextId]=arrival; previous[nextId]=current; zoc[nextId]=controlled
                    local later=buckets[arrival]; if later then table.insert(later,nextId) else buckets[arrival]={nextId} end
                end
            end
        end
    end
    return spent,previous,zoc
end
local function reachable(s: any, unit: any, vision: any?, occupancyUnits: any?, occupancyCities: any?): any
    if unit.moves<=0 then return {} end
    local seen=vision or visible(s,unit.ownerId); local units,cities=occupancyUnits,occupancyCities
    if not units or not cities then units,cities=occupants(s) end
    return (movementSearch(s,unit,seen,units,cities))
end
-- The fog-safe record of one legal move, built from a movement search.
local function movePreviewFor(unit: any, target: number, spent: any, previous: any, zoc: any): MovePreview
    local path={target}; local current=target
    while current~=unit.tileId do current=previous[current]; table.insert(path,1,current) end
    local left=fromSixths(toSixths(unit.moves)-spent[target])
    return {unitId=unit.id,tileId=target,path=path,movesSpent=fromSixths(spent[target]),movesLeft=left,endsMovement=left<=0,zoneOfControl=zoc[target]==true}
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
-- Each other friendly military unit next to the defending unit adds a percentage to a melee attack, up to a cap.
-- Only the attacking civilization's own units count, so the preview can read them under fog.
local function flankingPercent(s: any, unit: any, target: number, units: any): number
    local count=0
    for _, id in mapFor(s).neighbors[target] do
        local ally=units[id]
        if ally and ally.id~=unit.id and ally.ownerId==unit.ownerId and R.units[ally.kind].strength>0 then count += 1 end
    end
    return math.min(R.maxFlankingPercent,count*R.flankingPercent)
end
-- Experience and promotions. A unit has earned one level for each threshold its experience has reached; `level`
-- counts the promotions it has taken, so each earned level beyond `level` lets it choose one promotion.
local function earnedLevels(u: any): number
    local earned=0; for _, threshold in R.experienceThresholds do if (u.xp or 0)>=threshold then earned += 1 end end; return earned
end
local function gainExperience(u: any, amount: number)
    if R.units[u.kind].unitClass=="Civilian" then return end
    u.xp=math.min(R.maxExperience,(u.xp or 0)+amount)
end
-- Whether the unit may take this promotion now: a pending level, open to its class, not taken, prerequisites taken.
local function promotionAllowed(u: any, id: string): boolean
    local rule=R.promotions[id]
    if not rule or earnedLevels(u)<=u.level or not has(rule.classes,R.units[u.kind].unitClass) then return false end
    local taken=u.promotions or {}
    if has(taken,id) then return false end
    for _, prerequisite in rule.prerequisites do if not has(taken,prerequisite) then return false end end
    return true
end
local function promotionsAvailable(u: any): {string}
    local ids={}; for _, id in R.promotionOrder do if promotionAllowed(u,id) then table.insert(ids,id) end end; return ids
end
-- Taking a promotion raises the level, heals half the unit's maximum hit points (never above it) and ends its
-- movement this turn. Fortification is kept.
local function promote(s: any, u: any, id: string)
    local taken=u.promotions or {}; table.insert(taken,id); u.promotions=taken; u.level += 1
    local maxHp=R.units[u.kind].hp
    u.hp=math.min(maxHp,u.hp+math.floor(maxHp*R.promotionHealPercent/100)); u.moves=0
    event(s,"Promotion","Unit promoted: "..R.promotions[id].name..".",u.tileId,u.id,u.ownerId,nil,nil,nil,nil,u.kind)
end
-- The AI takes the promotion line that suits the terrain it stands on (Drill on rough, Shock on open), otherwise the
-- first available promotion in rule order (Accuracy, then Cover, then Medic for ranged units).
local function aiPromotion(s: any, u: any): string?
    local options=promotionsAvailable(u); if #options==0 then return nil end
    local rough=R.terrains[s.tiles[u.tileId].terrain].rough
    for _, id in options do local p=R.promotions[id]; if (if rough then p.roughPercent else p.openPercent)>0 then return id end end
    return options[1]
end
-- The percentage a unit's promotions add to its strength in one strike. The strike's target tile decides rough or
-- open terrain for both sides. Cover counts while defending against a ranged attack, Accuracy on a ranged attack
-- against a unit. A unit's promotions are visible with the unit, so the preview may read the defender's.
local function promotionPercent(s: any, u: any, target: number, attacking: boolean, rangedStrike: boolean, againstUnit: boolean): number
    local taken=u.promotions; if not taken then return 0 end
    local rough=R.terrains[s.tiles[target].terrain].rough
    local total=0
    for _, id in taken do
        local p=R.promotions[id]
        total += if rough then p.roughPercent else p.openPercent
        if attacking then
            if rangedStrike and againstUnit then total += p.accuracyPercent end
        elseif rangedStrike then total += p.coverPercent end
    end
    return total
end
-- A unit's defence on the target tile against one strike (ranged or melee): max(3, strength) x (100 + terrain% +
-- fortified% + promotion%)/100 x (0.5 + hp/200). Shared by unit strikes and city strikes.
local function unitDefense(s: any, defender: any, target: number, rangedStrike: boolean): number
    local terrain=R.terrains[s.tiles[target].terrain].defensePercent or 0
    local modifier=terrain+(if defender.fortified then R.fortifyDefensePercent else 0)+promotionPercent(s,defender,target,false,rangedStrike,true)
    return math.max(3,R.units[defender.kind].strength)*(100+modifier)/100*(0.5+defender.hp/200)
end
-- Deterministic damage for one strike, given the target city's building defence and the tile-to-unit occupancy.
-- Attack: base strength x (0.5 + hp/200) x (100 + flanking% + promotion% + siege%)/100; flanking applies only to melee
-- attacks on a defending unit, siege only when the target tile holds an (enemy) city. Defence of a unit: see
-- unitDefense; of an undefended city: (cityBaseStrength 14 + population) x (100 + terrain%)/100. City buildings (Walls)
-- add a flat amount on top in both cases, so damage stays monotonic in the hidden building defence. `level` adds nothing
-- itself (it was +3 strength per level before promotions); the promotions it counts carry the bonuses.
local function strike(s: any, unit: any, defender: any, city: any, target: number, cityDefense: number, units: any): (number, number, boolean)
    local ranged=(R.units[unit.kind].range or 1)>1
    local attack=if ranged then R.units[unit.kind].rangedStrength else R.units[unit.kind].strength
    local flanking=if ranged or not defender then 0 else flankingPercent(s,unit,target,units)
    local promoted=promotionPercent(s,unit,target,true,ranged,defender~=nil)
    local siege=if city then R.units[unit.kind].siegePercent else 0
    attack=math.max(1,attack)*(0.5+unit.hp/200)*(100+flanking+promoted+siege)/100
    local terrain=R.terrains[s.tiles[target].terrain].defensePercent or 0
    local defense: number
    if defender then
        defense=unitDefense(s,defender,target,ranged)
    else
        defense=(R.cityBaseStrength+(city.population or 1))*(100+terrain)/100
    end
    if city then defense += cityDefense end
    local dealt=math.clamp(math.floor(30*attack/math.max(1,defense)+0.5),8,65)
    local received=if ranged or (defender and R.units[defender.kind].strength==0) then 0 else math.clamp(math.floor(25*defense/attack+0.5),8,65)
    return dealt,received,ranged
end
local function combat(s: any, unit: any, target: number)
    local units,cities=occupants(s); local defender,city=units[target],cities[target]
    local dealt,received,ranged=strike(s,unit,defender,city,target,if city then buildingDefense(city) else 0,units)
    local enemyOwner=if defender then defender.ownerId else city.ownerId
    unit.hp -= received; unit.moves=0; unit.fortified=false; unit.work=nil
    if defender then defender.hp -= dealt
    else city.hp=math.max(0,city.hp-dealt) end
    -- Experience: both sides of a strike on a military unit, and the attacker of a strike on a city. A strike on a
    -- civilian gives none. A unit that dies is removed below, so only survivors keep what they gained.
    if not defender or R.units[defender.kind].strength>0 then
        gainExperience(unit,if ranged then R.experience.rangedAttack else R.experience.meleeAttack)
        if defender then gainExperience(defender,if ranged then R.experience.rangedDefense else R.experience.meleeDefense) end
    end
    event(s,"Attack","Battle dealt "..dealt.." damage.",target,unit.id,unit.ownerId,dealt)
    if defender and defender.hp<=0 then removeUnit(s,defender.id); unitLost(s,defender,target,if ranged then "Ranged" else "Combat",unit.ownerId,dealt) end
    if unit.hp<=0 then removeUnit(s,unit.id); unitLost(s,unit,unit.tileId,"Combat",enemyOwner,received); return end
    if not ranged and not select(1,occupants(s))[target] then
        if city and city.ownerId~=unit.ownerId then
            if city.hp==0 then
                local loser=city.ownerId
                -- A city captured this round cannot strike until the next round (its strike counts as used).
                city.ownerId=unit.ownerId; city.hp=50; city.population=math.max(1,city.population-1); city.production=0; city.queue="Warrior"; city.food=0; city.strikeTurn=s.turn
                local ids={target}; for _, id in mapFor(s).neighbors[target] do table.insert(ids,id) end
                for _, id in ids do s.tiles[id].ownerId=unit.ownerId end
                unit.tileId=target; event(s,"Capture","City captured.",target,unit.id,unit.ownerId)
                event(s,"CityLost",city.name.." was captured.",target,nil,loser,nil,nil,"Captured",unit.ownerId)
            end
        else unit.tileId=target end
    end
end
local function outcome(low: boolean, high: boolean): string return if low~=high then "Maybe" elseif low then "Yes" else "No" end
-- Fog-safe preview. It reads only the actor's units (the attacker and its flanking units), the visible
-- defender (kind, hp and fortification), the visible city population/hp and visible terrain. It calls the
-- same strike as combat, so a unit result is exact. Hidden city buildings
-- widen the result to a range. Damage is monotonic in defence, so the bounds are exact.
local function previewFor(s: any, unit: any, target: number, units: any, cities: any): AttackPreview
    local defender,city=units[target],cities[target]
    local high=if city then hiddenCityDefense else 0
    local dealtMax,receivedMin,ranged=strike(s,unit,defender,city,target,0,units)
    local dealtMin,receivedMax=strike(s,unit,defender,city,target,high,units)
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
-- City combat. A civilization's era is 1 + floor(technologies / 4) (1-5), the same coarse value `progress` makes public.
local function era(s: any, owner: number): number return 1+math.floor(#s.players[owner].technologies/4) end
-- A military unit (strength above zero) of the city's owner standing in the city adds garrisonPercent of its strength.
local function garrisonStrength(city: any, units: any): number
    local garrison=units[city.tileId]
    if not garrison or garrison.ownerId~=city.ownerId or R.units[garrison.kind].strength<=0 then return 0 end
    return math.floor(R.units[garrison.kind].strength*R.garrisonPercent/100)
end
-- City combat strength: cityBaseStrength + population + cityStrengthPerEra x (era - 1) + building defence (Walls) +
-- garrison. Its ranged strike uses cityStrikePercent of it, rounded down. Both are whole numbers.
local function cityStrength(s: any, city: any, units: any): number
    return R.cityBaseStrength+city.population+R.cityStrengthPerEra*(era(s,city.ownerId)-1)+buildingDefense(city)+garrisonStrength(city,units)
end
local function cityRangedStrength(s: any, city: any, units: any): number
    return math.floor(cityStrength(s,city,units)*R.cityStrikePercent/100)
end
-- One strike per round: `strikeTurn` records the round whose strike the city used (by striking or by being captured).
local function strikeReady(s: any, city: any): boolean return city.strikeTurn~=s.turn end
-- A legal city strike target: an enemy unit at war, on a tile the city's owner can see, within cityStrikeRange of the
-- city and not inside a city (cities stand at least three apart, so that only matters for hand-made states).
local function strikeTargetAllowed(s: any, city: any, target: any, seen: any, cities: any): boolean
    return s.diplomacy.status=="War" and target.ownerId~=city.ownerId and seen[target.tileId]==true and cities[target.tileId]==nil
        and W.inRange(mapFor(s),city.tileId,target.tileId,R.cityStrikeRange)
end
local function cityStrikeTargets(s: any, city: any, seen: any, units: any, cities: any): {number}
    local ids={}
    if s.diplomacy.status~="War" then return ids end
    for _, tileId in nearby(s,city.tileId,R.cityStrikeRange) do
        local target=units[tileId]
        if target and strikeTargetAllowed(s,city,target,seen,cities) then table.insert(ids,target.id) end
    end
    table.sort(ids); return ids
end
-- Damage of a city strike: the unit-strike damage formula with the city's ranged strength as the attack (a city's
-- damage does not weaken it, so there is no health factor) against the target's defence to a ranged strike, so Cover,
-- fortification, terrain and Drill/Shock on the target's tile all count. The city takes no damage.
local function cityStrikeDamage(s: any, city: any, target: any, units: any): number
    local attack=math.max(1,cityRangedStrength(s,city,units))
    return math.clamp(math.floor(30*attack/math.max(1,unitDefense(s,target,target.tileId,true))+0.5),8,65)
end
-- The fog-safe preview of one strike. It reads the actor's own city and garrison, the owner's era and the visible
-- target (kind, hp, fortification, promotions) and terrain, and calls the same damage function as the strike.
local function cityStrikePreviewFor(s: any, city: any, target: any, units: any): CityStrikePreview
    local dealt=cityStrikeDamage(s,city,target,units)
    return {cityId=city.id,unitId=target.id,tileId=target.tileId,rangedStrength=cityRangedStrength(s,city,units),exact=true,dealt=dealt,received=0,
        defenderHp=target.hp,defenderDefeated=if target.hp-dealt<=0 then "Yes" else "No"}
end
-- A city strike: damages the target, uses the city's strike for this round and gives the target the experience of a
-- unit hit by a ranged attack (cities have none; civilians gain none). A target reduced to 0 hit points dies.
local function cityStrike(s: any, city: any, target: any, units: any)
    local dealt=cityStrikeDamage(s,city,target,units)
    city.strikeTurn=s.turn; target.hp -= dealt
    gainExperience(target,R.experience.rangedDefense)
    event(s,"CityStrike","City strike dealt "..dealt.." damage.",target.tileId,target.id,city.ownerId,dealt,nil,nil,nil,target.kind,city.id)
    if target.hp<=0 then removeUnit(s,target.id); unitLost(s,target,target.tileId,"CityStrike",city.ownerId,dealt) end
end
-- The AI's choice for one ready city: a target the strike kills first, then a military unit over a civilian, then the
-- target left with the fewest hit points; ties go to the lowest unit id.
local function aiCityStrike(s: any, city: any)
    local seen=visible(s,city.ownerId); local units,cities=occupants(s)
    local best: any=nil; local bestRank=-math.huge
    for _, id in cityStrikeTargets(s,city,seen,units,cities) do
        local target=unitById(s,id); local dealt=cityStrikeDamage(s,city,target,units)
        local rank=(if dealt>=target.hp then 2000 else 0)+(if R.units[target.kind].strength>0 then 1000 else 0)-math.max(0,target.hp-dealt)
        if rank>bestRank then best=target; bestRank=rank end
    end
    if best then cityStrike(s,city,best,units) end
end
local function moveUnit(s: any, unit: any, target: number): boolean
    local seen=visible(s,unit.ownerId)
    if attackable(s,unit,target,seen) then combat(s,unit,target); return true end
    local targets=reachable(s,unit,seen); local cost=targets[target]
    if target==unit.tileId or not cost then return false end
    unit.tileId=target; unit.moves=fromSixths(toSixths(unit.moves)-cost); unit.fortified=false; unit.work=nil
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
-- One city's yields this turn: the free center, each citizen on the best distinct nearby owned tile for its
-- focus (marking `worked`), buildings, policies and the Science/Culture production conversion. Pure apart
-- from `worked`; returns the yields and the buildings' maintenance. Shared by the economy and the forecast.
-- `claimed` marks tiles the forecast treats as already owned by `owner` (its virtual claims).
local function cityYields(s: any, p: any, owner: number, c: any, worked: any, cityTiles: any, claimed: {[number]: boolean}?): (any, number)
    local candidates: {any}={}
    for _, id in nearby(s,c.tileId,R.cityWorkRadius) do
        local tile=s.tiles[id]; if (tile.ownerId==owner or (claimed~=nil and claimed[id]==true)) and not cityTiles[id] and not worked[id] then table.insert(candidates,{id=id,yields=yieldFor(tile)}) end
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
    local maintenance=0
    for _, building in c.buildings do local b=R.buildings[building]; maintenance += b.maintenance; for key,value in b.yields do yields[key] += value end end
    for _, policy in p.policies do for key,value in R.policies[policy].yields do yields[key] += value end end
    if c.focus=="Science" or c.focus=="Culture" then
        local converted=math.floor(yields.production/2); yields.production -= converted; yields[string.lower(c.focus)] += converted
    end
    return yields, maintenance
end
-- Net food and production a city adds per turn after happiness (and AI difficulty) adjustments.
local function cityNet(s: any, p: any, c: any, yields: any, happiness: number): (number, number)
    local food=yields.food-c.population*R.foodPerPopulation
    if happiness<0 and food>0 then food=math.floor(food/2) end
    local production=yields.production
    if happiness<=-5 then production=math.max(1,math.floor(production/2)) end
    if not p.human then production=math.max(1,math.floor(production*(if s.difficulty=="Easy" then 0.75 elseif s.difficulty=="Hard" then 1.25 else 1))) end
    return food, production
end
-- The happiness an economy step uses for all of its cities (fixed at the start of the step) and the
-- policies' maintenance discount. Pure; shared by the economy and the forecast.
local function stepHappiness(s: any, owner: number, resources: any): (number, number)
    local p=s.players[owner]
    local population,cityCount,happiness=0,0,R.baseHappiness
    for resource,count in resources do if count>0 then happiness += R.resources[resource].happiness or 0 end end
    for _, c in s.cities do if c.ownerId==owner then cityCount += 1; population += c.population; for _, b in c.buildings do happiness += R.buildings[b].happiness or 0 end end end
    local discount=0; for _, policy in p.policies do happiness += R.policies[policy].happiness or 0; discount += R.policies[policy].maintenanceDiscount or 0 end
    return happiness-cityCount*R.unhappinessPerCity-population*R.unhappinessPerPopulation, discount
end
local function economy(s: any, owner: number)
    local p=s.players[owner]; p.resources=resourceInventory(s,owner)
    local happiness,discount=stepHappiness(s,owner,p.resources); p.happiness=happiness
    local income: {[string]: number}={food=0,production=0,gold=0,science=0,culture=0,maintenance=0}
    local worked={}; local _,cityTiles=occupants(s)
    local cityOrder: {any}={}; for _, city in s.cities do table.insert(cityOrder,city) end
    table.sort(cityOrder,function(a: any,b: any) return a.id<b.id end)
    for _, c in cityOrder do
        if c.ownerId~=owner then continue end
        -- The city center is free; each citizen works one distinct nearby owned tile.
        claim(s,c)
        local yields,maintenance=cityYields(s,p,owner,c,worked,cityTiles); income.maintenance += maintenance
        local food,production=cityNet(s,p,c,yields,p.happiness)
        c.food += food
        local threshold=R.growthBase+c.population*R.growthPerPopulation
        if c.food>=threshold and p.happiness>=0 and c.population<R.maxPopulation then c.food -= threshold; c.population += 1; event(s,"Growth","City grew.",c.tileId,nil,owner,c.population)
        elseif c.food<0 then
            if c.population>1 then c.population -= 1; event(s,"Starvation","City lost population.",c.tileId,nil,owner,c.population) end
            c.food=0
        end
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
-- Whether a unit spent its owner's previous turn without moving or attacking, derived from saved fields (no
-- extra state): moving spends movement and attacking spends all of it, while both clear fortification. A unit
-- still holding its full movement rested; a fortified unit or a worker on an improvement order rested too.
local function rested(u: any): boolean
    return u.fortified or u.work~=nil or u.moves>=R.units[u.kind].moves
end
-- Hit points regained by a rested unit: most in its owner's city, then friendly territory, then elsewhere.
local function healing(s: any, u: any, cities: any): number
    local city=cities[u.tileId]
    if city and city.ownerId==u.ownerId then return R.healing.city end
    if s.tiles[u.tileId].ownerId==u.ownerId then return R.healing.friendly end
    return R.healing.neutral
end
-- The extra healing the owner's medics give a resting unit next to them: the largest one, as medics do not stack.
local function medicTiles(s: any, owner: number): {[number]: number}
    local tiles: {[number]: number}={}
    for _, u in s.units do
        if u.ownerId~=owner or not u.promotions then continue end
        for _, id in u.promotions do local heal=R.promotions[id].adjacentHeal; if heal>0 then tiles[u.tileId]=math.max(tiles[u.tileId] or 0,heal) end end
    end
    return tiles
end
local function medicBonus(s: any, u: any, medics: {[number]: number}): number
    local best=0; for _, id in mapFor(s).neighbors[u.tileId] do best=math.max(best,medics[id] or 0) end; return best
end
local function beginTurn(s: any, owner: number)
    s.activePlayerId=owner
    local _,cities=occupants(s); local medics=medicTiles(s,owner)
    for _, u in s.units do
        if u.ownerId~=owner then continue end
        -- Healing reads last turn's remaining movement, so it runs before movement refreshes. A medic next to a
        -- resting unit adds its bonus; a unit that does not rest gets none.
        if rested(u) then u.hp=math.min(R.units[u.kind].hp,u.hp+healing(s,u,cities)+medicBonus(s,u,medics)) end
        u.moves=if u.work then 0 else R.units[u.kind].moves
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
    -- Each ready city strikes first, in city id order, so the units that act next can finish weakened targets.
    local strikers: {any}={}; for _, c in s.cities do if c.ownerId==owner and strikeReady(s,c) then table.insert(strikers,c) end end
    table.sort(strikers,function(a: any,b: any) return a.id<b.id end)
    for _, c in strikers do aiCityStrike(s,c) end
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
    -- After its units have acted, the AI spends every pending level (promoting ends a unit's movement).
    for _, u in s.units do
        if u.ownerId~=owner then continue end
        local choice=aiPromotion(s,u)
        while choice do promote(s,u,choice); choice=aiPromotion(s,u) end
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
local schemas: any={MoveUnit={unitId=true,tileId=true},RangedAttack={unitId=true,tileId=true},FoundCity={unitId=true},FortifyUnit={unitId=true},UpgradeUnit={unitId=true},BuildImprovement={unitId=true,improvement=true},SetProduction={cityId=true,item=true},Purchase={cityId=true,item=true},SetCityFocus={cityId=true,focus=true},Research={technology=true},AdoptPolicy={policy=true},DeclareWar={targetId=true},OfferPeace={targetId=true},AcceptPeace={targetId=true},ProposeTrade={targetId=true,giveGold=true,receiveGold=true},AcceptTrade={tradeId=true},CancelTrade={tradeId=true},EndTurn={},PromoteUnit={unitId=true,promotion=true},CityRangedStrike={cityId=true,targetUnitId=true}}
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
        elseif cmd.kind=="PromoteUnit" then
            if type(cmd.promotion)~="string" or not promotionAllowed(u,cmd.promotion) then return reject("That promotion is unavailable for this unit.") end
            promote(s,u,cmd.promotion)
        end
    elseif cmd.cityId~=nil then
        if not finiteId(cmd.cityId) then return reject("Invalid city identifier.") end
        local c=cityById(s,cmd.cityId); if not c or c.ownerId~=actorId then return reject("Select your city.") end
        if cmd.kind=="SetCityFocus" then
            if not has({"Balanced","Food","Production","Gold","Science","Culture"},cmd.focus) or c.focus==cmd.focus then return reject("Choose a different valid city focus.") end
            c.focus=cmd.focus
        elseif cmd.kind=="CityRangedStrike" then
            if not finiteId(cmd.targetUnitId) then return reject("Invalid unit identifier.") end
            if not strikeReady(s,c) then return reject("This city has used its strike this round.") end
            -- One message for a missing, hidden, friendly, out-of-range or peaceful target, so nothing hidden is revealed.
            local units,cities=occupants(s); local target=unitById(s,cmd.targetUnitId)
            if not target or not strikeTargetAllowed(s,c,target,visible(s,actorId),cities) then return reject("Choose a visible enemy unit within the city's range.") end
            cityStrike(s,c,target,units)
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
        if u.ownerId==actorId or seen[u.tileId] then
            -- Level and promotions are visible with the unit (the combat preview reads them). Experience and pending
            -- choices are the owner's alone.
            local view=copy(u); view.promotions=copy(u.promotions or {})
            if u.ownerId==actorId then
                view.xp=u.xp or 0; view.nextLevelXp=R.experienceThresholds[earnedLevels(u)+1]
                view.promotionsAvailable=if canAct then promotionsAvailable(u) else {}
            else view.xp=nil end
            table.insert(units,view)
        end
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
    local strikePreviews={}
    for _, c in s.cities do
        if c.ownerId==actorId then
            -- City combat for the actor's own cities: strength, readiness and the strikes it can make now.
            local view=copy(c); view.strikeTurn=nil
            local ready=strikeReady(s,c); local targets: {number}={}; local list={}
            if canAct and ready then
                targets=cityStrikeTargets(s,c,seen,occupancyUnits,occupancyCities)
                for _, id in targets do table.insert(list,cityStrikePreviewFor(s,c,unitById(s,id),occupancyUnits)) end
            end
            view.strength=cityStrength(s,c,occupancyUnits); view.rangedStrength=cityRangedStrength(s,c,occupancyUnits)
            view.strikeReady=ready; view.canStrike=#targets>0; view.strikeTargets=targets
            strikePreviews[tostring(c.id)]=list
            table.insert(cities,view)
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
        progress[owner]={cities=cityCount,policies=#player.policies,era=era(s,owner)}
    end
    local threshold=cultureThreshold(s)
    -- Per-city forecast for the actor's own cities: what the next economy step adds, and turns to grow and to finish
    -- the queue at that rate. It replays the step without mutating the state: cities in id order, each first making
    -- its territory claim (into a virtual overlay), then the shared yield and net functions with the step's
    -- happiness (taken before any claim, as the step does). Production availability counts claimed improved
    -- resources and earlier own completions' strategic resources and deployment space. The global unit cap is fog-safe:
    -- the current total (already exposed by availableProductionByCity) plus earlier own completions against the
    -- units the actor can see; unseen rival units are never counted, so they cannot change any forecast.
    -- It reads only the actor's own cities, units, technologies and territory, tiles around its cities, visible units.
    local forecasts={}
    do
        local actor=s.players[actorId]; local worked,claimed,added={},{},{}; local _,cityTiles=occupants(s)
        local stepMood=stepHappiness(s,actorId,resourceInventory(s,actorId))
        local own: {any}={}; for _, c in s.cities do if c.ownerId==actorId then table.insert(own,c) end end
        table.sort(own,function(a: any,b: any) return a.id<b.id end)
        for _, c in own do
            claim(s,c,claimed)
            local yields=cityYields(s,actor,actorId,c,worked,cityTiles,claimed); local food,made=cityNet(s,actor,c,yields,stepMood)
            local growAt=R.growthBase+c.population*R.growthPerPopulation; local cost=R.productionCosts[c.queue]
            local canGrow=stepMood>=0 and c.population<R.maxPopulation
            -- The economy completes the queue only when it is still available and a unit has a free deployment tile.
            local blocked: ("NotAvailable" | "NoSpace")?=nil; local spawn: number?=nil
            if not productionAvailable(s,c,c.queue,added,claimed) or (R.units[c.queue] and #units+#added>=R.maxUnits) then blocked="NotAvailable"
            elseif R.units[c.queue] then spawn=spawnTile(s,c,added); if not spawn then blocked="NoSpace" end end
            local turns: number?=nil
            if not blocked and cost then
                if c.production+made>=cost then turns=1 elseif made>0 then turns=math.ceil((cost-c.production)/made) end
                if turns==1 and spawn then table.insert(added,{ownerId=actorId,kind=c.queue,tileId=spawn}) end
            end
            forecasts[tostring(c.id)]={food=food,production=made,gold=yields.gold,science=yields.science,culture=yields.culture,
                growthTurns=if not canGrow then nil elseif c.food+food>=growAt then 1 elseif food>0 then math.ceil((growAt-c.food)/food) else nil,
                productionTurns=turns,productionBlocked=blocked}
        end
    end
    return {cityForecasts=forecasts,seed=if s.humanPlayers==1 or s.phase=="Finished" then s.seed else nil,radius=s.radius,mapShape=s.mapShape,frequency=s.frequency,difficulty=s.difficulty,humanPlayers=s.humanPlayers,turn=s.turn,revision=s.revision,activePlayerId=s.activePlayerId,actorId=actorId,canAct=canAct,phase=s.phase,winner=s.winner,reason=s.reason,victoryType=s.victoryType,gold=p.gold,science=p.science,culture=p.culture,happiness=p.happiness,research=copy(p.research),technologies=copy(p.technologies),policies=copy(p.policies),resources=copy(resourceInventory(s,actorId)),income=copy(p.income),tiles=tiles,units=units,cities=cities,events=events,log={},legalMoves=legal,availableProduction=production,availableProductionByCity=productionByCity,availablePurchasesByCity=purchasesByCity,availableResearch=research,availablePolicies=policies,availableImprovements=improvements,productionCosts=copy(R.productionCosts),purchaseCosts=copy(R.purchaseCosts),scores=score,statistics=stats,progress=progress,cultureVictoryPolicies=threshold,policyCostIncrease=s.policyCostIncrease or 0,attackPreviews=previews,cityStrikePreviews=strikePreviews,diplomacy=copy(s.diplomacy),trades=copy(s.trades),objectives={"Found cities, develop resources and maintain happiness.","Control both original capitals for domination.","Build SpaceProject after Rocketry for science victory.","Adopt "..threshold.." "..(if threshold==1 then "policy" else "policies").." for culture victory.","Highest score wins at the round limit; ties favor civilization 1."}}
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
-- Pure, fog-safe query for one strike the actor's city could make now (a `strikeTargets` entry): the same damage the
-- CityRangedStrike command applies. It never mutates the state, ignores turn ownership and gives one message for a
-- missing, hidden, friendly, out-of-range or peaceful target.
function BaseGame.previewCityStrike(state: State, actorId: number, cityId: number, targetUnitId: number): (CityStrikePreview?, string?)
    local s: any=state
    if (actorId~=1 and actorId~=2) or s.phase~="Playing" then return nil,"No city strike preview is available." end
    if not finiteId(cityId) or not finiteId(targetUnitId) then return nil,"No city strike preview is available." end
    local c=cityById(s,cityId); if not c or c.ownerId~=actorId then return nil,"Select your city." end
    if not strikeReady(s,c) then return nil,"This city has used its strike this round." end
    local units,cities=occupants(s); local target=unitById(s,targetUnitId)
    if not target or not strikeTargetAllowed(s,c,target,visible(s,actorId),cities) then return nil,"Choose a visible enemy unit within the city's range." end
    return cityStrikePreviewFor(s,c,target,units),nil
end
-- Pure, fog-safe query for one move the actor's unit could make now (any destination in its `legalMoves` that is
-- not an attack target): the same search MoveUnit applies, so the preview's path and remaining movement equal the
-- applied result. Snapshots carry only `legalMoves`; hosts ask for previews on demand. It reads only tiles and enemies the
-- actor can see, never mutates the state, ignores turn ownership and gives one message for any unavailable tile.
function BaseGame.previewMove(state: State, actorId: number, unitId: number, tileId: number): (MovePreview?, string?)
    local s: any=state
    if (actorId~=1 and actorId~=2) or s.phase~="Playing" then return nil,"No move preview is available." end
    if not finiteId(unitId) or not finiteId(tileId) or not s.tiles[tileId] then return nil,"No move preview is available." end
    local u=unitById(s,unitId); if not u or u.ownerId~=actorId then return nil,"Select your unit." end
    if u.moves<=0 or tileId==u.tileId then return nil,"Destination is unavailable or movement is insufficient." end
    local units,cities=occupants(s)
    local spent,previous,zoc=movementSearch(s,u,visible(s,actorId),units,cities)
    if not spent[tileId] then return nil,"Destination is unavailable or movement is insufficient." end
    return movePreviewFor(u,tileId,spent,previous,zoc),nil
end
function BaseGame.serialize(state: State): any
    local saved={format="unciv-luau-base",version=if state.mapShape=="Sphere" then 2 else 1,state=state}
    assert(Save.valid(saved),"cannot serialize an invalid base-game state"); return copy(saved)
end
function BaseGame.restore(saved: any): (State?,string?)
    -- BaseSave.restore validates, copies and snaps every unit's moves to its exact sixth, so both public restore
    -- paths produce the same canonical movement.
    local s,message=Save.restore(saved)
    if not s then return nil,message end
    mapFor(s); return s :: State,nil
end
function BaseGame.getRules(): typeof(Rules) return copy(Rules) end
return table.freeze(BaseGame)
