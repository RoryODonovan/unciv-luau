--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Provenance-Kind: original
-- Original bounded civilization balance; no copied Unciv ruleset or media.
export type Yields = {food: number, production: number, gold: number, science: number, culture: number}
-- unitClass: "Melee" (strength above zero, range 1; Scouts included), "Ranged" (range above 1) or "Civilian" (strength 0).
-- It decides which promotions a unit may take. siegePercent is added to the unit's attack when it strikes a tile holding
-- an enemy city (Civ V's siege bonus against cities); it is 0 for every unit except the Catapult.
export type UnitRule = {id: string, cost: number, purchaseCost: number, hp: number, moves: number, strength: number, rangedStrength: number, range: number, maintenance: number, technology: string?, resource: string?, resourceAmount: number?, upgradeTo: string?, unitClass: string, siegePercent: number}
-- A building's `yields` go to its own city and its `happiness` to its owner. A world wonder (`wonder=true`) can be
-- completed once per world. Its empire effects follow the city that holds it (a captured wonder serves its captor):
-- `globalYields` add to every city of the owner, `sciencePercent` raises every city's science, `policyCostPercent` comes
-- off every policy's culture cost, `unitExperience` is given to each new military unit the owner builds or buys, and
-- `startsGoldenAge` starts (or extends) a golden age once, when the wonder is completed. Ordinary buildings have none
-- of these (zero yields, 0 or false).
export type BuildingRule = {id: string, name: string, cost: number, purchaseCost: number, maintenance: number, technology: string?, yields: Yields, happiness: number, defense: number,
    wonder: boolean, globalYields: Yields, sciencePercent: number, policyCostPercent: number, unitExperience: number, startsGoldenAge: boolean}
-- Golden-age numbers (see `goldenAge` in the rule table below).
export type GoldenAgeRule = {threshold: number, thresholdIncrease: number, turns: number, tileGold: number, productionPercent: number, paceTurns: number, minPacePercent: number, maxPacePercent: number}
export type Technology = {id: string, name: string, cost: number, prerequisites: {string}}
export type Policy = {id: string, name: string, cost: number, prerequisites: {string}, yields: Yields, happiness: number, maintenanceDiscount: number}
export type Improvement = {id: string, technology: string?, terrains: {string}, resources: {string}, turns: number, yields: Yields, road: boolean}
-- defensePercent: percentage added to a defender's strength on this terrain (Hills/Forest +25%).
-- rough: Hills and Forest (and impassable Mountain) are rough terrain for promotions (Drill); every other passable
-- terrain is open (Shock).
export type Terrain = {id: string, movement: number, passable: boolean, defensePercent: number, rough: boolean, yields: Yields}
-- A terrain feature on top of a tile's terrain (Civ V's Forest, Jungle, Marsh and Oasis), stored in the optional tile field
-- `feature`. It may stand only on the listed `terrains`. `movement` is the feature's movement cost (a step costs the larger
-- of it and the terrain's). `defensePercent` adds to the terrain's defence percentage and `rough` makes the tile rough
-- for promotions. With `overrideYields` the feature's `yields` replace the terrain's, otherwise they add to them (a
-- tile's yield never drops below zero). Of the non-road improvements only the listed `improvements` may be built on the
-- feature (there is no feature removal); roads may be built on any feature.
export type Feature = {id: string, terrains: {string}, movement: number, defensePercent: number, rough: boolean, yields: Yields, overrideYields: boolean, improvements: {string}}
-- A promotion's percentages add to the unit's combat strength in one strike, in the same sum as the other modifiers:
-- roughPercent when the strike's target tile is rough, openPercent when it is open, coverPercent while defending
-- against a ranged attack, accuracyPercent on a ranged attack against a unit. adjacentHeal is extra healing for the
-- owner's resting units next to this unit (several medics do not stack). All prerequisites must be taken first.
export type Promotion = {id: string, name: string, prerequisites: {string}, classes: {string}, roughPercent: number, openPercent: number, coverPercent: number, accuracyPercent: number, adjacentHeal: number}
export type Resource = {id: string, category: string, yields: Yields, happiness: number, improvement: string}
local function yields(food: number?, production: number?, gold: number?, science: number?, culture: number?): Yields
    return {food=food or 0, production=production or 0, gold=gold or 0, science=science or 0, culture=culture or 0}
end
local function freeze(value: any)
    if type(value) ~= "table" or table.isfrozen(value) then return end
    for _, child in value do freeze(child) end
    table.freeze(value)
end
local units: {[string]: UnitRule} = {}
local function unit(id: string, cost: number, hp: number, moves: number, strength: number, technology: string?, rangedStrength: number?, range: number?, resource: string?)
    local class=if strength<=0 then "Civilian" elseif (range or 1)>1 then "Ranged" else "Melee"
    units[id] = {id=id,cost=cost,purchaseCost=cost*4,hp=hp,moves=moves,strength=strength,rangedStrength=rangedStrength or 0,range=range or 1,maintenance=if strength > 0 then 1 else 0,technology=technology,resource=resource,resourceAmount=if resource then 1 else nil,unitClass=class,siegePercent=0}
end
unit("Scout",9,60,3,4); unit("Warrior",12,100,2,10); unit("Settler",24,50,2,0); unit("Worker",16,50,2,0)
unit("Archer",18,70,2,5,"Archery",12,2); unit("Swordsman",28,100,2,18,"IronWorking",nil,nil,"Iron")
unit("Pikeman",30,100,2,20,"CivilService"); unit("Knight",42,100,3,26,"CivilService",nil,nil,"Horses")
unit("Catapult",32,65,2,5,"Engineering",22,2); unit("Musketman",48,100,2,30,"Gunpowder"); unit("Rifleman",62,100,2,42,"Rifling")
units.Warrior.upgradeTo="Swordsman"; units.Swordsman.upgradeTo="Musketman"; units.Musketman.upgradeTo="Rifleman"
-- The Catapult is the roster's siege unit: +50% attack against cities.
units.Catapult.siegePercent=50
local buildings: {[string]: BuildingRule} = {}
local buildingNames: {[string]: string}={GuildHall="Guild Hall",SpaceProject="Space Project"}
local function building(id: string, cost: number, maintenance: number, technology: string?, effect: Yields, happiness: number?, defense: number?)
    buildings[id]={id=id,name=buildingNames[id] or id,cost=cost,purchaseCost=cost*4,maintenance=maintenance,technology=technology,yields=effect,happiness=happiness or 0,defense=defense or 0,
        wonder=false,globalYields=yields(),sciencePercent=0,policyCostPercent=0,unitExperience=0,startsGoldenAge=false}
end
building("Granary",16,1,"Agriculture",yields(2)); building("Monument",14,0,nil,yields(0,0,0,0,2))
building("Library",22,1,"Writing",yields(0,0,0,3)); building("Workshop",28,2,"Engineering",yields(0,3))
building("Market",24,1,"Currency",yields(0,0,4)); building("Walls",22,1,"Masonry",yields(),0,8)
building("Temple",26,1,"Philosophy",yields(0,0,0,0,3),2); building("University",40,2,"Education",yields(0,0,0,6))
building("SpaceProject",250,0,"Rocketry",yields()); building("Observatory",55,3,"Astronomy",yields(0,0,0,8)); building("GuildHall",48,2,"CivilService",yields(0,0,2,0,5))
-- World wonders: original, Civ V-flavoured effects under generic historical names, spread along the technology tree.
-- Each can be completed once per world, costs no maintenance and cannot be purchased.
type WonderExtra = {happiness: number?, globalYields: Yields?, sciencePercent: number?, policyCostPercent: number?, unitExperience: number?, startsGoldenAge: boolean?}
local function wonder(id: string, name: string, cost: number, technology: string, effect: Yields, extra: WonderExtra)
    building(id,cost,0,technology,effect,extra.happiness)
    local rule=buildings[id]; rule.name=name; rule.wonder=true; rule.globalYields=extra.globalYields or yields()
    rule.sciencePercent=extra.sciencePercent or 0; rule.policyCostPercent=extra.policyCostPercent or 0
    rule.unitExperience=extra.unitExperience or 0; rule.startsGoldenAge=extra.startsGoldenAge==true
end
wonder("HangingGardens","Hanging Gardens",60,"Agriculture",yields(2),{globalYields=yields(1)})
wonder("Colossus","Colossus",70,"BronzeWorking",yields(0,0,3),{globalYields=yields(0,0,1)})
wonder("GreatLibrary","Great Library",75,"Writing",yields(0,0,0,4,1),{})
wonder("TerracottaArmy","Terracotta Army",90,"IronWorking",yields(),{unitExperience=15})
wonder("Oracle","Oracle",100,"Philosophy",yields(0,0,0,0,3),{policyCostPercent=25})
wonder("NotreDame","Notre Dame",120,"CivilService",yields(0,0,0,0,2),{happiness=4})
wonder("HouseOfWisdom","House of Wisdom",140,"Education",yields(0,0,0,2),{sciencePercent=15})
wonder("TajMahal","Taj Mahal",170,"Gunpowder",yields(0,0,0,0,2),{startsGoldenAge=true})
local wonderOrder={"HangingGardens","Colossus","GreatLibrary","TerracottaArmy","Oracle","NotreDame","HouseOfWisdom","TajMahal"}
local buildingOrder={"Monument","Granary","Library","Walls","Market","Workshop","Temple","University","GuildHall","Observatory","SpaceProject"}
for _, id in wonderOrder do table.insert(buildingOrder,id) end
local technologies: {[string]: Technology} = {}
local technologyOrder = {"Agriculture","Mining","Archery","BronzeWorking","Writing","Masonry","IronWorking","Currency","Engineering","Philosophy","CivilService","Education","Astronomy","Gunpowder","Rifling","Rocketry"}
local function tech(id: string, cost: number, prerequisites: {string}) technologies[id]={id=id,name=id,cost=cost,prerequisites=prerequisites} end
tech("Agriculture",12,{}); tech("Mining",14,{}); tech("Archery",16,{"Agriculture"}); tech("BronzeWorking",22,{"Mining"})
tech("Writing",24,{"Agriculture"}); tech("Masonry",22,{"Mining"}); tech("IronWorking",38,{"BronzeWorking"})
tech("Currency",38,{"Writing"}); tech("Engineering",44,{"Masonry","BronzeWorking"}); tech("Philosophy",42,{"Writing"})
tech("CivilService",60,{"Currency","Philosophy"}); tech("Education",70,{"Philosophy","Engineering"}); tech("Astronomy",100,{"Education"}); tech("Gunpowder",90,{"Engineering","Education"}); tech("Rifling",130,{"Gunpowder"}); tech("Rocketry",180,{"Astronomy","Rifling"})
local policies: {[string]: Policy} = {
    Tradition={id="Tradition",name="Tradition",cost=20,prerequisites={},yields=yields(1),happiness=1,maintenanceDiscount=0},
    Liberty={id="Liberty",name="Liberty",cost=25,prerequisites={},yields=yields(0,1),happiness=0,maintenanceDiscount=0},
    Honor={id="Honor",name="Honor",cost=30,prerequisites={},yields=yields(),happiness=1,maintenanceDiscount=0.15},
    Commerce={id="Commerce",name="Commerce",cost=40,prerequisites={"Liberty"},yields=yields(0,0,2),happiness=0,maintenanceDiscount=0},
    Rationalism={id="Rationalism",name="Rationalism",cost=55,prerequisites={"Tradition"},yields=yields(0,0,0,3),happiness=0,maintenanceDiscount=0},
    Patronage={id="Patronage",name="Patronage",cost=65,prerequisites={"Commerce"},yields=yields(0,0,0,0,3),happiness=2,maintenanceDiscount=0},
}
local terrains: {[string]: Terrain} = {
    Plains={id="Plains",movement=1,passable=true,defensePercent=0,rough=false,yields=yields(2,1)},
    Grassland={id="Grassland",movement=1,passable=true,defensePercent=0,rough=false,yields=yields(3)},
    Hills={id="Hills",movement=2,passable=true,defensePercent=25,rough=true,yields=yields(1,2)},
    Forest={id="Forest",movement=2,passable=true,defensePercent=25,rough=true,yields=yields(1,2)},
    Desert={id="Desert",movement=1,passable=true,defensePercent=0,rough=false,yields=yields(0,1)},
    Tundra={id="Tundra",movement=1,passable=true,defensePercent=0,rough=false,yields=yields(1)},
    Water={id="Water",movement=1,passable=false,defensePercent=0,rough=false,yields=yields(1,0,1)},
    Mountain={id="Mountain",movement=1,passable=false,defensePercent=0,rough=true,yields=yields()},
}
-- Civ V-flavoured synthetic features. Forest keeps the values of the legacy Forest terrain (which earlier generators
-- produced and older saves still hold); Jungle trades production for food, Marsh is wet lowland that is hard to cross and
-- to hold, and the Oasis is a fertile desert spring.
local features: {[string]: Feature} = {
    Forest={id="Forest",terrains={"Plains","Grassland","Tundra"},movement=2,defensePercent=25,rough=true,yields=yields(1,2),overrideYields=true,improvements={"Camp","Plantation"}},
    Jungle={id="Jungle",terrains={"Plains","Grassland"},movement=2,defensePercent=25,rough=true,yields=yields(2),overrideYields=true,improvements={"Plantation"}},
    Marsh={id="Marsh",terrains={"Grassland"},movement=2,defensePercent=-15,rough=true,yields=yields(-1),overrideYields=false,improvements={}},
    Oasis={id="Oasis",terrains={"Desert"},movement=1,defensePercent=-10,rough=false,yields=yields(3,0,1),overrideYields=true,improvements={}},
}
local resources: {[string]: Resource} = {
    Wheat={id="Wheat",category="Bonus",yields=yields(1),happiness=0,improvement="Farm"},
    Iron={id="Iron",category="Strategic",yields=yields(0,1),happiness=0,improvement="Mine"},
    Horses={id="Horses",category="Strategic",yields=yields(0,1),happiness=0,improvement="Pasture"},
    Gold={id="Gold",category="Luxury",yields=yields(0,0,2),happiness=3,improvement="Mine"},
    Spices={id="Spices",category="Luxury",yields=yields(0,0,1),happiness=3,improvement="Plantation"},
    Deer={id="Deer",category="Bonus",yields=yields(1),happiness=0,improvement="Camp"},
}
local improvements: {[string]: Improvement} = {
    Farm={id="Farm",technology="Agriculture",terrains={"Plains","Grassland"},resources={"Wheat"},turns=2,yields=yields(1),road=false},
    Mine={id="Mine",technology="Mining",terrains={"Hills","Plains","Desert"},resources={"Iron","Gold"},turns=3,yields=yields(0,1),road=false},
    Pasture={id="Pasture",technology="Agriculture",terrains={"Plains","Grassland"},resources={"Horses"},turns=2,yields=yields(0,1),road=false},
    Plantation={id="Plantation",technology="Currency",terrains={"Plains","Grassland","Forest"},resources={"Spices"},turns=3,yields=yields(0,0,2),road=false},
    -- Camp lists Grassland and Tundra so Deer under a Forest feature on those terrains stays valid. A Camp always needs its
    -- Deer, so bare land gains nothing.
    Camp={id="Camp",technology="Archery",terrains={"Forest","Plains","Grassland","Tundra"},resources={"Deer"},turns=2,yields=yields(1),road=false},
    Road={id="Road",technology="Engineering",terrains={"Plains","Grassland","Hills","Forest","Desert","Tundra"},resources={},turns=2,yields=yields(),road=true},
}
local promotions: {[string]: Promotion} = {}
local function promotion(id: string, name: string, prerequisites: {string}, classes: {string}, effect: {roughPercent: number?, openPercent: number?, coverPercent: number?, accuracyPercent: number?, adjacentHeal: number?})
    promotions[id]={id=id,name=name,prerequisites=prerequisites,classes=classes,roughPercent=effect.roughPercent or 0,openPercent=effect.openPercent or 0,
        coverPercent=effect.coverPercent or 0,accuracyPercent=effect.accuracyPercent or 0,adjacentHeal=effect.adjacentHeal or 0}
end
-- Four lines: Drill (rough terrain) and Shock (open terrain) for melee units, Accuracy for ranged units, and Cover
-- leading to Medic for both.
promotion("Drill1","Drill I",{},{"Melee"},{roughPercent=15}); promotion("Drill2","Drill II",{"Drill1"},{"Melee"},{roughPercent=15})
promotion("Shock1","Shock I",{},{"Melee"},{openPercent=15}); promotion("Shock2","Shock II",{"Shock1"},{"Melee"},{openPercent=15})
promotion("Accuracy1","Accuracy I",{},{"Ranged"},{accuracyPercent=15})
promotion("Cover1","Cover I",{},{"Melee","Ranged"},{coverPercent=33}); promotion("Medic","Medic",{"Cover1"},{"Melee","Ranged"},{adjacentHeal=5})
local productionCosts: {[string]: number}, purchaseCosts: {[string]: number} = {}, {}
for id, rule in units do productionCosts[id]=rule.cost; purchaseCosts[id]=rule.purchaseCost end
for id, rule in buildings do productionCosts[id]=rule.cost; purchaseCosts[id]=rule.purchaseCost end
local terrainYields: {[string]: Yields} = {}
for id, rule in terrains do terrainYields[id]=rule.yields end
local rules = {
    minRadius=3,maxRadius=40,maxTiles=4921,radius=4,maxTurns=120,maxPopulation=100,maxUnits=169,maxCities=24,
    units=units,unitStats=units,buildings=buildings,buildingEffects=buildings,technologies=technologies,technologyOrder=technologyOrder,
    unitOrder={"Scout","Warrior","Settler","Worker","Archer","Swordsman","Pikeman","Knight","Catapult","Musketman","Rifleman"},buildingOrder=buildingOrder,wonderOrder=wonderOrder,
    policies=policies,policyOrder={"Tradition","Liberty","Honor","Commerce","Rationalism","Patronage"},
    terrains=terrains,terrainYields=terrainYields,features=features,featureOrder={"Forest","Jungle","Marsh","Oasis"},resources=resources,improvements=improvements,improvementOrder={"Farm","Mine","Pasture","Plantation","Camp","Road"},
    productionCosts=productionCosts,purchaseCosts=purchaseCosts,upgradeCost=40,workerTurns=2,
    cityHp=150,cityBaseYields=yields(2,2,2,2,1),cityWorkRadius=2,foodPerPopulation=2,baseHappiness=9,unhappinessPerCity=2,unhappinessPerPopulation=1,
    growthBase=20,growthPerPopulation=8,starvationLoss=1,unitVision=2,cityVision=2,
    -- Moving between two road tiles costs a third of a move (Civ V), whatever the terrain.
    roadMovement=1/3,
    -- Rivers run along tile edges (the optional tile mask `river`). A tile with a river on any edge yields riverGold more
    -- gold, and a Farm on it riverFarmFood more food (fresh water). A step across a river edge spends all remaining
    -- movement unless both tiles have roads (the road bridges it), and a melee attack across a river loses
    -- riverAttackPercent of its attack (Civ V's -20%).
    riverGold=1,riverFarmFood=1,riverAttackPercent=20,
    scienceVictoryTechnology="Rocketry",scienceVictoryBuilding="SpaceProject",cultureVictoryPolicies=6,score={city=10,population=3,unit=2,technology=5,policy=5,wonder=10},
    maxTradeTurns=20,maxTradeDeals=16,maxEvents=64,maxLog=24,
    -- Combat percentages: fortification adds to the terrain percentage in one defence multiplier; each other
    -- friendly military unit next to a defending unit adds to a melee attack, up to the cap.
    fortifyDefensePercent=50,flankingPercent=10,maxFlankingPercent=30,
    -- Hit points a unit regains at the start of its owner's turn after a turn without moving or attacking.
    healing={neutral=10,friendly=15,city=20},
    -- Experience from combat: a melee attacker gains 5, a unit defending against melee 4, a ranged attacker 2 and a
    -- unit hit by a ranged attack 2. A strike on a civilian gives none, and civilians never gain any. A unit reaches a
    -- level at each cumulative threshold (as in Civ V: 10, 30, 60...), and each level earned and not yet spent lets it
    -- choose one promotion. Experience stops at the last threshold.
    experience={meleeAttack=5,meleeDefense=4,rangedAttack=2,rangedDefense=2},experienceThresholds={10,30,60,100,150,210},maxExperience=210,
    promotions=promotions,promotionOrder={"Drill1","Drill2","Shock1","Shock2","Accuracy1","Cover1","Medic"},
    -- Taking a promotion heals this percentage of the unit's maximum hit points and ends its movement this turn.
    promotionHealPercent=50,
    -- City combat. A city's combat strength is cityBaseStrength + population + cityStrengthPerEra x (era - 1) + its
    -- buildings' defence (Walls) + garrisonPercent of the strength of a military unit standing in it (rounded down).
    -- An undefended city still defends with (cityBaseStrength + population) x terrain percentage, plus Walls.
    -- Once per round a city may strike a visible enemy unit within cityStrikeRange with cityStrikePercent of its
    -- combat strength (rounded down) as its ranged strength; it takes no damage and gains no experience.
    cityBaseStrength=14,cityStrengthPerEra=3,garrisonPercent=25,cityStrikeRange=2,cityStrikePercent=60,
    -- Golden ages. Each of its owner's economy steps outside a golden age adds the step's happiness, when positive, to
    -- the civilization's meter. When the meter reaches the threshold (threshold + thresholdIncrease x golden ages so
    -- far) it is spent and a golden age of `turns` owner steps begins with the next step. During one, every worked tile
    -- and city centre yielding at least 1 gold yields `tileGold` more, and each city's production rises by
    -- `productionPercent`. Both the threshold and the length scale with the match's round limit against `paceTurns`
    -- (clamped from minPacePercent to maxPacePercent).
    goldenAge={threshold=120,thresholdIncrease=60,turns=8,tileGold=1,productionPercent=20,paceTurns=120,minPacePercent=50,maxPacePercent=200} :: GoldenAgeRule,
}
freeze(rules)
return rules





