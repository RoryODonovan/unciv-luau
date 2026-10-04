--!strict
-- Generated module-only Roblox form. Source: src/simulation/BaseGame.luau
-- Source SHA-256: 75ed11b1f094769265d298854b683db0bf6ae901c4c7445d0339928e68008633
-- Reproduce with tools/roblox-export.mjs; preserve MPL notices below.
-- Covered source: https://github.com/RoryODonovan/unciv-luau
-- This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
-- Obtain a copy at https://mozilla.org/MPL/2.0/.
--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Provenance-Kind: original
-- Original deterministic civilization rules engine; not an Unciv parity implementation.
local Rules = require(script.Parent.BaseRules)
local WorldMap = require(script.Parent.WorldMap)
local Save = require(script.Parent.BaseSave)
export type CostCategory = "tech" | "production" | "growth" | "policy"
export type Options = {humanPlayers: number?, radius: number?, mapShape: string?, frequency: number?, difficulty: string?, forest: boolean?, maxTurns: number?, cultureVictoryPolicies: number?, policyCostIncrease: number?, barbarians: boolean?}
export type Command = {kind: "MoveUnit" | "RangedAttack", unitId: number, tileId: number}
    | {kind: "FoundCity" | "FortifyUnit" | "UpgradeUnit", unitId: number}
    | {kind: "BuildImprovement", unitId: number, improvement: string}
    | {kind: "SetProduction" | "Purchase", cityId: number, item: string}
    | {kind: "BuyTile", cityId: number, tileId: number}
    | {kind: "SetCityFocus", cityId: number, focus: string}
    | {kind: "Research", technology: string} | {kind: "AdoptPolicy", policy: string}
    | {kind: "DeclareWar" | "OfferPeace" | "AcceptPeace", targetId: number}
    | {kind: "ProposeTrade", targetId: number, giveGold: number, receiveGold: number}
    | {kind: "AcceptTrade" | "CancelTrade", tradeId: number} | {kind: "EndTurn"}
    | {kind: "PromoteUnit", unitId: number, promotion: string}
    | {kind: "CityRangedStrike", cityId: number, targetUnitId: number}
-- `feature` (Forest, Jungle, Marsh or Oasis) and `river` (an edge mask over the tile's neighbours in ascending id order;
-- see WorldMap) are optional.
export type Tile = {id: number, x: number?, y: number?, terrain: string, resource: string?, ownerId: number?, improvement: string?, road: boolean?, feature: string?, river: number?}
-- `xp` and `promotions` are optional (absent means 0 and none). `level` counts the promotions taken.
export type Unit = {id: number, ownerId: number, kind: string, tileId: number, hp: number, moves: number, fortified: boolean, level: number, xp: number?, promotions: {string}?, work: {improvement: string, remaining: number}?}
-- A unit in a snapshot. Every listed unit carries `level` and `promotions` (visible, as in Civ V). Only the actor's own
-- units carry `xp`, `nextLevelXp` (the next threshold, absent at the last level) and `promotionsAvailable` (the ids
-- PromoteUnit accepts now, empty while the actor cannot act).
-- Own units with an upgrade whose technology the owner knows also carry `upgradeKind` (the unit kind it becomes),
-- `upgradeCost` (gold) and `canUpgrade` (UpgradeUnit accepts it now: movement left, the strategic resource and the
-- gold, and the actor can act).
export type UnitView = {id: number, ownerId: number, kind: string, tileId: number, hp: number, moves: number, fortified: boolean, level: number, promotions: {string}, xp: number?, nextLevelXp: number?, promotionsAvailable: {string}?, work: {improvement: string, remaining: number}?, upgradeKind: string?, upgradeCost: number?, canUpgrade: boolean?}
-- `strikeTurn` is optional: the round whose ranged strike the city has used (it struck, or it was captured, that
-- round). Absent means the city has never used one.
-- Optional border fields: accumulated culture and post-founding culture/purchase acquisitions. Restore migrates
-- missing values; capture preserves both. New cities explicitly start at zero.
export type City = {id: number, ownerId: number, originalOwnerId: number, capital: boolean, tileId: number, name: string, population: number, food: number, production: number, queue: string, hp: number, buildings: {string}, focus: string, strikeTurn: number?, borderCulture: number?, borderTiles: number?}
export type Research = {id: string, progress: number, cost: number}
-- A civilization's golden-age record (optional; absent means an empty meter, no golden age and none so far): the meter's
-- `progress`, the owner economy steps the current golden age still lasts (`turnsLeft`, 0 outside one) and the number of
-- golden ages begun so far (`ages`), which raises the next threshold.
export type GoldenAge = {progress: number, turnsLeft: number, ages: number}
export type Player = {id: number, human: boolean, gold: number, science: number, culture: number, happiness: number, technologies: {string}, policies: {string}, research: Research?, explored: {number}, resources: {[string]: number}, income: {food: number, production: number, gold: number, science: number, culture: number, maintenance: number}, goldenAge: GoldenAge?}
-- `wonder` names the world wonder of a WonderBuilt or WonderLost event, or the wonder that started a golden age.
export type Event = {id: number, kind: string, message: string, tileId: number?, unitId: number?, ownerId: number?, amount: number?, public: boolean?, cause: string?, byOwnerId: number?, unitKind: string?, cityId: number?, wonder: string?}
-- met is optional only for legacy/raw fixtures. warPlan's treaty value invalidates a plan when peace is re-made.
export type WarPlan = {by: number, at: number, peaceUntil: number}
export type Diplomacy = {status: string, peaceOfferBy: number?, peaceUntil: number, met: boolean?, warPlan: WarPlan?}
export type DiplomacyView = {status: string, peaceOfferBy: number?, peaceUntil: number, met: boolean, warWarning: {roundsLeft: number}?}
export type Trade = {id: number, fromId: number, toId: number, giveGold: number, receiveGold: number, expires: number}
-- An explored tile shows its terrain, resource, `feature` and `river` mask (static knowledge, like terrain); an unexplored
-- tile shows none of them.
export type TileView = {id: number, x: number?, y: number?, visible: boolean, explored: boolean, terrain: string?, resource: string?, feature: string?, river: number?, ownerId: number?, improvement: string?, road: boolean?, food: number?, production: number?, gold: number?}
-- A city in a snapshot. Only the actor's own cities carry the economy fields and the city-combat fields: `strength`
-- (combat strength), `rangedStrength` (what its strike uses), `strikeReady` (its strike for this round is unused),
-- `canStrike` (ready, the actor can act now and at least one target is legal) and `strikeTargets` (the unit ids
-- CityRangedStrike accepts now, ascending; empty while the actor cannot act).
export type CityView = {id: number, ownerId: number, originalOwnerId: number, capital: boolean, tileId: number, name: string, population: number, hp: number, food: number?, production: number?, queue: string?, buildings: {string}?, focus: string?, strength: number?, rangedStrength: number?, strikeReady: boolean?, canStrike: boolean?, strikeTargets: {number}?, borderCulture: number?, nextTileCost: number?, borderTurns: number?, buyableTiles: {{tileId: number, cost: number}}?, nextBorderTile: number?}
export type Statistics = {cities: number, units: number, population: number, technologies: number, policies: number}
export type Progress = {cities: number, policies: number, era: number}
-- `acrossRiver` is true when a melee attack crosses a river edge (its attack loses riverAttackPercent).
-- `advances` is true when a melee attack kills a unit outside a city and the attacker moves onto its tile: it survives
-- and its owner may enter that land (a civilization at peace keeps its borders closed even to a unit chasing a
-- barbarian). `clearsCamp` is true when that advance enters a barbarian encampment and destroys it. Both are exact (a
-- strike on a unit outside a city is exact); a city capture is reported by `captures`.
export type AttackPreview = {unitId: number, tileId: number, target: string, ranged: boolean, exact: boolean, hiddenDefense: boolean, acrossRiver: boolean, advances: boolean, clearsCamp: boolean, dealt: number?, received: number?, dealtMin: number, dealtMax: number, receivedMin: number, receivedMax: number, attackerHp: number, defenderHp: number, attackerDefeated: string, defenderDefeated: string, captures: string}
-- One legal move: the path from the unit's tile (first) to the destination (last), the movement it spends and keeps,
-- whether it ends the unit's movement, whether the zone of control ended it and whether its final step crossed a river
-- (which also ends it). `clearsCamp` is true when the destination is a barbarian encampment, which the move destroys
-- (entering one ends movement). Values are in moves (multiples of 1/6).
export type MovePreview = {unitId: number, tileId: number, path: {number}, movesSpent: number, movesLeft: number, endsMovement: boolean, zoneOfControl: boolean, riverCrossing: boolean, clearsCamp: boolean}
-- One legal city strike: the striking city, the target unit and its tile, the city's ranged strength, the exact damage
-- (a strike is deterministic and reads only visible facts, so `exact` is always true), `received` (always 0: the
-- city takes no damage), the target's hit points before the strike and whether it dies ("Yes" or "No").
export type CityStrikePreview = {cityId: number, unitId: number, tileId: number, rangedStrength: number, exact: boolean, dealt: number, received: number, defenderHp: number, defenderDefeated: string}
export type Technology = Rules.Technology
export type Policy = Rules.Policy
export type Promotion = Rules.Promotion
-- A barbarian encampment: its id, tile, the round it appeared and the round it last added a unit.
export type Camp = {id: number, tileId: number, founded: number, lastSpawn: number}
-- The barbarian record, present exactly when the match has barbarians (absent in a match without them and in every
-- save written before them).
export type Barbarians = {camps: {Camp}, nextCamp: number}
-- A barbarian encampment in a snapshot (only while its tile is visible to the actor).
export type CampView = {id: number, tileId: number}
export type State = {barbarians: Barbarians?, seed: number, radius: number?, mapShape: string?, frequency: number?, difficulty: string, humanPlayers: number, forest: boolean, maxTurns: number, cultureVictoryPolicies: number?, policyCostIncrease: number?, turn: number, revision: number, activePlayerId: number, phase: string, winner: number?, reason: string?, victoryType: string?, tiles: {Tile}, units: {Unit}, cities: {City}, players: {Player}, diplomacy: Diplomacy, trades: {Trade}, events: {Event}, nextEvent: number, nextUnit: number, nextCity: number, nextTrade: number, log: {string}}
export type CityForecast = {food: number, production: number, gold: number, science: number, culture: number, growthTurns: number?, productionTurns: number?, productionBlocked: ("NotAvailable" | "NoSpace" | "Idle")?}
-- A completed world wonder, public to both civilizations: its id and the civilization whose city holds it now. The
-- holding city (`cityId`, `tileId`, `cityName`) is given only to that city's owner and to an actor who can see the city
-- tile now.
export type WonderView = {id: string, ownerId: number, cityId: number?, tileId: number?, cityName: string?}
-- The actor's own golden age: whether one is active, the owner economy steps it still lasts, the meter's progress and
-- threshold, the golden ages begun so far, what the next step adds to the meter (the current happiness when positive
-- and no golden age is active, otherwise 0) and how many steps a new golden age lasts in this match.
export type GoldenAgeView = {active: boolean, turnsLeft: number, progress: number, threshold: number, ages: number, progressPerTurn: number, turns: number}
-- The actor's own strategic resource: `have` is what its improved tiles supply (tiles x quantity), `used` what its living
-- units need. `used` can exceed `have` (after losing a tile); existing units are unaffected, but no new unit or upgrade
-- needing the resource is possible until `have - used` covers it.
export type StrategicView = {have: number, used: number}
export type View = {strategic: {[string]: StrategicView}, barbarians: boolean, camps: {CampView}, cityForecasts: {[string]: CityForecast}, seed: number?, radius: number?, mapShape: string?, frequency: number?, difficulty: string, humanPlayers: number, turn: number, revision: number, activePlayerId: number, actorId: number, canAct: boolean, phase: string, winner: number?, reason: string?, victoryType: string?, gold: number, science: number, culture: number, happiness: number, research: Research?, technologies: {string}, policies: {string}, resources: {[string]: number}, income: {food: number, production: number, gold: number, science: number, culture: number, maintenance: number}, tiles: {TileView}, units: {UnitView}, cities: {CityView}, events: {Event}, log: {string}, legalMoves: {[string]: {number}}, riverMoves: {[string]: {number}}, availableProduction: {string}, availableProductionByCity: {[string]: {string}}, availablePurchasesByCity: {[string]: {string}}, availableResearch: {Technology}, availablePolicies: {Policy}, availableImprovements: {[string]: {string}}, productionCosts: {[string]: number}, purchaseCosts: {[string]: number}, scores: {number}, statistics: {Statistics}, progress: {Progress}, cultureVictoryPolicies: number, policyCostIncrease: number, attackPreviews: {[string]: {AttackPreview}}, cityStrikePreviews: {[string]: {CityStrikePreview}}, diplomacy: DiplomacyView, trades: {Trade}, objectives: {string}, wonders: {WonderView}, goldenAge: GoldenAgeView}
local BaseGame = {}
local R: any = Rules
local W: any = WorldMap
local improvementOrder: {string} = R.improvementOrder or {"Farm","Mine","Pasture","Plantation","Camp","Well","Road"}
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
-- Barbarians are a non-playing faction: their units carry this owner id, which no civilization uses. Every civilization
-- is always at war with them; between the two civilizations hostility follows their diplomacy.
local BARBARIAN: number=R.barbarians.ownerId
local function hostile(s: any, a: number, b: number): boolean
    if a==b then return false end
    if a==BARBARIAN or b==BARBARIAN then return true end
    return s.diplomacy.status=="War"
end
-- Whether the unit's owner may enter the tile's territory: unowned or own land, or land of an owner it is hostile to
-- (the other civilization at war; barbarians may enter any land). Movement and a melee attacker's advance both obey it.
local function territoryOpen(s: any, unit: any, tileId: number): boolean
    local owner=s.tiles[tileId].ownerId
    return owner==nil or owner==unit.ownerId or hostile(s,unit.ownerId,owner)
end
-- The barbarian encampments by tile (empty when the match has none).
local function campTiles(s: any): {[number]: any}
    local tiles={}; if s.barbarians then for _, camp in s.barbarians.camps do tiles[camp.tileId]=camp end end; return tiles
end
-- Event kinds the ring keeps longest (each player must reliably learn of its losses and the result).
-- Wonder and golden-age events are rare (a few per match) and are kept too, so a burst cannot evict them either.
-- A cleared barbarian camp carries its reward and is kept too. A barbarian's own loss (owner 0) is routine: no player
-- owns it.
local RETAINED={UnitLost=true, CityLost=true, Eliminated=true, Victory=true, WonderBuilt=true, WonderLost=true, GoldenAgeStarted=true, GoldenAgeEnded=true, CampCleared=true, Contact=true, WarWarning=true}
local function event(s: any, kind: string, message: string, tileId: number?, unitId: number?, ownerId: number?, amount: number?, public: boolean?, cause: string?, byOwnerId: number?, unitKind: string?, cityId: number?, wonder: string?)
    table.insert(s.events, {id=s.nextEvent, kind=kind, message=message, tileId=tileId, unitId=unitId, ownerId=ownerId, amount=amount, public=public, cause=cause, byOwnerId=byOwnerId, unitKind=unitKind, cityId=cityId, wonder=wonder})
    s.nextEvent += 1
    if #s.events > 64 then
        -- One command (an EndTurn running the AI and both economies) can emit more than 64 events, so
        -- routine events go first: the oldest one that is not a loss or outcome, never the event just added.
        local drop=1
        for i=1,#s.events-1 do local e=s.events[i]; if not RETAINED[e.kind] or e.ownerId==BARBARIAN then drop=i; break end end
        table.remove(s.events, drop)
    end
end
-- Loss events are owned by the losing civilization, so its projection includes them whatever
-- its current fog. Saves written before these fields existed simply lack them.
local function unitLost(s: any, u: any, tileId: number, cause: string, byOwnerId: number?, damage: number?)
    local message=if u.ownerId==BARBARIAN then "A barbarian "..u.kind.." was destroyed." else "Your "..u.kind.." was destroyed."
    event(s,"UnitLost",message,tileId,u.id,u.ownerId,damage,nil,cause,byOwnerId,u.kind)
end
-- The culture victory threshold and per-adoption policy cost growth are stored per game.
-- A state without them (saved by an earlier library version) keeps the original flat rule.
local function cultureThreshold(s: any): number return s.cultureVictoryPolicies or R.cultureVictoryPolicies or 6 end
-- World wonders. A wonder is built when a city holds it; cities are never destroyed, so the holding city is the whole
-- record (no separate state). Its empire effects serve whoever owns that city now.
local function isWonder(id: string): boolean local rule=R.buildings[id]; return rule~=nil and rule.wonder==true end
local function wonderCity(s: any, id: string): any
    for _, c in s.cities do if has(c.buildings,id) then return c end end; return nil
end
-- The empire effects of the wonders the owner's cities hold. The economy reads them once at the start of a step (like
-- its happiness), so a wonder completed during the step takes effect from the next one and the forecast stays exact.
local function empireBonus(s: any, owner: number): any
    local bonus={yields={food=0,production=0,gold=0,science=0,culture=0},sciencePercent=0,policyCostPercent=0,unitExperience=0,golden=false}
    for _, c in s.cities do
        if c.ownerId~=owner then continue end
        for _, id in c.buildings do
            local rule=R.buildings[id]
            if not rule.wonder then continue end
            for key,value in rule.globalYields do bonus.yields[key] += value end
            bonus.sciencePercent += rule.sciencePercent; bonus.policyCostPercent += rule.policyCostPercent; bonus.unitExperience += rule.unitExperience
        end
    end
    bonus.policyCostPercent=math.min(90,bonus.policyCostPercent); bonus.unitExperience=math.min(R.maxExperience,bonus.unitExperience)
    return bonus
end
-- Golden ages. The pace percentage scales the threshold and the length with the round limit (120 rounds is 100%).
local function pacePercent(s: any): number
    local g=R.goldenAge
    return math.clamp(math.floor(s.maxTurns*100/g.paceTurns+0.5),g.minPacePercent,g.maxPacePercent)
end
-- Independent of golden-age/barbarian pace. Derived from the saved round limit, including on restore.
local function costPercent(s: any, category: CostCategory?): number
    local pace=R.costPace
    local c=pace[category or "tech"]
    return math.clamp(math.floor(100*(s.maxTurns/pace.turns)^c.exponent+0.5),c.minPercent,c.maxPercent)
end
local function scaledCost(s: any, base: number, category: CostCategory?): number return math.max(1,math.floor(base*costPercent(s,category)/100+0.5)) end
local function productionCost(s: any, item: string): number return scaledCost(s,R.productionCosts[item],"production") end
local function purchaseCost(s: any, item: string): number
    return productionCost(s,item)*R.purchaseCosts[item]/R.productionCosts[item]
end
local function growthCost(s: any, population: number): number return scaledCost(s,R.growthBase+population*R.growthPerPopulation,"growth") end
local function goldenAgeTurns(s: any): number return math.max(1,math.floor(R.goldenAge.turns*pacePercent(s)/100+0.5)) end
local function goldenAgeThreshold(s: any, ages: number): number
    return math.floor((R.goldenAge.threshold+R.goldenAge.thresholdIncrease*ages)*pacePercent(s)/100)
end
local function goldenActive(p: any): boolean return p.goldenAge~=nil and p.goldenAge.turnsLeft>0 end
-- Barbarian timing: a number of rounds scaled by the match pace and the difficulty, never below one round.
local function barbarianRounds(s: any, rounds: number): number
    local percent=R.barbarians.difficultyPercent[s.difficulty] or 100
    return math.max(1,math.floor(rounds*pacePercent(s)*percent/10000+0.5))
end
-- The gold for clearing a camp, scaled by the match pace (rounded down).
local function campGold(s: any): number return math.floor(R.barbarians.campGold*pacePercent(s)/100) end
-- A civilization's military unit that ends a move or an attack's advance on a barbarian camp destroys it and earns
-- its owner the camp's gold (a CampCleared event owned by that civilization). Civilians never enter camps, and
-- barbarians' own units stand in them freely.
local function enterCamp(s: any, unit: any)
    if not s.barbarians or unit.ownerId==BARBARIAN or R.units[unit.kind].strength<=0 then return end
    for index, camp in s.barbarians.camps do
        if camp.tileId==unit.tileId then
            table.remove(s.barbarians.camps,index)
            local gold=campGold(s); local p=s.players[unit.ownerId]; p.gold=math.min(1000000000,p.gold+gold)
            event(s,"CampCleared","Barbarian encampment destroyed: "..gold.." gold.",camp.tileId,unit.id,unit.ownerId,gold,nil,nil,nil,unit.kind)
            return
        end
    end
end
-- A policy's culture cost: escalated by the policies already adopted, then reduced by the owner's wonders (Oracle).
local function policyCost(s: any, p: any, policy: any): number
    local cost=math.floor(scaledCost(s,policy.cost,"policy")*(100+(s.policyCostIncrease or 0)*#p.policies)/100)
    local discount=empireBonus(s,p.id).policyCostPercent
    if discount>0 then cost=math.floor(cost*(100-discount)/100) end
    return cost
end
local function visible(s: any, owner: number): any
    local centers = {}; for _, u in s.units do if u.ownerId == owner then table.insert(centers, u.tileId) end end
    for _, c in s.cities do if c.ownerId == owner then table.insert(centers, c.tileId) end end
    local set = {}; for _, center in centers do for _, id in nearby(s,center,2) do set[id]=true end end; return set
end
local function contact(s: any, owner: number, seen: any)
    if s.diplomacy.met then return end
    local other=3-owner
    for _, entities in {s.units,s.cities} do
        for _, entity in entities do
            if entity.ownerId==other and seen[entity.tileId] then
                s.diplomacy.met=true
                event(s,"Contact","Contact established with the rival civilization.",nil,nil,nil,nil,true)
                return
            end
        end
    end
end
local function refreshVision(s: any)
    for owner=1,2 do
        local discovered = {}; for _, id in s.players[owner].explored do discovered[id] = true end
        local seen=visible(s,owner); contact(s,owner,seen)
        for id in seen do discovered[id] = true end
        local ids = {}; for id in discovered do table.insert(ids,id) end; table.sort(ids); s.players[owner].explored = ids
    end
end
local function removeUnit(s: any, id: number)
    for i,u in s.units do if u.id == id then table.remove(s.units,i); return end end
end
local function addUnit(s: any, owner: number, kind: string, tileId: number): any
    local stats = R.units[kind]
    local u={id=s.nextUnit, ownerId=owner, kind=kind, tileId=tileId, hp=stats.hp, moves=0, fortified=false, level=0}
    table.insert(s.units, u)
    s.nextUnit += 1
    return u
end
-- Founding alone claims the first ring. Population never changes territory.
local function claim(s: any, city: any)
    local ids = nearby(s,city.tileId,1)
    for _, id in ids do
        local t=s.tiles[id]
        if not t.ownerId or id==city.tileId then t.ownerId=city.ownerId end
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
    local c = {id=s.nextCity, ownerId=owner, originalOwnerId=owner, capital=capital, tileId=tileId, name=name, population=1, food=0, production=0, queue="Warrior", hp=R.cityHp, buildings={}, focus="Balanced",borderCulture=0,borderTiles=0}
    -- The tile keeps its feature (unlike Civ V, which clears it): features never change after generation, so an explored
    -- tile's projected feature and natural yields cannot reveal an unseen city.
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
-- Strategic resources (G7 quantities). A civilization has `quantity` of a strategic resource for each improved tile of
-- it that it owns (with `claimed`, the forecast's virtual claims count as its own), and it uses each of its living
-- units' `resourceAmount`. Both are derived from the state, so nothing is stored. `extra` adds units that do not exist
-- yet (the forecast's earlier completions); `exclude` leaves out a unit being upgraded, whose own use ends.
local function strategicHave(s: any, owner: number, claimed: {[number]: boolean}?): {[string]: number}
    local result: {[string]: number}={}
    for id, count in resourceInventory(s,owner,claimed) do
        local rule=R.resources[id]; if rule.category=="Strategic" then result[id]=count*rule.quantity end
    end
    return result
end
local function strategicUsed(s: any, owner: number, extra: {any}?, exclude: any?): {[string]: number}
    local result: {[string]: number}={}
    local function add(u: any)
        if u.ownerId~=owner or u==exclude then return end
        local rule=R.units[u.kind]; if rule.resource then result[rule.resource]=(result[rule.resource] or 0)+(rule.resourceAmount or 1) end
    end
    for _, u in s.units do add(u) end
    if extra then for _, u in extra do add(u) end end
    return result
end
-- A civilization's strategic stock: `have` and `used` per resource. Hot callers (the snapshot's menus, the AI) compute
-- it once and pass it on.
local function strategicStock(s: any, owner: number, extra: {any}?, claimed: {[number]: boolean}?, exclude: any?): any
    return {have=strategicHave(s,owner,claimed),used=strategicUsed(s,owner,extra,exclude)}
end
-- Whether the stock spares `entry`'s strategic resource for one more unit.
local function resourceSpare(stock: any, entry: any): boolean
    if not entry.resource then return true end
    return (stock.have[entry.resource] or 0)-(stock.used[entry.resource] or 0)>=(entry.resourceAmount or 1)
end
-- For the forecast, `extra` lists the city owner's units that do not exist yet but would by then (earlier
-- completions this step) and `claimed` the tiles its claims would own by then. Neither changes the global unit
-- cap check, which counts every unit (including unseen rival units) and so stays at the current count. `stock` is the
-- owner's precomputed strategic stock (only without `extra` and `claimed`).
local function productionAvailable(s: any, city: any, item: string, extra: {any}?, claimed: {[number]: boolean}?, stock: any?): boolean
    local entry=R.units[item] or R.buildings[item]
    if not entry then return false end
    local player=s.players[city.ownerId]
    if entry.technology and not has(player.technologies,entry.technology) then return false end
    if R.buildings[item] and has(city.buildings,item) then return false end
    -- A world wonder can be completed once per world. Completion is public, so this check reveals nothing hidden.
    if isWonder(item) and wonderCity(s,item) then return false end
    if R.units[item] and #s.units >= R.maxUnits then return false end
    if entry.resource and not resourceSpare(stock or strategicStock(s,city.ownerId,extra,claimed),entry) then return false end
    return true
end
local function spawnTile(s: any, city: any, extra: {any}?): number?
    local units,cities=occupants(s); local camps=campTiles(s)
    if extra then for _, u in extra do units[u.tileId]=u end end
    local ids={city.tileId}; for _, id in mapFor(s).neighbors[city.tileId] do table.insert(ids,id) end; table.sort(ids)
    for _, id in ids do
        local tile=s.tiles[id]
        local territoryAllowed=not tile.ownerId or tile.ownerId==city.ownerId or s.diplomacy.status=="War"
        -- A barbarian camp next to the city is never a deployment tile (the city's owner always sees it).
        if not units[id] and not camps[id] and R.terrains[tile.terrain].passable and territoryAllowed and (not cities[id] or cities[id].ownerId==city.ownerId) then return id end
    end
    return nil
end
-- Whether a city may choose an item now (SetProduction, the AI and the production menus): it must be available, and a
-- wonder must not already be queued in another of the owner's cities (one city races for each wonder, as in Civ V).
-- The economy's completion check uses productionAvailable alone, so a queue never stalls on this rule.
local function canChoose(s: any, city: any, item: string, stock: any?): boolean
    if not productionAvailable(s,city,item,nil,nil,stock) then return false end
    if isWonder(item) then for _, c in s.cities do if c~=city and c.ownerId==city.ownerId and c.queue==item then return false end end end
    return true
end
-- The refusal when a strategic resource is short: what one more unit needs, what the owner's improved tiles supply and
-- what its living units use (all its own facts).
local function shortageMessage(stock: any, entry: any): string
    local id=entry.resource
    return string.format("Not enough %s: needs %d, %d available and %d in use.",R.resources[id].name,entry.resourceAmount or 1,stock.have[id] or 0,stock.used[id] or 0)
end
-- Why SetProduction or Purchase refuses an item: the shortage message when the only obstacle is a unit's strategic
-- resource, otherwise the general message.
local function productionRefusal(s: any, city: any, item: string): string
    local entry=R.units[item]
    if entry and entry.resource and (not entry.technology or has(s.players[city.ownerId].technologies,entry.technology)) and #s.units<R.maxUnits then
        local stock=strategicStock(s,city.ownerId)
        if not resourceSpare(stock,entry) then return shortageMessage(stock,entry) end
    end
    return "Production item is unavailable."
end
-- Unit upgrades. A unit's upgrade is its rule's `upgradeTo` once its owner knows that kind's technology; it costs
-- max(paced upgradeMinimumGold, paced new cost - paced old cost) x upgradeCostMultiplier gold. UpgradeUnit needs movement left and the
-- new kind's strategic resource, with the unit's own use counted as freed (a Knight becoming a Lancer keeps its Horses).
-- The global unit cap does not apply, as no unit is added.
local function upgradeKind(s: any, u: any): string?
    local nextKind=R.units[u.kind].upgradeTo
    if not nextKind or u.ownerId==BARBARIAN then return nil end
    local technology=R.units[nextKind].technology
    if technology and not has(s.players[u.ownerId].technologies,technology) then return nil end
    return nextKind
end
local function upgradeCost(s: any, kind: string, nextKind: string): number
    return math.max(scaledCost(s,R.upgradeMinimumGold,"production"),productionCost(s,nextKind)-productionCost(s,kind))*R.upgradeCostMultiplier
end
-- Why UpgradeUnit refuses the unit now, or nil when it accepts it (turn ownership aside).
local function upgradeRefusal(s: any, u: any): string?
    local nextKind=upgradeKind(s,u)
    if not nextKind or u.moves<=0 then return "Upgrade technology is unavailable." end
    local stock=strategicStock(s,u.ownerId,nil,nil,u)
    if not resourceSpare(stock,R.units[nextKind]) then return shortageMessage(stock,R.units[nextKind]) end
    if s.players[u.ownerId].gold<upgradeCost(s,u.kind,nextKind) then return "Upgrade requires gold and strategic resources." end
    return nil
end
-- Applies an accepted upgrade: the gold is spent, the kind changes and movement ends. Hit points, experience,
-- promotions (an upgrade keeps the unit class) and fortification are kept.
local function upgrade(s: any, u: any)
    local nextKind=upgradeKind(s,u) :: string
    s.players[u.ownerId].gold -= upgradeCost(s,u.kind,nextKind); u.kind=nextKind; u.moves=0
    event(s,"Upgrade","Unit upgraded.",u.tileId,u.id,u.ownerId)
end
-- A completed world wonder: a public WonderBuilt event (its location is projected only to those who can see the city;
-- see the snapshot), then every other city queuing the same wonder loses the race. Such a city keeps all its
-- accumulated production for its next item, its queue becomes idle (as after any completed building) and its
-- owner gets a private WonderLost event without a tile. `converted` marks those cities so an economy step in progress
-- does not complete anything in them this step.
local function wonderBuilt(s: any, city: any, item: string, converted: {[number]: boolean}?)
    local name=R.buildings[item].name
    event(s,"WonderBuilt",name.." was completed by civilization "..city.ownerId..".",city.tileId,nil,city.ownerId,nil,true,nil,nil,nil,city.id,item)
    local losers: {any}={}; for _, c in s.cities do if c~=city and c.queue==item then table.insert(losers,c) end end
    table.sort(losers,function(a: any,b: any) return a.id<b.id end)
    for _, c in losers do
        c.queue=""; if converted then converted[c.id]=true end
        local message=if c.ownerId==city.ownerId then "Another of your cities completed "..name.." first; production is kept." else "A rival completed "..name.." first; production is kept."
        event(s,"WonderLost",message,nil,nil,c.ownerId,c.production,nil,nil,city.ownerId,nil,c.id,item)
    end
end
-- `bonus` is the owner's empireBonus captured at the start of an economy step, so a wonder completed earlier in the
-- same step (in a city processed first) changes nothing until the next step, whatever the city order. A purchase,
-- outside any economy step, passes none and reads the owner's wonders as they stand.
local function complete(s: any, city: any, item: string, spawn: number?, converted: {[number]: boolean}?, bonus: any?)
    if R.buildings[item] then table.insert(city.buildings,item); if city.queue==item then city.queue="" end
    else
        assert(spawn); local u=addUnit(s,city.ownerId,item,spawn)
        -- New military units start with the experience the owner's wonders give (Terracotta Army); civilians never gain any.
        if R.units[item].unitClass~="Civilian" then
            local xp=(bonus or empireBonus(s,city.ownerId)).unitExperience
            if xp>0 then u.xp=xp end
        end
    end
    event(s,"Production","Completed "..item..".",city.tileId,nil,city.ownerId)
    if isWonder(item) then wonderBuilt(s,city,item,converted) end
end
local function finish(s: any, winner: number?, kind: string, tieBroken: boolean?)
    s.phase="Finished"; s.winner=winner; s.victoryType=kind
    if kind=="Draw" then s.reason="Draw: equal score, technologies and policies."
    else
        assert(winner)
        s.reason=kind.." victory for civilization "..winner..(if tieBroken then " (tie broken by technologies and policies)." else ".")
    end
    event(s,"Victory",s.reason,nil,nil,winner,nil,true)
end
local function scores(s: any): (any,any)
    local values,stats={0,0},{}
    for owner=1,2 do
        local p=s.players[owner]; stats[owner]={cities=0,units=0,population=0,technologies=#p.technologies,policies=#p.policies}
        values[owner]=#p.technologies*R.score.technology+#p.policies*R.score.policy
    end
    for _, c in s.cities do
        stats[c.ownerId].cities += 1; stats[c.ownerId].population += c.population; values[c.ownerId] += R.score.city+c.population*R.score.population
        -- Each world wonder scores for the civilization holding it.
        for _, id in c.buildings do if isWonder(id) then values[c.ownerId] += R.score.wonder or 0 end end
    end
    -- Barbarian units belong to no civilization and score nothing.
    for _, u in s.units do if u.ownerId~=BARBARIAN then stats[u.ownerId].units += 1; values[u.ownerId] += R.score.unit end end
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
        if has(p.technologies,R.scienceVictoryTechnology) then
            for _, c in s.cities do if c.ownerId==owner and has(c.buildings,R.scienceVictoryBuilding) then finish(s,owner,"Science"); return end end
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
-- Terrain features. A tile's movement cost is the larger of its terrain's and its feature's; its defence percentage is
-- their sum; it is rough when either is.
local function tileMovement(tile: any): number
    local moves=R.terrains[tile.terrain].movement
    if tile.feature then moves=math.max(moves,R.features[tile.feature].movement) end
    return moves
end
local function defensePercentAt(s: any, tileId: number): number
    local tile=s.tiles[tileId]; local percent=R.terrains[tile.terrain].defensePercent or 0
    if tile.feature then percent += R.features[tile.feature].defensePercent end
    return percent
end
local function roughAt(s: any, tileId: number): boolean
    local tile=s.tiles[tileId]
    return R.terrains[tile.terrain].rough or (tile.feature~=nil and R.features[tile.feature].rough)
end
-- Rivers run along tile edges (WorldMap.riverBetween reads the edge mask).
local function riverBetween(s: any, a: number, b: number): boolean return W.riverBetween(mapFor(s),a,b) end
-- A step across a river edge spends all remaining movement, unless both tiles have roads (the road bridges the river).
local function riverCrossing(s: any, fromId: number, toId: number): boolean
    return riverBetween(s,fromId,toId) and not (s.tiles[fromId].road and s.tiles[toId].road)
end
-- The cost in sixths of stepping from `fromId` into the adjacent `toId`, or nil when the step is not allowed. Only
-- tiles the mover can see may be entered. Between two road tiles a step costs a third of a move, whatever the terrain
-- or feature.
local function movementCost(s: any, unit: any, fromId: number, toId: number, seen: any, units: any, cities: any): number?
    if not seen[toId] then return nil end
    local tile=s.tiles[toId]; local terrain=R.terrains[tile.terrain]
    if not terrain.passable then return nil end
    local occupant,city=units[toId],cities[toId]
    if occupant and occupant.id~=unit.id then return nil end
    if city and city.ownerId~=unit.ownerId then return nil end
    -- Foreign land only when hostile: the other civilization at war, and any land for barbarians.
    if not territoryOpen(s,unit,toId) then return nil end
    if tile.road and s.tiles[fromId].road then return roadSixths end
    return tileMovement(tile)*SIXTHS
end
-- Tiles that exert a zone of control on this unit: hostile military units (strength above zero) and hostile cities,
-- only where the moving civilization can see them, so a move never reveals a hidden unit. Hostile means the other
-- civilization at war, and barbarians always (in both directions). Civilians neither exert nor feel a zone of control
-- (nil: none applies).
local function zoneSources(s: any, unit: any, seen: any, units: any, cities: any): {[number]: boolean}?
    if R.units[unit.kind].strength<=0 then return nil end
    local sources: {[number]: boolean}={}; local found=false
    for tileId,u in units do if seen[tileId] and R.units[u.kind].strength>0 and hostile(s,unit.ownerId,u.ownerId) then sources[tileId]=true; found=true end end
    for tileId,c in cities do if seen[tileId] and hostile(s,unit.ownerId,c.ownerId) then sources[tileId]=true; found=true end end
    return if found then sources else nil
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
-- costs 0), the previous tile on the cheapest path, whether the zone of control ended the final step and whether the
-- final step crossed a river. A unit with any movement left may always enter an adjacent allowed tile: when the step
-- costs at least what remains, the zone of control applies or it crosses a river, the unit arrives with no movement
-- left. Arrival never decreases as the spent amount grows, so Dijkstra's order stays exact. Ties settle the lowest tile
-- id first and keep the first path found. Costs are whole sixths and every step arrives strictly later than it leaves,
-- so a bucket per spent sixth (at most the unit's maximum moves times six) is complete when reached; sorting it settles
-- that cost's tiles by id. The search is therefore linear in the tiles it reaches, apart from those small sorts.
local function movementSearch(s: any, unit: any, seen: any, units: any, cities: any): ({[number]: number}, {[number]: number}, {[number]: boolean}, {[number]: boolean})
    local budget=toSixths(unit.moves)
    local spent: {[number]: number}={[unit.tileId]=0}; local previous: {[number]: number}={}; local zoc: {[number]: boolean}={}; local crossed: {[number]: boolean}={}
    if budget<=0 then return spent,previous,zoc,crossed end
    local sources=zoneSources(s,unit,seen,units,cities); local neighbors=mapFor(s).neighbors; local settled: {[number]: boolean}={}
    -- Barbarian encampments: a civilization's military unit may enter one (destroying it), which ends its movement, so
    -- it never passes through; civilians cannot enter one. Barbarians move through their camps freely. Only visible
    -- tiles are entered, so this reads only camps the mover can see.
    local camps=if unit.ownerId==BARBARIAN then {} else campTiles(s); local civilian=R.units[unit.kind].strength<=0
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
                local camp=camps[nextId]~=nil
                if camp and civilian then continue end
                local controlled=zoneOfControl(s,sources,current,nextId)
                local crossing=riverCrossing(s,current,nextId)
                local arrival=if controlled or crossing or camp then budget else math.min(budget,here+step)
                if spent[nextId]==nil or arrival<spent[nextId] then
                    spent[nextId]=arrival; previous[nextId]=current; zoc[nextId]=controlled; crossed[nextId]=crossing
                    local later=buckets[arrival]; if later then table.insert(later,nextId) else buckets[arrival]={nextId} end
                end
            end
        end
    end
    return spent,previous,zoc,crossed
end
local function reachable(s: any, unit: any, vision: any?, occupancyUnits: any?, occupancyCities: any?): any
    if unit.moves<=0 then return {} end
    local seen=vision or visible(s,unit.ownerId); local units,cities=occupancyUnits,occupancyCities
    if not units or not cities then units,cities=occupants(s) end
    return (movementSearch(s,unit,seen,units,cities))
end
-- The fog-safe record of one legal move, built from a movement search.
local function movePreviewFor(s: any, unit: any, target: number, spent: any, previous: any, zoc: any, crossed: any): MovePreview
    local path={target}; local current=target
    while current~=unit.tileId do current=previous[current]; table.insert(path,1,current) end
    local left=fromSixths(toSixths(unit.moves)-spent[target])
    return {unitId=unit.id,tileId=target,path=path,movesSpent=fromSixths(spent[target]),movesLeft=left,endsMovement=left<=0,zoneOfControl=zoc[target]==true,riverCrossing=crossed[target]==true,
        clearsCamp=campTiles(s)[target]~=nil}
end
local function attackable(s: any, unit: any, target: number, seen: any, occupancyUnits: any?, occupancyCities: any?): boolean
    if not seen[target] or unit.moves<=0 or R.units[unit.kind].strength<=0 then return false end
    local units,cities=occupancyUnits,occupancyCities; if not units or not cities then units,cities=occupants(s) end
    local enemy=units[target] or cities[target]
    if not enemy or not hostile(s,unit.ownerId,enemy.ownerId) then return false end
    return W.inRange(mapFor(s),unit.tileId,target,math.max(1,R.units[unit.kind].range or 1))
end
local function attackTargets(s: any, unit: any, seen: any, units: any, cities: any): {number}
    if unit.moves<=0 or R.units[unit.kind].strength<=0 then return {} end
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
-- Barbarian units never gain experience. A strike against barbarians (`versusBarbarian`) raises a unit's experience
-- only up to the barbarian cap (Civ V's 30): a unit at or above it gains nothing from them.
local function gainExperience(u: any, amount: number, versusBarbarian: boolean?)
    if R.units[u.kind].unitClass=="Civilian" or u.ownerId==BARBARIAN then return end
    local current=u.xp or 0; local gained=math.min(R.maxExperience,current+amount)
    if versusBarbarian then gained=math.max(current,math.min(gained,R.barbarians.maxExperience)) end
    if gained~=current or u.xp~=nil then u.xp=gained end
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
    local rough=roughAt(s,u.tileId)
    for _, id in options do local p=R.promotions[id]; if (if rough then p.roughPercent else p.openPercent)>0 then return id end end
    return options[1]
end
-- The percentage a unit's promotions add to its strength in one strike. The strike's target tile decides rough or
-- open terrain for both sides. Cover counts while defending against a ranged attack, Accuracy on a ranged attack
-- against a unit. A unit's promotions are visible with the unit, so the preview may read the defender's.
local function promotionPercent(s: any, u: any, target: number, attacking: boolean, rangedStrike: boolean, againstUnit: boolean): number
    local taken=u.promotions; if not taken then return 0 end
    local rough=roughAt(s,target)
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
-- The percentage a unit's `versus` bonus adds against a unit of the given role (the Spearman line against Mounted
-- units, the Anti-Tank Gun against Armor). Roles are visible with the unit, so previews may read it.
local function versusPercent(u: any, otherRole: string?): number
    if not otherRole then return 0 end
    return R.units[u.kind].versus[otherRole] or 0
end
-- A unit's defence on the target tile against one strike (ranged or melee): max(3, defense) x (100 + terrain% +
-- fortified% + promotion% + versus%)/100 x (0.5 + hp/200), where the terrain percentage includes the tile's feature and
-- versus% is the defender's bonus against the attacker's role (none for a city strike: `attackerRole` is nil). Shared by
-- unit strikes and city strikes.
local function unitDefense(s: any, defender: any, target: number, rangedStrike: boolean, attackerRole: string?): number
    local terrain=defensePercentAt(s,target)
    local modifier=terrain+(if defender.fortified then R.fortifyDefensePercent else 0)+promotionPercent(s,defender,target,false,rangedStrike,true)+versusPercent(defender,attackerRole)
    return math.max(3,R.units[defender.kind].defense)*(100+modifier)/100*(0.5+defender.hp/200)
end
-- Deterministic damage for one strike, given the target city's building defence and the tile-to-unit occupancy.
-- Attack: base x (0.5 + hp/200) x (100 + flanking% + promotion% + siege% + versus% - river%)/100, where the base is the
-- unit's rangedStrength for a ranged unit and its `attack` otherwise (G7: separate from its defence); flanking applies
-- only to melee attacks on a defending unit, siege only when the target tile holds an (enemy) city, versus only against
-- a defending unit of the bonus's role, the river penalty only to a melee attack across a river edge (the attacker's
-- tile and the target share one). Defence of a unit: see unitDefense (its `defense`); of an undefended city:
-- (cityBaseStrength 14 + population) x (100 + terrain%)/100. City buildings (Walls, Castle) add a flat amount on top in
-- both cases, so damage stays monotonic in the hidden building defence. `level` adds nothing itself (it was +3 strength
-- per level before promotions); the promotions it counts carry the bonuses.
local function strike(s: any, unit: any, defender: any, city: any, target: number, cityDefense: number, units: any): (number, number, boolean)
    local rule=R.units[unit.kind]
    local ranged=(rule.range or 1)>1
    local attack=if ranged then rule.rangedStrength else rule.attack
    local flanking=if ranged or not defender then 0 else flankingPercent(s,unit,target,units)
    local promoted=promotionPercent(s,unit,target,true,ranged,defender~=nil)
    local siege=if city then rule.siegePercent else 0
    local river=if not ranged and riverBetween(s,unit.tileId,target) then R.riverAttackPercent else 0
    local versus=if defender then versusPercent(unit,R.units[defender.kind].role) else 0
    attack=math.max(1,attack)*(0.5+unit.hp/200)*(100+flanking+promoted+siege+versus-river)/100
    local terrain=defensePercentAt(s,target)
    local defense: number
    if defender then
        defense=unitDefense(s,defender,target,ranged,rule.role)
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
    -- Experience from a strike between a civilization and the barbarians stops at the barbarian cap.
    if not defender or R.units[defender.kind].strength>0 then
        local versusBarbarian=unit.ownerId==BARBARIAN or enemyOwner==BARBARIAN
        gainExperience(unit,if ranged then R.experience.rangedAttack else R.experience.meleeAttack,versusBarbarian)
        if defender then gainExperience(defender,if ranged then R.experience.rangedDefense else R.experience.meleeDefense,versusBarbarian) end
    end
    event(s,"Attack","Battle dealt "..dealt.." damage.",target,unit.id,unit.ownerId,dealt)
    if defender and defender.hp<=0 then removeUnit(s,defender.id); unitLost(s,defender,target,if ranged then "Ranged" else "Combat",unit.ownerId,dealt) end
    if unit.hp<=0 then removeUnit(s,unit.id); unitLost(s,unit,unit.tileId,"Combat",enemyOwner,received); return end
    if not ranged and not select(1,occupants(s))[target] then
        if city and city.ownerId~=unit.ownerId then
            -- Barbarians damage cities but never capture them.
            if city.hp==0 and unit.ownerId~=BARBARIAN then
                local loser=city.ownerId
                -- A city captured this round cannot strike until the next round (its strike counts as used).
                city.ownerId=unit.ownerId; city.hp=50; city.population=math.max(1,city.population-1); city.production=0; city.queue=""; city.food=0; city.strikeTurn=s.turn
                local ids={target}; for _, id in mapFor(s).neighbors[target] do table.insert(ids,id) end
                for _, id in ids do s.tiles[id].ownerId=unit.ownerId end
                unit.tileId=target; event(s,"Capture","City captured.",target,unit.id,unit.ownerId)
                event(s,"CityLost",city.name.." was captured.",target,nil,loser,nil,nil,"Captured",unit.ownerId)
            end
        -- A melee attacker that kills a unit outside a city advances only into land its owner may enter: a barbarian
        -- killed on the territory of a civilization at peace with the attacker dies, and the attacker stays put.
        elseif territoryOpen(s,unit,target) then unit.tileId=target; enterCamp(s,unit) end
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
    -- A melee kill of a unit outside a city advances onto its tile when the attacker's owner may enter that land; a kill
    -- of a camp's guard that advances destroys the camp. A unit outside a city gives an exact strike, so both bounds agree.
    -- The territory owner is visible (the target tile is), so this reads nothing hidden.
    local advances=not ranged and city==nil and defender~=nil and defenderLow and defenderHigh and not attackerLow and not attackerHigh and territoryOpen(s,unit,target)
    local clearsCamp=advances and unit.ownerId~=BARBARIAN and campTiles(s)[target]~=nil
    return {unitId=unit.id,tileId=target,target=if defender then "Unit" else "City",ranged=ranged,exact=exact,hiddenDefense=high>0,acrossRiver=not ranged and riverBetween(s,unit.tileId,target),advances=advances,clearsCamp=clearsCamp,
        dealt=if exact then dealtMin else nil,received=if exact then receivedMin else nil,
        dealtMin=dealtMin,dealtMax=dealtMax,receivedMin=receivedMin,receivedMax=receivedMax,
        attackerHp=unit.hp,defenderHp=if defender then defender.hp else city.hp,
        attackerDefeated=outcome(attackerLow,attackerHigh),defenderDefeated=if defender then outcome(defenderLow,defenderHigh) else "No",
        captures=outcome(captureLow,captureHigh)}
end
-- A civilization's era (G7): the highest era among the technologies it knows (1-6; 1 with none), the coarse value
-- `progress` makes public. It was 1 + floor(technologies / 4) before G7.
local function eraOf(technologies: {string}): number
    local result=1; for _, id in technologies do result=math.max(result,R.technologies[id].era) end; return result
end
local function era(s: any, owner: number): number return eraOf(s.players[owner].technologies) end
-- A military unit (strength above zero) of the city's owner standing in the city adds garrisonPercent of its defence.
local function garrisonStrength(city: any, units: any): number
    local garrison=units[city.tileId]
    if not garrison or garrison.ownerId~=city.ownerId or R.units[garrison.kind].strength<=0 then return 0 end
    return math.floor(R.units[garrison.kind].defense*R.garrisonPercent/100)
end
-- City combat strength: cityBaseStrength + population + cityStrengthPerEra x (era - 1) + building defence (Walls,
-- Castle) + garrison. Its ranged strike uses cityStrikePercent of it, rounded down. Both are whole numbers.
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
    return hostile(s,city.ownerId,target.ownerId) and seen[target.tileId]==true and cities[target.tileId]==nil
        and W.inRange(mapFor(s),city.tileId,target.tileId,R.cityStrikeRange)
end
local function cityStrikeTargets(s: any, city: any, seen: any, units: any, cities: any): {number}
    local ids={}
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
    return math.clamp(math.floor(30*attack/math.max(1,unitDefense(s,target,target.tileId,true,nil))+0.5),8,65)
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
    -- Catch contact after each AI move, even if another AI unit later moves out of sight in this turn.
    if not s.diplomacy.met then for owner=1,2 do contact(s,owner,visible(s,owner)) end end
    event(s,"Move","Unit moved.",target,unit.id,unit.ownerId); enterCamp(s,unit); return true
end
local function improvementAvailable(s: any, unit: any, improvement: string): boolean
    local rule=R.improvements[improvement]; if not rule or unit.kind~="Worker" or unit.moves<=0 or unit.work then return false end
    local tile=s.tiles[unit.tileId]; if tile.ownerId~=unit.ownerId then return false end
    if rule.technology and not has(s.players[unit.ownerId].technologies,rule.technology) then return false end
    if rule.road then return not tile.road end
    if tile.improvement==improvement or not has(rule.terrains,tile.terrain) then return false end
    -- Features cannot be removed, so only the improvements a feature lists may be built on it.
    if tile.feature and not has(R.features[tile.feature].improvements,improvement) then return false end
    if #rule.resources>0 and tile.resource and not has(rule.resources,tile.resource) then return false end
    if (improvement=="Pasture" or improvement=="Plantation" or improvement=="Camp" or improvement=="Well") and not tile.resource then return false end
    return true
end
-- A tile's yields: its terrain's, replaced by (or, for Marsh, added to) its feature's, then its resource and improvement;
-- a river adds riverGold and gives a Farm riverFarmFood more (fresh water). No yield drops below zero.
local yieldKeys={"food","production","gold","science","culture"}
local function yieldFor(tile: any): any
    local feature=if tile.feature then R.features[tile.feature] else nil
    local result=copy(if feature and feature.overrideYields then feature.yields else R.terrains[tile.terrain].yields)
    for _, key in yieldKeys do result[key]=result[key] or 0 end
    if feature and not feature.overrideYields then for key,value in feature.yields do result[key] += value end end
    if tile.resource then for key,value in R.resources[tile.resource].yields do result[key] += value end end
    if tile.improvement then for key,value in R.improvements[tile.improvement].yields do result[key] += value end end
    if tile.river then
        result.gold += R.riverGold
        if tile.improvement=="Farm" then result.food += R.riverFarmFood end
    end
    for _, key in yieldKeys do result[key]=math.max(0,result[key]) end
    return result
end
local function nextTileCost(s: any, c: any): number
    return scaledCost(s,math.floor(R.borderCultureBase+(R.borderCultureMultiplier*(c.borderTiles or 0))^R.borderCultureExponent),"policy")
end
local function buyTileCost(s: any, c: any, tileId: number): number
    local d=distance(s,c.tileId,tileId)
    local factor=if d==3 then 1.5 elseif d==2 then 1 else 0.75
    return scaledCost(s,math.floor((R.borderBuyBase+R.borderBuyPerTile*(c.borderTiles or 0))*factor),"production")
end
-- Strategic reveal for border decisions. The existing tile/economy projection predates reveal rules; keep this
-- local to borders. Hidden resources contribute neither natural resource yields nor a resource bonus.
local BORDER_REVEAL={Horses="AnimalHusbandry",Iron="BronzeWorking",Saltpeter="Gunpowder",Oil="Combustion"}
local function borderResource(s: any, owner: number, tile: any, seen: any): any
    if not tile.resource or not seen[tile.id] then return nil end
    local tech=BORDER_REVEAL[tile.resource]
    if tech and not has(s.players[owner].technologies,tech) then return nil end
    return R.resources[tile.resource]
end
local function borderScore(s: any, c: any, tileId: number, seen: any): number
    local tile=s.tiles[tileId]; local resource=borderResource(s,c.ownerId,tile,seen)
    local y=yieldFor({terrain=tile.terrain,feature=tile.feature,river=tile.river,resource=if resource then tile.resource else nil})
    local extra=if not resource then 0 elseif resource.category=="Luxury" then 6 elseif resource.category=="Strategic" then 4 else 2
    return 2*y.food+2*y.production+y.gold+y.science+y.culture+extra-3*(distance(s,c.tileId,tileId)-1)
end
-- Shared physical legality for growth, purchase and projection. Water and mountains are legal. `claimed` is the
-- forecast's virtual culture acquisitions, applied after the yielding city's production, never a population claim.
local function borderCandidates(s: any, c: any, claimed: {[number]: boolean}?): {number}
    local units,cities=occupants(s); local camps=campTiles(s); local result={}
    for _, id in nearby(s,c.tileId,3) do
        local tile=s.tiles[id]
        if tile.ownerId or (claimed and claimed[id]) or (units[id] and units[id].ownerId~=c.ownerId)
            or (cities[id] and cities[id].ownerId~=c.ownerId) or camps[id] then continue end
        for _, neighbor in mapFor(s).neighbors[id] do
            if s.tiles[neighbor].ownerId==c.ownerId or (claimed and claimed[neighbor]) then table.insert(result,id); break end
        end
    end
    table.sort(result); return result
end
local function bestBorderTile(s: any, c: any, candidates: {number}, seen: any): number?
    local best: number?=nil; local score=-math.huge
    for _, id in candidates do
        local value=borderScore(s,c,id,seen)
        if value>score or (value==score and (not best or id<best)) then best=id; score=value end
    end
    return best
end
local function acquireBorderTile(s: any, c: any, tileId: number, gold: number?)
    s.tiles[tileId].ownerId=c.ownerId; c.borderTiles=(c.borderTiles or 0)+1
    event(s,"BorderGrowth",c.name.."'s borders expanded.",tileId,nil,c.ownerId,gold,nil,nil,nil,nil,c.id)
end
local function borderStep(s: any, c: any, culture: number)
    local cost=nextTileCost(s,c)
    c.borderCulture=math.min(1000000000,(c.borderCulture or 0)+math.max(0,culture)+R.borderBaseRate)
    local candidates=borderCandidates(s,c)
    if #candidates==0 then c.borderCulture=math.min(c.borderCulture,cost)
    elseif c.borderCulture>=cost then
        local tileId=bestBorderTile(s,c,candidates,visible(s,c.ownerId)) :: number
        c.borderCulture-=cost; acquireBorderTile(s,c,tileId)
    end
end
-- One city's yields this turn: the free center, each citizen on the best distinct nearby owned tile for its
-- focus (marking `worked`), buildings, policies and the Science/Culture production conversion. Pure apart
-- from `worked`; returns the yields and the buildings' maintenance. Shared by the economy and the forecast.
-- `claimed` marks tiles the forecast treats as already owned by `owner` (its virtual claims). `bonus` is the owner's
-- empireBonus at the start of the step plus `golden` (a golden age is active): the owner's wonders add their global
-- yields and science percentage, and a golden age adds tileGold to the centre and to every worked tile yielding gold.
local function cityYields(s: any, p: any, owner: number, c: any, worked: any, cityTiles: any, bonus: any, claimed: {[number]: boolean}?): (any, number)
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
    local tileGold=if bonus.golden then R.goldenAge.tileGold else 0
    if yields.gold>=1 then yields.gold += tileGold end
    for index=1,math.min(c.population,#candidates) do
        local row=candidates[index]; worked[row.id]=true; for key,value in row.yields do yields[key] += value end
        if row.yields.gold>=1 then yields.gold += tileGold end
    end
    local maintenance=0
    for _, building in c.buildings do local b=R.buildings[building]; maintenance += b.maintenance; for key,value in b.yields do yields[key] += value end end
    for _, policy in p.policies do for key,value in R.policies[policy].yields do yields[key] += value end end
    for key,value in bonus.yields do yields[key] += value end
    if c.focus=="Science" or c.focus=="Culture" then
        local converted=math.floor(yields.production/2); yields.production -= converted; yields[string.lower(c.focus)] += converted
    end
    if bonus.sciencePercent>0 then yields.science=math.floor(yields.science*(100+bonus.sciencePercent)/100) end
    return yields, maintenance
end
-- Net food and production a city adds per turn after golden-age, happiness (and AI difficulty) adjustments.
local function cityNet(s: any, p: any, c: any, yields: any, happiness: number, bonus: any): (number, number)
    local food=yields.food-c.population*R.foodPerPopulation
    if happiness<0 and food>0 then food=math.floor(food/2) end
    local production=yields.production
    if bonus.golden then production=math.floor(production*(100+R.goldenAge.productionPercent)/100) end
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
-- The end of an owner's economy step for its golden age. `golden` is whether an age was active at the start of the step
-- (its effects applied to the whole step) and `granted` the steps a wonder completed during the step grants.
-- An active age counts down one step; outside one the step's positive happiness fills the meter. A granted age starts
-- (or extends one still running, with no new event). When the meter reaches the threshold outside an age it is spent
-- and a new age begins. A new age takes effect from the next step, and every age begun raises the next threshold.
local function goldenStep(s: any, p: any, owner: number, golden: boolean, happiness: number, granted: number, grantedBy: string?)
    local g: any=if p.goldenAge then p.goldenAge else {progress=0,turnsLeft=0,ages=0}
    if golden then g.turnsLeft -= 1 elseif happiness>0 then g.progress += happiness end
    if granted>0 then
        if golden or g.turnsLeft>0 then g.turnsLeft += granted
        else
            g.turnsLeft=granted; g.ages += 1
            event(s,"GoldenAgeStarted","A golden age begins for "..granted.." turns.",nil,nil,owner,granted,nil,"Wonder",nil,nil,nil,grantedBy)
        end
    end
    if golden and g.turnsLeft==0 then event(s,"GoldenAgeEnded","The golden age has ended.",nil,nil,owner) end
    local threshold=goldenAgeThreshold(s,g.ages)
    if not golden and g.turnsLeft==0 and g.progress>=threshold then
        g.progress -= threshold; g.ages += 1; g.turnsLeft=goldenAgeTurns(s)
        event(s,"GoldenAgeStarted","A golden age begins for "..g.turnsLeft.." turns.",nil,nil,owner,g.turnsLeft,nil,"Happiness")
    end
    -- The record is stored once anything is non-zero, so a civilization that never fills its meter writes no field.
    if p.goldenAge or g.progress>0 or g.turnsLeft>0 or g.ages>0 then p.goldenAge=g end
end
local aiProduction: (any, number, boolean?) -> ()
local function economy(s: any, owner: number)
    local p=s.players[owner]; p.resources=resourceInventory(s,owner)
    local happiness,discount=stepHappiness(s,owner,p.resources); p.happiness=happiness
    local income: {[string]: number}={food=0,production=0,gold=0,science=0,culture=0,maintenance=0}
    local worked={}; local _,cityTiles=occupants(s)
    local cityOrder: {any}={}; for _, city in s.cities do table.insert(cityOrder,city) end
    table.sort(cityOrder,function(a: any,b: any) return a.id<b.id end)
    -- Wonder effects and the golden age are fixed at the start of the step, like its happiness.
    local bonus=empireBonus(s,owner); local golden=goldenActive(p); bonus.golden=golden
    local converted: {[number]: boolean}={}; local granted,grantedBy=0,nil
    for _, c in cityOrder do
        if c.ownerId~=owner then continue end
        -- The city center is free; each citizen works one distinct nearby owned tile.
        local yields,maintenance=cityYields(s,p,owner,c,worked,cityTiles,bonus); income.maintenance += maintenance
        local food,production=cityNet(s,p,c,yields,p.happiness,bonus)
        c.food += food
        local threshold=growthCost(s,c.population)
        if c.food>=threshold and p.happiness>=0 and c.population<R.maxPopulation then c.food -= threshold; c.population += 1; event(s,"Growth","City grew.",c.tileId,nil,owner,c.population)
        elseif c.food<0 then
            if c.population>1 then c.population -= 1; event(s,"Starvation","City lost population.",c.tileId,nil,owner,c.population) end
            c.food=0
        end
        -- Idle turns lose their production yield; stored overflow remains available for the next choice.
        if c.queue~="" then c.production += production end
        c.hp=math.min(R.cityHp,c.hp+5)
        for key,value in yields do income[key] += value end
        -- A city that lost a wonder race earlier in this step completes nothing until its next step.
        if c.queue~="" and not converted[c.id] and productionAvailable(s,c,c.queue) and c.production>=productionCost(s,c.queue) then
            local spawn=spawnTile(s,c)
            if R.buildings[c.queue] or spawn then
                local item=c.queue; c.production -= productionCost(s,item); complete(s,c,item,spawn,converted,bonus)
                if R.buildings[item] and R.buildings[item].startsGoldenAge then granted += goldenAgeTurns(s); grantedBy=item end
            end
        end
        borderStep(s,c,yields.culture)
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
    goldenStep(s,p,owner,golden,happiness,granted,grantedBy)
    p.resources=resourceInventory(s,owner)
    -- AI completions can empty a queue after its choices for this turn. Fill only those queues before the turn ends.
    if not p.human then aiProduction(s,owner,true) end
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
-- Barbarians. A deterministic 32-bit hash (FNV-1a over 32-bit pieces of each value, then a final mix) of the seed, the
-- round and a salt decides where camps appear, which unit kinds they add and where idle barbarians wander, so every
-- barbarian choice follows from the seed and the state alone (no random generator state is kept or saved).
local TWO32=4294967296
local function mul32(a: number, b: number): number
    return (a*(b%65536)+((a*(b//65536))%65536)*65536)%TWO32
end
local function hash(a: number, b: number, c: number): number
    local h=2166136261
    for _, value in {a,b,c} do
        local folded=value%9007199254740992
        h=mul32(bit32.bxor(h,folded%TWO32),16777619); h=mul32(bit32.bxor(h,folded//TWO32),16777619)
    end
    h=bit32.bxor(h,bit32.rshift(h,16)); h=mul32(h,73244475); return bit32.bxor(h,bit32.rshift(h,16))
end
-- Barbarians are not a player, so fog does not limit them: every tile counts as seen for their movement and targets.
local everywhere: any=setmetatable({},{__index=function() return true end})
-- The camp cap for the map size: one camp per tilesPerCamp tiles, from 1 to maxCamps.
local function campCap(s: any): number
    local b=R.barbarians; return math.max(1,math.min(b.maxCamps,math.floor(#s.tiles/b.tilesPerCamp)))
end
local function barbarianCount(s: any): number
    local n=0; for _, u in s.units do if u.ownerId==BARBARIAN then n += 1 end end; return n
end
-- The kinds barbarians field: the list for the lower of the two civilizations' eras (the public era).
local function barbarianKinds(s: any): {string}
    local lists=R.barbarians.eraUnits; return lists[math.clamp(math.min(era(s,1),era(s,2)),1,#lists)]
end
-- Graph distances from `center` up to `limit` hexes (equal to hex distance on a hex board).
local function distancesWithin(s: any, center: number, limit: number): {[number]: number}
    local neighbors=mapFor(s).neighbors; local result: {[number]: number}={[center]=0}; local queue={center}; local head=1
    while head<=#queue do
        local current=queue[head]; head += 1
        local d=result[current]
        if d>=limit then continue end
        for _, other in neighbors[current] do if result[other]==nil then result[other]=d+1; table.insert(queue,other) end end
    end
    return result
end
-- A camp adds a unit: on its own tile when that is free (the new unit becomes its guard and is the first kind of the
-- era), otherwise on its free passable neighbour with the lowest id that holds no city or other camp. A unit is added
-- only while the world holds fewer units than the global cap and the barbarians fewer than their own cap. Returns
-- whether a unit was added.
local function campSpawn(s: any, camp: any): boolean
    if #s.units>=R.maxUnits or barbarianCount(s)>=R.barbarians.maxUnits then return false end
    local units,cities=occupants(s); local camps=campTiles(s); local kinds=barbarianKinds(s)
    if not units[camp.tileId] then addUnit(s,BARBARIAN,kinds[1],camp.tileId); return true end
    for _, id in mapFor(s).neighbors[camp.tileId] do
        if not units[id] and not cities[id] and not camps[id] and R.terrains[s.tiles[id].terrain].passable then
            addUnit(s,BARBARIAN,kinds[hash(s.seed,s.turn,camp.id)%#kinds+1],id); return true
        end
    end
    return false
end
-- A new camp, when one is due (round firstCampTurn, then every campInterval rounds, both pace- and difficulty-scaled)
-- and the map has room under its cap: passable land no civilization can see now, with no unit or city, at least
-- campCityDistance from every city and campSpacing from every camp. Tiles neither civilization has explored are
-- preferred; the hash picks one of the candidates in tile id order. The camp starts with its guard.
local function newCamp(s: any)
    local b=s.barbarians; local rules=R.barbarians
    if #b.camps>=campCap(s) then return end
    local first=barbarianRounds(s,rules.firstCampTurn)
    if s.turn<first or (s.turn-first)%barbarianRounds(s,rules.campInterval)~=0 then return end
    local blocked: {[number]: boolean}={}
    for _, c in s.cities do for _, id in nearby(s,c.tileId,rules.campCityDistance-1) do blocked[id]=true end end
    for _, camp in b.camps do for _, id in nearby(s,camp.tileId,rules.campSpacing-1) do blocked[id]=true end end
    for _, u in s.units do blocked[u.tileId]=true end
    local seen1,seen2=visible(s,1),visible(s,2)
    local known: {[number]: boolean}={}; for owner=1,2 do for _, id in s.players[owner].explored do known[id]=true end end
    local unexplored,unseen={},{}
    for _, tile in s.tiles do
        if blocked[tile.id] or seen1[tile.id] or seen2[tile.id] or not R.terrains[tile.terrain].passable then continue end
        if known[tile.id] then table.insert(unseen,tile.id) else table.insert(unexplored,tile.id) end
    end
    local list=if #unexplored>0 then unexplored else unseen
    if #list==0 then return end
    local camp={id=b.nextCamp,tileId=list[hash(s.seed,s.turn,b.nextCamp)%#list+1],founded=s.turn,lastSpawn=s.turn}
    b.nextCamp += 1; table.insert(b.camps,camp)
    campSpawn(s,camp)
end
-- The barbarian's best favourable attack from its tile, or nil: one it survives that kills the defender or deals at
-- least the damage it takes. A kill ranks first, then the damage difference; ties go to the lowest tile id. A city at
-- 0 hit points is never a target (barbarians cannot capture it). The strike is the combat function itself.
local function barbarianAttack(s: any, u: any): number?
    local units,cities=occupants(s); local best: number?=nil; local bestRank=-math.huge
    for _, tileId in attackTargets(s,u,everywhere,units,cities) do
        local defender,city=units[tileId],cities[tileId]
        if city and not defender and city.hp<=0 then continue end
        local dealt,received=strike(s,u,defender,city,tileId,if city then buildingDefense(city) else 0,units)
        if received>=u.hp then continue end
        local kills=defender~=nil and dealt>=defender.hp
        if not kills and dealt<received then continue end
        local rank=(if kills then 1000 else 0)+dealt-received
        if rank>bestRank then best=tileId; bestRank=rank end
    end
    return best
end
-- The nearest civilization unit or city within huntRadius hexes of the barbarian (ties: the lowest tile id).
local function barbarianGoal(s: any, u: any): number?
    local units,cities=occupants(s); local best: number?=nil; local bestDistance=math.huge
    local within=distancesWithin(s,u.tileId,R.barbarians.huntRadius)
    for _, tileId in nearby(s,u.tileId,R.barbarians.huntRadius) do
        local other=units[tileId] or cities[tileId]
        if other and other.ownerId~=BARBARIAN and within[tileId]<bestDistance then best=tileId; bestDistance=within[tileId] end
    end
    return best
end
-- The nearest camp (the lowest id among the nearest) and its distance, by a breadth-first search from the tile that
-- stops at the first layer holding a camp.
local function nearestCamp(s: any, tileId: number): (any, number)
    local camps=campTiles(s)
    if next(camps)==nil then return nil,0 end
    local neighbors=mapFor(s).neighbors; local reached: {[number]: boolean}={[tileId]=true}; local layer={tileId}; local d=0
    while #layer>0 do
        local best: any=nil
        for _, id in layer do local camp=camps[id]; if camp and (best==nil or camp.id<best.id) then best=camp end end
        if best then return best,d end
        local following={}
        for _, id in layer do for _, other in neighbors[id] do if not reached[other] then reached[other]=true; table.insert(following,other) end end end
        layer=following; d += 1
    end
    return nil,0
end
-- One barbarian unit's action. A guard (a unit on a camp tile) holds the camp: it never moves and attacks only from
-- range. Another unit attacks at once when it has a favourable attack. Otherwise it moves: toward the nearest
-- civilization unit or city within huntRadius (to the reachable tile closest to it, only if that is closer than where it
-- stands), or, with no target, back toward its nearest camp when it is beyond leashRadius, or else to a reachable tile
-- within leashRadius chosen by the hash. After moving it attacks if a favourable attack is open and it is not on a camp.
-- Each unit searches once and attacks at most once, so the phase always ends.
local function barbarianAct(s: any, u: any)
    local rules=R.barbarians; local camps=campTiles(s); local ranged=(R.units[u.kind].range or 1)>1
    local target=barbarianAttack(s,u)
    if camps[u.tileId] then if target and ranged then combat(s,u,target) end; return end
    if target then combat(s,u,target); return end
    local units,cities=occupants(s)
    local spent=movementSearch(s,u,everywhere,units,cities)
    local ids={}; for tileId in spent do if tileId~=u.tileId then table.insert(ids,tileId) end end
    if #ids==0 then return end
    table.sort(ids)
    local best: number?=nil
    local goal=barbarianGoal(s,u)
    if goal then
        local toGoal=distancesWithin(s,goal,rules.huntRadius+3*R.units[u.kind].moves+1); local bestDistance=toGoal[u.tileId] or math.huge
        for _, tileId in ids do local d=toGoal[tileId]; if d and d<bestDistance then best=tileId; bestDistance=d end end
    else
        local home,homeDistance=nearestCamp(s,u.tileId)
        -- Distances from the camp cover every reachable tile that could matter: a move spans at most three steps per
        -- move (road steps cost a third), and a tile beyond the limit is neither closer nor within the leash.
        local fromHome: {[number]: number}={}
        if home then fromHome=distancesWithin(s,home.tileId,math.max(homeDistance,rules.leashRadius)+3*R.units[u.kind].moves+1) end
        if home and homeDistance>rules.leashRadius then
            local bestDistance=homeDistance
            for _, tileId in ids do local d=fromHome[tileId]; if d and d<bestDistance then best=tileId; bestDistance=d end end
        else
            local allowed={}
            for _, tileId in ids do if not home or (fromHome[tileId] or math.huge)<=rules.leashRadius then table.insert(allowed,tileId) end end
            if #allowed>0 then best=allowed[hash(s.seed,s.turn,u.id)%#allowed+1] end
        end
    end
    if not best then return end
    u.tileId=best; u.moves=fromSixths(toSixths(u.moves)-spent[best]); u.fortified=false
    if u.moves>0 and (ranged or not camps[best]) then
        local after=barbarianAttack(s,u)
        if after then combat(s,u,after) end
    end
end
-- The barbarian phase, once per round after both civilizations have acted. Barbarian units that rested heal and every
-- unit's movement refreshes; the units act in id order; each camp due a unit (every spawnInterval rounds) adds one
-- while there are fewer than unitsPerCamp barbarian units per camp; then a new camp may appear. Barbarian moves emit
-- no events (only their attacks and losses do), so the phase cannot flood the event ring.
local function barbarianTurn(s: any)
    local b=s.barbarians
    if not b then return end
    local rules=R.barbarians; local ids={}
    for _, u in s.units do
        if u.ownerId~=BARBARIAN then continue end
        if rested(u) then u.hp=math.min(R.units[u.kind].hp,u.hp+rules.healing) end
        u.moves=R.units[u.kind].moves; table.insert(ids,u.id)
    end
    table.sort(ids)
    for _, id in ids do local u=unitById(s,id); if u then barbarianAct(s,u) end end
    local interval=barbarianRounds(s,rules.spawnInterval)
    for _, camp in b.camps do
        if s.turn-camp.lastSpawn>=interval and barbarianCount(s)<rules.unitsPerCamp*#b.camps and campSpawn(s,camp) then camp.lastSpawn=s.turn end
    end
    newCamp(s)
end
local function foundAllowed(s: any, unit: any): boolean
    if #s.cities>=R.maxCities or unit.kind~="Settler" or unit.moves<=0 or not R.terrains[s.tiles[unit.tileId].terrain].passable then return false end
    local t=s.tiles[unit.tileId]; if t.ownerId and t.ownerId~=unit.ownerId then return false end
    for _, c in s.cities do if W.inRange(mapFor(s),c.tileId,unit.tileId,2) then return false end end
    return true
end
-- The AI races for at most one world wonder at a time, in one city. It keeps a wonder it is already building while that
-- wonder is still available. Otherwise it picks its city with the most net production (lowest id on ties) and the first
-- wonder in rule order (earliest first) that city may choose and can finish within AI_WONDER_TURNS at its current rate,
-- so a slow city never sinks its production into a wonder it cannot finish. The wonder goes after that city's core
-- buildings and settler and before military units. A lost race switches the queue, and the next AI turn plans again.
local AI_WONDER_TURNS=30
local function aiWonderPlan(s: any, owner: number): (number?, string?)
    local p=s.players[owner]
    local own: {any}={}; for _, c in s.cities do if c.ownerId==owner then table.insert(own,c) end end
    table.sort(own,function(a: any,b: any) return a.id<b.id end)
    for _, c in own do if c.queue~="" and isWonder(c.queue) and productionAvailable(s,c,c.queue) then return c.id,c.queue end end
    local bonus=empireBonus(s,owner); bonus.golden=goldenActive(p); local _,cityTiles=occupants(s)
    local mood=stepHappiness(s,owner,resourceInventory(s,owner))
    local best: any=nil; local bestMade=0
    for _, c in own do
        local yields=cityYields(s,p,owner,c,{},cityTiles,bonus); local _,made=cityNet(s,p,c,yields,mood,bonus)
        if made>bestMade then best=c; bestMade=made end
    end
    if not best then return nil,nil end
    for _, id in R.wonderOrder do
        if canChoose(s,best,id) and math.ceil(math.max(0,productionCost(s,id)-best.production)/bestMade)<=AI_WONDER_TURNS then return best.id,id end
    end
    return nil,nil
end
-- AI production (G7). The AI's ordinary buildings for growth, production, gold and science, in the order it builds them
-- once their technologies are known. Every id is a building in the rules (the list before G7 named a "Colosseum" that did
-- not exist, so that entry never applied). Happiness buildings come first, but only while the AI's happiness is below
-- AI_CONTENT, so it builds a Colosseum when its cities need contentment and never when they do not. They are the ordinary
-- buildings with happiness and no culture yield (Colosseum, Shrine, Stadium), ranked by happiness per production cost;
-- the Temple and Theatre are left out so that contentment does not hurry the AI's culture victory (the AI never built a
-- Temple before G7 either). Defence buildings (Walls, Castle) come first in a threatened city: one with a visible hostile
-- military unit within AI_THREAT_RADIUS hexes. A city's full order: the science-victory building (once its technology
-- is known), a worker (when the AI has none), defence buildings (threatened), a military unit (at war with fewer military
-- units than cities plus one), its wonder (when already racing for it), happiness buildings (when needed), the economy
-- list with a settler after the Monument (fewer than three cities, no settler yet), its planned wonder, then the upkeep
-- fallback: a military unit while the AI can pay for one, otherwise a worker (while it has fewer than two workers per
-- city, as workers cost no upkeep), then a military unit after all. An idle city then tries every legal building and
-- unit before keeping a blocked Warrior when nothing is currently available.
local AI_ECONOMY={"Monument","Granary","Library","Market","Forge","Workshop","Aqueduct","University","Bank","Observatory","StockExchange","Factory","Hospital","PowerPlant","ResearchLab"}
local AI_CONTENT=1
local AI_THREAT_RADIUS=3
-- Upkeep budget: the last economy step's net gold less the upkeep of what the AI's other cities are already producing
-- (their queues will add it when they complete). A building with upkeep is affordable when its own gold covers its
-- upkeep (Market, Bank, Stock Exchange), when the budget covers it, or when the treasury holds AI_GOLD_RESERVE and the
-- budget is not negative; a further military unit (1 upkeep) needs the same, unless the AI is below its wartime
-- minimum. So the AI's cities do not all commit the same spare gold, and new upkeep does not push it into insolvency
-- (which retires units).
local AI_GOLD_RESERVE=60
-- The AI upgrades a unit standing in its own territory when its gold stays at AI_UPGRADE_RESERVE or more afterwards.
local AI_UPGRADE_RESERVE=40
-- Exhausted priorities do not imply exhausted legal choices. Prefer the cheapest remaining building (including
-- wonders), ties by id, then any available unit in rule order before retaining a blocked Warrior queue.
local aiFallbackItems: {string}=table.clone(R.buildingOrder)
local aiHappinessBuildings: {string}, aiDefenseBuildings: {string}={},{}
for _, id in R.buildingOrder do
    local rule=R.buildings[id]
    if rule.wonder then continue end
    if rule.happiness>0 and rule.yields.culture<=0 then table.insert(aiHappinessBuildings,id) end
    if rule.defense>0 then table.insert(aiDefenseBuildings,id) end
end
-- A unit's value for the AI's choice: a ranged unit's ranged strength plus half its defence, otherwise attack plus
-- defence.
local function aiUnitValue(rule: any): number
    if rule.range>1 then return rule.rangedStrength+rule.defense/2 end
    return rule.attack+rule.defense
end
-- A unit's group for the AI's army mix: Siege, Archery (ranged), Mobile (mounted and armour) or Line (the rest).
local function aiUnitGroup(rule: any): string
    if rule.role=="Siege" or rule.role=="Archery" then return rule.role end
    if rule.role=="Mounted" or rule.role=="Armor" then return "Mobile" end
    return "Line"
end
-- The AI's military unit for a city: the best available unit of the group it lacks most (a siege unit when it is at war
-- with at least four military units and none of them is siege, a ranged unit while ranged units are fewer than a third
-- of its army, a mounted or armour unit while those are fewer than a quarter, otherwise a line unit), or the best of any
-- group when none of that group is available (a mounted unit needs Horses). Recon units are never chosen. Ties go to the
-- later unit in unitOrder.
local function aiMilitaryChoice(s: any, city: any, groups: {[string]: number}, military: number, stock: any): string?
    local wanted="Line"
    if s.diplomacy.status=="War" and military>=4 and (groups.Siege or 0)==0 then wanted="Siege"
    elseif (groups.Archery or 0)*3<military then wanted="Archery"
    elseif (groups.Mobile or 0)*4<military then wanted="Mobile" end
    local best: string?,bestValue,fallback: string?,fallbackValue=nil,-math.huge,nil,-math.huge
    for _, id in R.unitOrder do
        local rule=R.units[id]
        if rule.strength<=0 or rule.role=="Recon" or not canChoose(s,city,id,stock) then continue end
        local value=aiUnitValue(rule)
        if aiUnitGroup(rule)==wanted and value>=bestValue then best=id; bestValue=value end
        if value>=fallbackValue then fallback=id; fallbackValue=value end
    end
    return best or fallback
end
-- The AI's gold focus: while its net gold is negative, one more of its cities (the lowest id not yet on it) takes the
-- Gold focus each turn; once the net gold reaches AI_GOLD_RECOVERED, one city (the highest id on it) returns to Balanced.
local AI_GOLD_RECOVERED=8
local function aiGoldFocus(s: any, owner: number)
    local p=s.players[owner]
    local own: {any}={}; for _, c in s.cities do if c.ownerId==owner then table.insert(own,c) end end
    table.sort(own,function(a: any,b: any) return a.id<b.id end)
    if p.income.gold<0 then
        for _, c in own do if c.focus~="Gold" then c.focus="Gold"; return end end
    elseif p.income.gold>=AI_GOLD_RECOVERED then
        for i=#own,1,-1 do if own[i].focus=="Gold" then own[i].focus="Balanced"; return end end
    end
end
aiProduction = function(s: any, owner: number, idleOnly: boolean?)
    local p=s.players[owner]
    local aiFallbackItems=table.clone(aiFallbackItems)
    table.sort(aiFallbackItems,function(a: string,b: string): boolean
        local x,y=productionCost(s,a),productionCost(s,b)
        if x~=y then return x<y end
        return a<b
    end)
    for _, id in R.unitOrder do table.insert(aiFallbackItems,id) end
    local aiHappinessBuildings=table.clone(aiHappinessBuildings)
    table.sort(aiHappinessBuildings,function(a: string,b: string): boolean
        local x,y=R.buildings[a],R.buildings[b]
        local first,second=x.happiness*productionCost(s,b),y.happiness*productionCost(s,a)
        if first~=second then return first>second end
        return a<b
    end)
    if not idleOnly then aiGoldFocus(s,owner) end
    local wonderCityId,wonderId=aiWonderPlan(s,owner)
    local counts: {[string]: number}={}; local groups: {[string]: number}={}; local military=0
    for _, u in s.units do
        if u.ownerId~=owner then continue end
        local rule=R.units[u.kind]; counts[u.kind]=(counts[u.kind] or 0)+1
        if rule.strength>0 then military += 1; local group=aiUnitGroup(rule); groups[group]=(groups[group] or 0)+1 end
    end
    local ownCities=0; for _, city in s.cities do if city.ownerId==owner then ownCities += 1 end end
    local seen=visible(s,owner); local stock=strategicStock(s,owner)
    local threats: {number}={}
    for _, u in s.units do if seen[u.tileId] and R.units[u.kind].strength>0 and hostile(s,owner,u.ownerId) then table.insert(threats,u.tileId) end end
    local function upkeep(item: string): number
        local rule=R.units[item] or R.buildings[item]; return if rule then rule.maintenance else 0
    end
    local pending=0; for _, c in s.cities do if c.ownerId==owner then pending += upkeep(c.queue) end end
    local atWar=s.diplomacy.status=="War"
    for _, c in s.cities do
        if c.ownerId~=owner then continue end
        if idleOnly and c.queue~="" then continue end
        local budget=p.income.gold-(pending-upkeep(c.queue))
        local function affordable(id: string): boolean
            local rule=R.buildings[id]
            return rule.maintenance<=0 or rule.yields.gold>=rule.maintenance or budget>=rule.maintenance or (p.gold>=AI_GOLD_RESERVE and budget>=0)
        end
        local unitsAffordable=budget>=1 or (p.gold>=AI_GOLD_RESERVE and budget>=0) or (atWar and military<ownCities+1)
        local priorities: {string}={}
        if has(p.technologies,R.scienceVictoryTechnology) then table.insert(priorities,R.scienceVictoryBuilding) end
        if not counts.Worker then table.insert(priorities,"Worker") end
        local threatened=false
        for _, tileId in threats do if W.inRange(mapFor(s),c.tileId,tileId,AI_THREAT_RADIUS) then threatened=true; break end end
        if threatened then for _, id in aiDefenseBuildings do table.insert(priorities,id) end end
        -- At war with fewer military units than cities plus one, a unit comes before buildings.
        local unit=aiMilitaryChoice(s,c,groups,military,stock)
        if atWar and military<ownCities+1 and unit then table.insert(priorities,unit) end
        -- A city already racing for its planned wonder keeps racing ahead of new buildings.
        if wonderId and c.id==wonderCityId and c.queue==wonderId then table.insert(priorities,wonderId) end
        if p.happiness<AI_CONTENT then for _, id in aiHappinessBuildings do if affordable(id) then table.insert(priorities,id) end end end
        -- A settler (while the AI has fewer than three cities) follows the first economy building, the Monument.
        for index, id in AI_ECONOMY do
            if affordable(id) then table.insert(priorities,id) end
            if index==1 and ownCities<3 and not counts.Settler then table.insert(priorities,"Settler") end
        end
        if wonderId and c.id==wonderCityId then table.insert(priorities,wonderId) end
        if unit and unitsAffordable then table.insert(priorities,unit) end
        if (counts.Worker or 0)<2*ownCities then table.insert(priorities,"Worker") end
        if unit then table.insert(priorities,unit) end
        local previous=c.queue
        for _, item in priorities do if canChoose(s,c,item,stock) then c.queue=item; break end end
        if c.queue=="" then
            for _, item in aiFallbackItems do if canChoose(s,c,item,stock) then c.queue=item; break end end
        end
        -- At the global unit cap with every eligible building finished, no choice is available now. Keep a real
        -- repeatable unit queued (blocked until space returns), just as a non-idle AI city's existing queue is kept.
        if c.queue=="" then c.queue="Warrior" end
        pending += upkeep(c.queue)-upkeep(previous)
    end
end
-- The AI's upgrades, before its units act: each military unit in its own territory, in id order, whose upgrade
-- UpgradeUnit would accept while leaving at least AI_UPGRADE_RESERVE gold, and only while its net gold is not negative
-- (the upgrade ends that unit's movement).
local function aiUpgrades(s: any, owner: number)
    local p=s.players[owner]
    local ids={}; for _, u in s.units do if u.ownerId==owner and R.units[u.kind].strength>0 then table.insert(ids,u.id) end end
    table.sort(ids)
    for _, id in ids do
        local u=unitById(s,id)
        if s.tiles[u.tileId].ownerId~=owner or upgradeRefusal(s,u) then continue end
        if p.income.gold>=0 and p.gold-upgradeCost(s,u.kind,upgradeKind(s,u) :: string)>=AI_UPGRADE_RESERVE then upgrade(s,u) end
    end
end
-- One empire purchase after production, using the existing 60-gold reserve. Resource visibility and ranking are
-- shared with culture growth. City id only resolves the same tile offered by two cities, so neither seat is favoured.
local function aiBuyTile(s: any, owner: number)
    local seen=visible(s,owner); local p=s.players[owner]
    local bestCity: any=nil; local bestTile: number?=nil; local bestScore=-math.huge
    for _, c in s.cities do
        if c.ownerId~=owner then continue end
        for _, id in borderCandidates(s,c) do
            local resource=borderResource(s,owner,s.tiles[id],seen)
            if not resource or (resource.category~="Luxury" and resource.category~="Strategic") or p.gold<buyTileCost(s,c,id)+AI_GOLD_RESERVE then continue end
            local score=borderScore(s,c,id,seen)
            if score>bestScore or (score==bestScore and (not bestTile or id<bestTile or (id==bestTile and c.id<bestCity.id))) then
                bestCity=c; bestTile=id; bestScore=score
            end
        end
    end
    if bestTile then
        local cost=buyTileCost(s,bestCity,bestTile); p.gold-=cost; acquireBorderTile(s,bestCity,bestTile,cost)
    end
end
local function ai(s: any, owner: number)
    local p=s.players[owner]
    if not p.research then for _, id in R.technologyOrder do local tech=R.technologies[id]; if eligible(p,tech,p.technologies) then p.research={id=id,progress=0,cost=scaledCost(s,tech.cost)}; break end end end
    for _, id in R.policyOrder do local policy=R.policies[id]; local cost=policyCost(s,p,policy); if eligible(p,policy,p.policies) and p.culture>=cost then p.culture -= cost; table.insert(p.policies,id); event(s,"Policy","Policy adopted: "..id,nil,nil,owner); break end end
    if s.diplomacy.peaceOfferBy and s.diplomacy.peaceOfferBy~=owner then
        -- The balance of military units with the other civilization (barbarians are no party to the peace).
        local own,enemy=0,0; for _, u in s.units do if R.units[u.kind].strength>0 then if u.ownerId==owner then own += 1 elseif u.ownerId~=BARBARIAN then enemy += 1 end end end
        if own<=enemy or s.turn%4==0 then s.diplomacy.status="Peace"; s.diplomacy.warPlan=nil; s.diplomacy.peaceOfferBy=nil; s.diplomacy.peaceUntil=s.turn+8; event(s,"Peace","Peace agreed.",nil,nil,nil,nil,true) end
    end
    for i=#s.trades,1,-1 do
        local trade=s.trades[i]
        if trade.toId==owner and s.diplomacy.status=="Peace" and trade.giveGold>=trade.receiveGold and p.gold>=trade.receiveGold and s.players[trade.fromId].gold>=trade.giveGold then
            s.players[trade.fromId].gold += trade.receiveGold-trade.giveGold; p.gold += trade.giveGold-trade.receiveGold
            table.remove(s.trades,i); event(s,"Trade","Trade accepted.",nil,nil,nil,nil,true)
        end
    end
    local d=s.diplomacy; local plan=d.warPlan
    if plan and (d.status~="Peace" or not d.met or d.peaceUntil~=plan.peaceUntil or s.turn<d.peaceUntil) then
        d.warPlan=nil -- No cancellation event, and no replacement plan in this AI step.
    elseif plan then
        -- In AI-against-AI play only the planner executes its plan; the other seat neither replaces nor triggers it.
        if plan.by==owner and s.turn>=plan.at then
            d.status="War"; d.warPlan=nil; d.peaceOfferBy=nil; s.trades={}
            event(s,"War","War declared.",nil,nil,nil,nil,true)
        end
    elseif d.met and d.status=="Peace" and s.turn>=15 and s.turn>=d.peaceUntil and s.turn%5==0 then
        local lead=if s.difficulty=="Easy" then 3 elseif s.difficulty=="Hard" then 1 else 2
        d.warPlan={by=owner,at=s.turn+lead,peaceUntil=d.peaceUntil}
        event(s,"WarWarning","Rival forces are massing on your border. War may come within "..lead.." rounds.",nil,nil,3-owner)
    end
    -- Each ready city strikes first, in city id order, so the units that act next can finish weakened targets.
    local strikers: {any}={}; for _, c in s.cities do if c.ownerId==owner and strikeReady(s,c) then table.insert(strikers,c) end end
    table.sort(strikers,function(a: any,b: any) return a.id<b.id end)
    for _, c in strikers do aiCityStrike(s,c) end
    aiUpgrades(s,owner)
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
        -- The first legal target in tile order, except a barbarian whose return blow would kill the attacker.
        local attack: number?=nil
        for _, tileId in attackTargets(s,u,seen,occupiedUnits,occupiedCities) do
            local foe=occupiedUnits[tileId]
            if foe and foe.ownerId==BARBARIAN and select(2,strike(s,u,foe,nil,tileId,0,occupiedUnits))>=u.hp then continue end
            attack=tileId; break
        end
        if attack then combat(s,u,attack); continue end
        local targets=reachable(s,u); local best: number?=nil; local bestRank=-math.huge
        local discovered={}; for _, tileId in p.explored do discovered[tileId]=true end
        -- Barbarians: a healthy military unit heads for the camps it can see (entering one clears it) and toward the
        -- visible barbarian units within three hexes of its civilization's cities.
        local hunting=R.units[u.kind].strength>0 and u.hp>=60
        local camps: {number}={}; local raiders: {number}={}
        if hunting then
            for _, camp in (if s.barbarians then s.barbarians.camps else {}) do if seen[camp.tileId] then table.insert(camps,camp.tileId) end end
            for _, other in s.units do
                if other.ownerId~=BARBARIAN or not seen[other.tileId] then continue end
                for _, c in s.cities do if c.ownerId==owner and W.inRange(mapFor(s),c.tileId,other.tileId,3) then table.insert(raiders,other.tileId); break end end
            end
        end
        for tileId in targets do
            if tileId==u.tileId then continue end
            local rank=0
            for _, neighbor in mapFor(s).neighbors[tileId] do if not discovered[neighbor] then rank += 10 end end
            if s.diplomacy.status=="War" then for _, c in s.cities do if c.ownerId~=owner and seen[c.tileId] then rank += 30-distance(s,tileId,c.tileId)*5 end end end
            for _, campTile in camps do rank += if campTile==tileId then 100 else math.max(0,24-4*distance(s,tileId,campTile)) end
            for _, raider in raiders do rank += math.max(0,20-5*distance(s,tileId,raider)) end
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
    aiProduction(s,owner)
    aiBuyTile(s,owner)
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
    if s.turn>=s.maxTurns then
        local values=scores(s)
        if values[1]~=values[2] then finish(s,if values[1]>values[2] then 1 else 2,"Score")
        else
            local one,two=s.players[1],s.players[2]
            local knowledge1,knowledge2=#one.technologies+#one.policies,#two.technologies+#two.policies
            if knowledge1~=knowledge2 then finish(s,if knowledge1>knowledge2 then 1 else 2,"Score",true)
            else finish(s,nil,"Draw") end
        end
        return
    end
    -- Barbarians act once per round, after both civilizations. A civilization whose last settler they kill (before it
    -- founds a city) is eliminated by the evaluation as usual.
    if s.barbarians then
        barbarianTurn(s); refreshVision(s); evaluate(s)
        if s.phase=="Finished" then return end
    end
    s.turn += 1; beginTurn(s,1)
end
function BaseGame.new(seed: number?, options: Options?): State
    local o: Options=options or {}; local supplied=seed or 1; local radius=o.radius or 4; local humans=o.humanPlayers or 1; local difficulty=o.difficulty or "Normal"; local turns=o.maxTurns or 120
    local threshold=o.cultureVictoryPolicies or R.cultureVictoryPolicies or 6; local increase: any=o.policyCostIncrease
    assert(type(supplied)=="number" and supplied==supplied and math.abs(supplied)<=9007199254740991 and supplied%1==0,"seed must be a finite integer")
    assert(radius%1==0 and radius>=R.minRadius and radius<=R.maxRadius,"radius must be 3 to 40")
    assert(humans==1 or humans==2,"humanPlayers must be 1 or 2")
    assert(difficulty=="Easy" or difficulty=="Normal" or difficulty=="Hard","unknown difficulty")
    assert(turns%1==0 and turns>=20 and turns<=500,"maxTurns must be 20 to 500")
    -- G7 pacing: without an explicit value the policy cost growth follows the match pace (the golden-age pace, the round
    -- limit against 120 rounds, 50-200%) squared: max(minimumPolicyCostIncrease 50, policyCostIncrease 140 x pace%^2),
    -- rounded and at most 400. So 60 rounds or fewer keep the earlier flat 50 (Quick, 45 rounds), Standard (80 rounds,
    -- pace 67%) gets 63, Full (120 rounds) 140, 150 rounds 219 and 200 rounds or more 400.
    if increase==nil then
        local g=R.goldenAge; local pace=math.clamp(math.floor(turns*100/g.paceTurns+0.5),g.minPacePercent,g.maxPacePercent)
        increase=math.clamp(math.floor(R.policyCostIncrease*pace*pace/10000+0.5),R.minimumPolicyCostIncrease,400)
    end
    assert(type(threshold)=="number" and threshold%1==0 and threshold>=1 and threshold<=#R.policyOrder,"cultureVictoryPolicies must be 1 to "..#R.policyOrder)
    assert(type(increase)=="number" and increase%1==0 and increase>=0 and increase<=400,"policyCostIncrease must be 0 to 400")
    assert(o.mapShape==nil or o.mapShape=="Hex" or o.mapShape=="Sphere","unknown map shape")
    -- Barbarians default to on for a solo match and off for two humans.
    assert(o.barbarians==nil or type(o.barbarians)=="boolean","barbarians must be a boolean")
    local barbarians=if o.barbarians==nil then humans==1 else o.barbarians
    assert(o.mapShape=="Sphere" or o.frequency==nil,"frequency requires Sphere")
    local map=if o.mapShape=="Sphere" then W.generateSphere(supplied,o.frequency or 2) else W.generate(supplied,radius)
    local s: any={seed=supplied,radius=radius,difficulty=difficulty,humanPlayers=humans,forest=o.forest==true,maxTurns=turns,cultureVictoryPolicies=threshold,policyCostIncrease=increase,turn=1,revision=0,activePlayerId=1,phase="Playing",tiles=map.tiles,units={},cities={},players={},diplomacy={status="Peace",peaceUntil=0,met=false},trades={},events={},nextEvent=1,nextUnit=1,nextCity=1,nextTrade=1,log={}}
    if o.mapShape=="Sphere" then s.mapShape="Sphere"; s.frequency=map.frequency; s.radius=nil end
    if barbarians then s.barbarians={camps={},nextCamp=1} end
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
local schemas: any={MoveUnit={unitId=true,tileId=true},RangedAttack={unitId=true,tileId=true},FoundCity={unitId=true},FortifyUnit={unitId=true},UpgradeUnit={unitId=true},BuildImprovement={unitId=true,improvement=true},SetProduction={cityId=true,item=true},Purchase={cityId=true,item=true},BuyTile={cityId=true,tileId=true},SetCityFocus={cityId=true,focus=true},Research={technology=true},AdoptPolicy={policy=true},DeclareWar={targetId=true},OfferPeace={targetId=true},AcceptPeace={targetId=true},ProposeTrade={targetId=true,giveGold=true,receiveGold=true},AcceptTrade={tradeId=true},CancelTrade={tradeId=true},EndTurn={},PromoteUnit={unitId=true,promotion=true},CityRangedStrike={cityId=true,targetUnitId=true}}
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
            local refusal=upgradeRefusal(s,u)
            if refusal then return reject(refusal) end
            upgrade(s,u)
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
        elseif cmd.kind=="BuyTile" then
            if not finiteId(cmd.tileId) or not table.find(borderCandidates(s,c),cmd.tileId) then return reject("Choose an unowned adjacent tile within three tiles of your city, without foreign occupants or a camp.") end
            local cost=buyTileCost(s,c,cmd.tileId)
            if p.gold<cost then return reject("Buying this tile needs "..cost.." gold.") end
            p.gold-=cost; acquireBorderTile(s,c,cmd.tileId,cost)
        elseif cmd.kind=="CityRangedStrike" then
            if not finiteId(cmd.targetUnitId) then return reject("Invalid unit identifier.") end
            if not strikeReady(s,c) then return reject("This city has used its strike this round.") end
            -- One message for a missing, hidden, friendly, out-of-range or peaceful target, so nothing hidden is revealed.
            local units,cities=occupants(s); local target=unitById(s,cmd.targetUnitId)
            if not target or not strikeTargetAllowed(s,c,target,visible(s,actorId),cities) then return reject("Choose a visible enemy unit within the city's range.") end
            cityStrike(s,c,target,units)
        else
            if type(cmd.item)~="string" then return reject("Production item is unavailable.") end
            if not canChoose(s,c,cmd.item) then return reject(productionRefusal(s,c,cmd.item)) end
            if cmd.kind=="Purchase" then
                if isWonder(cmd.item) then return reject("World wonders cannot be purchased.") end
                local cost=purchaseCost(s,cmd.item); local spawn=spawnTile(s,c)
                if p.gold<cost or (not R.buildings[cmd.item] and not spawn) then return reject("Purchase needs gold and a free deployment tile.") end
                p.gold -= cost; complete(s,c,cmd.item,spawn)
            else
                if c.queue==cmd.item then return reject("Already producing this item.") end; c.queue=cmd.item
            end
        end
    elseif cmd.kind=="Research" then
        local tech=if type(cmd.technology)=="string" then R.technologies[cmd.technology] else nil
        if not tech or not eligible(p,tech,p.technologies) or (p.research and p.research.id==tech.id) then return reject("Research is unavailable.") end
        p.research={id=tech.id,progress=0,cost=scaledCost(s,tech.cost)}
    elseif cmd.kind=="AdoptPolicy" then
        local policy=if type(cmd.policy)=="string" then R.policies[cmd.policy] else nil
        if not policy or not eligible(p,policy,p.policies) or p.culture<policyCost(s,p,policy) then return reject("Policy requires culture and prerequisites.") end
        p.culture -= policyCost(s,p,policy); table.insert(p.policies,policy.id); event(s,"Policy","Policy adopted: "..policy.id,nil,nil,actorId)
    elseif cmd.targetId~=nil then
        if cmd.targetId~=3-actorId then return reject("Choose the other civilization.") end
        if cmd.kind=="DeclareWar" then
            if s.diplomacy.status=="War" or s.turn<s.diplomacy.peaceUntil then return reject("War is unavailable during this peace treaty.") end
            s.diplomacy.status="War"; s.diplomacy.warPlan=nil; s.diplomacy.peaceOfferBy=nil; s.trades={}; event(s,"War","War declared.",nil,nil,nil,nil,true)
        elseif cmd.kind=="OfferPeace" then
            if s.diplomacy.status~="War" or s.diplomacy.peaceOfferBy==actorId then return reject("A peace offer is unavailable.") end
            s.diplomacy.peaceOfferBy=actorId
        elseif cmd.kind=="AcceptPeace" then
            if s.diplomacy.status~="War" or s.diplomacy.peaceOfferBy~=cmd.targetId then return reject("No peace offer to accept.") end
            s.diplomacy.status="Peace"; s.diplomacy.warPlan=nil; s.diplomacy.peaceOfferBy=nil; s.diplomacy.peaceUntil=s.turn+8; event(s,"Peace","Peace agreed.",nil,nil,nil,nil,true)
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
            projected.terrain=tile.terrain; projected.resource=tile.resource; projected.feature=tile.feature; projected.river=tile.river
            local yields=yieldFor({terrain=tile.terrain,resource=tile.resource,feature=tile.feature,river=tile.river})
            projected.food=yields.food; projected.production=yields.production; projected.gold=yields.gold
        end
        if seen[tile.id] then
            projected.ownerId=tile.ownerId; projected.improvement=tile.improvement; projected.road=tile.road
            local yields=yieldFor(tile); projected.food=yields.food; projected.production=yields.production; projected.gold=yields.gold
        end
        table.insert(tiles,projected)
    end
    local units,cities,events,legal,improvements,previews,riverMoves={},{},{},{},{},{},{}
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
                -- The upgrade the owner's technology opens, its gold cost and whether UpgradeUnit accepts it now.
                local nextKind=upgradeKind(s,u)
                if nextKind then view.upgradeKind=nextKind; view.upgradeCost=upgradeCost(s,u.kind,nextKind); view.canUpgrade=canAct and upgradeRefusal(s,u)==nil end
            else view.xp=nil end
            table.insert(units,view)
        end
        if u.ownerId==actorId then
            local targets,unitPreviews={},{}
            if canAct then
                -- The same search previewMove runs: its crossing flags give the destinations whose move ends by crossing
                -- an unbridged river (riverCrossing), listed ascending under the unit's id only when there are any.
                if u.moves>0 then
                    local spent,_,_,crossed=movementSearch(s,u,seen,occupancyUnits,occupancyCities); local river={}
                    for tileId in spent do
                        if tileId==u.tileId then continue end
                        table.insert(targets,tileId); if crossed[tileId] then table.insert(river,tileId) end
                    end
                    if #river>0 then table.sort(river); riverMoves[tostring(u.id)]=river end
                end
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
            local view=copy(c); view.strikeTurn=nil; view.borderTiles=nil
            local ready=strikeReady(s,c); local targets: {number}={}; local list={}
            if canAct and ready then
                targets=cityStrikeTargets(s,c,seen,occupancyUnits,occupancyCities)
                for _, id in targets do table.insert(list,cityStrikePreviewFor(s,c,unitById(s,id),occupancyUnits)) end
            end
            view.strength=cityStrength(s,c,occupancyUnits); view.rangedStrength=cityRangedStrength(s,c,occupancyUnits)
            view.strikeReady=ready; view.canStrike=#targets>0; view.strikeTargets=targets
            local candidates=borderCandidates(s,c)
            view.borderCulture=c.borderCulture or 0; view.nextTileCost=nextTileCost(s,c)
            view.nextBorderTile=bestBorderTile(s,c,candidates,seen)
            view.buyableTiles={}; for _, id in candidates do table.insert(view.buyableTiles,{tileId=id,cost=buyTileCost(s,c,id)}) end
            strikePreviews[tostring(c.id)]=list
            table.insert(cities,view)
        elseif seen[c.tileId] then table.insert(cities,{id=c.id,ownerId=c.ownerId,tileId=c.tileId,name=c.name,population=c.population,hp=c.hp,capital=c.capital,originalOwnerId=c.originalOwnerId}) end
    end
    for _, e in s.events do
        if e.kind=="BorderGrowth" and e.ownerId~=actorId then continue end
        if e.public or e.ownerId==actorId or (e.tileId and seen[e.tileId]) then
            local view=copy(e)
            -- Every civilization learns that a wonder was completed and by whom, but the city only while it can see the
            -- city tile (or built the wonder itself), as for the `wonders` list.
            if e.kind=="WonderBuilt" and e.ownerId~=actorId and not (e.tileId and seen[e.tileId]) then view.tileId=nil; view.cityId=nil end
            table.insert(events,view)
        end
    end
    local research,policies,production={},{},{}
    local productionByCity: {[string]: {string}},purchasesByCity: {[string]: {string}}={},{}
    for _, c in s.cities do if c.ownerId==actorId then productionByCity[tostring(c.id)]={}; purchasesByCity[tostring(c.id)]={} end end
    for _, id in R.technologyOrder do if eligible(p,R.technologies[id],p.technologies) then local entry=copy(R.technologies[id]); entry.cost=scaledCost(s,entry.cost); table.insert(research,entry) end end
    for _, id in R.policyOrder do if eligible(p,R.policies[id],p.policies) then local entry=copy(R.policies[id]); entry.cost=policyCost(s,p,R.policies[id]); table.insert(policies,entry) end end
    local productionOrder=copy(R.unitOrder); for _, id in R.buildingOrder do table.insert(productionOrder,id) end
    -- The actor's strategic stock, computed once for every menu below and reported as `strategic`: for each strategic
    -- resource in resourceOrder, `have` (its improved tiles' supply) and `used` (its living units' needs).
    local stock=strategicStock(s,actorId)
    local strategic: {[string]: {have: number, used: number}}={}
    for _, id in R.resourceOrder do if R.resources[id].category=="Strategic" then strategic[id]={have=stock.have[id] or 0,used=stock.used[id] or 0} end end
    for _, id in productionOrder do
        local added=false
        for _, c in s.cities do
            if c.ownerId==actorId and canChoose(s,c,id,stock) then
                table.insert(productionByCity[tostring(c.id)],id)
                if not isWonder(id) and p.gold>=purchaseCost(s,id) and (R.buildings[id] or spawnTile(s,c)) then table.insert(purchasesByCity[tostring(c.id)],id) end
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
    -- the queue at that rate. It replays the step without mutating the state: cities in id order, each using
    -- the shared yield and net functions with the step's happiness. After each city's production the overlay
    -- records its culture tile for later cities, just as the economy does. Production availability counts claimed improved
    -- resources and earlier own completions' strategic resources and deployment space. The global unit cap is fog-safe:
    -- the current total (already exposed by availableProductionByCity) plus earlier own completions against the
    -- units the actor can see; unseen rival units are never counted, so they cannot change any forecast.
    -- It reads only the actor's own cities, units, technologies and territory, tiles around its cities, visible units.
    local forecasts={}
    do
        local actor=s.players[actorId]; local worked,claimed,added={},{},{}; local _,cityTiles=occupants(s)
        local forecastSeen=table.clone(seen)
        local stepMood=stepHappiness(s,actorId,resourceInventory(s,actorId))
        local bonus=empireBonus(s,actorId); bonus.golden=goldenActive(actor)
        -- Wonders earlier own cities complete in this step: a later city queuing one loses the race and completes nothing.
        local wondersNow: {[string]: boolean}={}
        local own: {any}={}; for _, c in s.cities do if c.ownerId==actorId then table.insert(own,c) end end
        table.sort(own,function(a: any,b: any) return a.id<b.id end)
        for _, c in own do
            local yields=cityYields(s,actor,actorId,c,worked,cityTiles,bonus,claimed); local food,made=cityNet(s,actor,c,yields,stepMood,bonus)
            local growAt=growthCost(s,c.population); local cost=if R.productionCosts[c.queue] then productionCost(s,c.queue) else nil
            local canGrow=stepMood>=0 and c.population<R.maxPopulation
            -- The economy completes the queue only when it is still available and a unit has a free deployment tile.
            local blocked: ("NotAvailable" | "NoSpace" | "Idle")?=nil; local spawn: number?=nil
            if c.queue=="" then blocked="Idle"
            elseif wondersNow[c.queue] or not productionAvailable(s,c,c.queue,added,claimed) or (R.units[c.queue] and #units+#added>=R.maxUnits) then blocked="NotAvailable"
            elseif R.units[c.queue] then spawn=spawnTile(s,c,added); if not spawn then blocked="NoSpace" end end
            local turns: number?=nil
            if not blocked and cost then
                if c.production+made>=cost then turns=1 elseif made>0 then turns=math.ceil((cost-c.production)/made) end
                if turns==1 and spawn then
                    table.insert(added,{ownerId=actorId,kind=c.queue,tileId=spawn})
                    for _, id in nearby(s,spawn,2) do forecastSeen[id]=true end
                end
                if turns==1 and isWonder(c.queue) then wondersNow[c.queue]=true end
            end
            forecasts[tostring(c.id)]={food=food,production=made,gold=yields.gold,science=yields.science,culture=yields.culture,
                growthTurns=if not canGrow then nil elseif c.food+food>=growAt then 1 elseif food>0 then math.ceil((growAt-c.food)/food) else nil,
                productionTurns=turns,productionBlocked=blocked}
            local candidates=borderCandidates(s,c,claimed)
            local rate=math.max(0,yields.culture)+R.borderBaseRate
            for _, view in cities do
                if view.id==c.id then view.borderTurns=if #(view :: any).buyableTiles>0 then math.ceil((nextTileCost(s,c)-(c.borderCulture or 0))/rate) else nil end
            end
            if (c.borderCulture or 0)+rate>=nextTileCost(s,c) then
                local tileId=bestBorderTile(s,c,candidates,forecastSeen); if tileId then claimed[tileId]=true end
            end
        end
    end
    -- Completed world wonders in rule order. Completion and the holder are public (both civilizations always learn of a
    -- WonderBuilt and of a capture between them); the city only to its owner or while its tile is visible.
    local wonders={}
    for _, id in R.wonderOrder do
        local c=wonderCity(s,id)
        if not c then continue end
        local entry: any={id=id,ownerId=c.ownerId}
        if c.ownerId==actorId or seen[c.tileId] then entry.cityId=c.id; entry.tileId=c.tileId; entry.cityName=c.name end
        table.insert(wonders,entry)
    end
    -- The actor's own golden age (private). progressPerTurn is what its next economy step adds to the meter: the step's
    -- happiness when positive, computed as the step computes it, and 0 during a golden age.
    -- Barbarian encampments the actor can see now, ascending by id. A camp can be destroyed out of sight, so it is
    -- shown only while its tile is visible (no per-player memory is kept); barbarian units follow the unit rule.
    local camps={}
    if s.barbarians then for _, camp in s.barbarians.camps do if seen[camp.tileId] then table.insert(camps,{id=camp.id,tileId=camp.tileId}) end end end
    table.sort(camps,function(a: any,b: any) return a.id<b.id end)
    local age=p.goldenAge or {progress=0,turnsLeft=0,ages=0}
    local mood=stepHappiness(s,actorId,resourceInventory(s,actorId))
    local goldenAge={active=age.turnsLeft>0,turnsLeft=age.turnsLeft,progress=age.progress,threshold=goldenAgeThreshold(s,age.ages),ages=age.ages,
        progressPerTurn=if age.turnsLeft>0 then 0 else math.max(0,mood),turns=goldenAgeTurns(s)}
    local productionCosts: {[string]: number},purchaseCosts: {[string]: number}={},{}
    for id in R.productionCosts do productionCosts[id]=productionCost(s,id); purchaseCosts[id]=purchaseCost(s,id) end
    local d=s.diplomacy
    local diplomacy: DiplomacyView={status=d.status,peaceOfferBy=d.peaceOfferBy,peaceUntil=d.peaceUntil,met=d.met==true}
    local plan=d.warPlan
    if plan and plan.by~=actorId and d.met and d.status=="Peace" and d.peaceUntil==plan.peaceUntil and s.turn>=d.peaceUntil then
        diplomacy.warWarning={roundsLeft=math.max(0,plan.at-s.turn)}
    end
    return {strategic=strategic,barbarians=s.barbarians~=nil,camps=camps,wonders=wonders,goldenAge=goldenAge,cityForecasts=forecasts,seed=if s.humanPlayers==1 or s.phase=="Finished" then s.seed else nil,radius=s.radius,mapShape=s.mapShape,frequency=s.frequency,difficulty=s.difficulty,humanPlayers=s.humanPlayers,turn=s.turn,revision=s.revision,activePlayerId=s.activePlayerId,actorId=actorId,canAct=canAct,phase=s.phase,winner=s.winner,reason=s.reason,victoryType=s.victoryType,gold=p.gold,science=p.science,culture=p.culture,happiness=p.happiness,research=copy(p.research),technologies=copy(p.technologies),policies=copy(p.policies),resources=copy(resourceInventory(s,actorId)),income=copy(p.income),tiles=tiles,units=units,cities=cities,events=events,log={},legalMoves=legal,riverMoves=riverMoves,availableProduction=production,availableProductionByCity=productionByCity,availablePurchasesByCity=purchasesByCity,availableResearch=research,availablePolicies=policies,availableImprovements=improvements,productionCosts=productionCosts,purchaseCosts=purchaseCosts,scores=score,statistics=stats,progress=progress,cultureVictoryPolicies=threshold,policyCostIncrease=s.policyCostIncrease or 0,attackPreviews=previews,cityStrikePreviews=strikePreviews,diplomacy=diplomacy,trades=copy(s.trades),objectives={"Found cities, develop resources and maintain happiness.","Control both original capitals for domination.","Build "..R.buildings[R.scienceVictoryBuilding].name.." after "..R.technologies[R.scienceVictoryTechnology].name.." for science victory.","Adopt "..threshold.." "..(if threshold==1 then "policy" else "policies").." for culture victory.","Highest score wins at the round limit; ties break on technologies plus policies, otherwise a Draw."}}
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
    local spent,previous,zoc,crossed=movementSearch(s,u,visible(s,actorId),units,cities)
    if not spent[tileId] then return nil,"Destination is unavailable or movement is insufficient." end
    return movePreviewFor(s,u,tileId,spent,previous,zoc,crossed),nil
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
function BaseGame.costPercent(state: State, category: CostCategory?): number return costPercent(state,category) end
function BaseGame.getRules(): typeof(Rules) return copy(Rules) end
return table.freeze(BaseGame)
