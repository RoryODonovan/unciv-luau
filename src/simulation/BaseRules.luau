--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Provenance-Kind: original
-- Original bounded civilization balance; no copied Unciv ruleset or media.
export type Yields = {food: number, production: number, gold: number, science: number, culture: number}
-- unitClass: "Melee" (strength above zero, range 1; Scouts included), "Ranged" (range above 1) or "Civilian" (strength 0).
-- It decides which promotions a unit may take.
export type UnitRule = {id: string, cost: number, purchaseCost: number, hp: number, moves: number, strength: number, rangedStrength: number, range: number, maintenance: number, technology: string?, resource: string?, resourceAmount: number?, upgradeTo: string?, unitClass: string}
export type BuildingRule = {id: string, cost: number, purchaseCost: number, maintenance: number, technology: string?, yields: Yields, happiness: number, defense: number}
export type Technology = {id: string, name: string, cost: number, prerequisites: {string}}
export type Policy = {id: string, name: string, cost: number, prerequisites: {string}, yields: Yields, happiness: number, maintenanceDiscount: number}
export type Improvement = {id: string, technology: string?, terrains: {string}, resources: {string}, turns: number, yields: Yields, road: boolean}
-- defensePercent: percentage added to a defender's strength on this terrain (Hills/Forest +25%).
-- rough: Hills and Forest (and impassable Mountain) are rough terrain for promotions (Drill); every other passable
-- terrain is open (Shock).
export type Terrain = {id: string, movement: number, passable: boolean, defensePercent: number, rough: boolean, yields: Yields}
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
    units[id] = {id=id,cost=cost,purchaseCost=cost*4,hp=hp,moves=moves,strength=strength,rangedStrength=rangedStrength or 0,range=range or 1,maintenance=if strength > 0 then 1 else 0,technology=technology,resource=resource,resourceAmount=if resource then 1 else nil,unitClass=class}
end
unit("Scout",9,60,3,4); unit("Warrior",12,100,2,10); unit("Settler",24,50,2,0); unit("Worker",16,50,2,0)
unit("Archer",18,70,2,5,"Archery",12,2); unit("Swordsman",28,100,2,18,"IronWorking",nil,nil,"Iron")
unit("Pikeman",30,100,2,20,"CivilService"); unit("Knight",42,100,3,26,"CivilService",nil,nil,"Horses")
unit("Catapult",32,65,2,5,"Engineering",22,2); unit("Musketman",48,100,2,30,"Gunpowder"); unit("Rifleman",62,100,2,42,"Rifling")
units.Warrior.upgradeTo="Swordsman"; units.Swordsman.upgradeTo="Musketman"; units.Musketman.upgradeTo="Rifleman"
local buildings: {[string]: BuildingRule} = {}
local function building(id: string, cost: number, maintenance: number, technology: string?, effect: Yields, happiness: number?, defense: number?)
    buildings[id]={id=id,cost=cost,purchaseCost=cost*4,maintenance=maintenance,technology=technology,yields=effect,happiness=happiness or 0,defense=defense or 0}
end
building("Granary",16,1,"Agriculture",yields(2)); building("Monument",14,0,nil,yields(0,0,0,0,2))
building("Library",22,1,"Writing",yields(0,0,0,3)); building("Workshop",28,2,"Engineering",yields(0,3))
building("Market",24,1,"Currency",yields(0,0,4)); building("Walls",22,1,"Masonry",yields(),0,8)
building("Temple",26,1,"Philosophy",yields(0,0,0,0,3),2); building("University",40,2,"Education",yields(0,0,0,6))
building("SpaceProject",250,0,"Rocketry",yields()); building("Observatory",55,3,"Astronomy",yields(0,0,0,8)); building("GuildHall",48,2,"CivilService",yields(0,0,2,0,5))
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
    Camp={id="Camp",technology="Archery",terrains={"Forest","Plains"},resources={"Deer"},turns=2,yields=yields(1),road=false},
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
    unitOrder={"Scout","Warrior","Settler","Worker","Archer","Swordsman","Pikeman","Knight","Catapult","Musketman","Rifleman"},buildingOrder={"Monument","Granary","Library","Walls","Market","Workshop","Temple","University","GuildHall","Observatory","SpaceProject"},
    policies=policies,policyOrder={"Tradition","Liberty","Honor","Commerce","Rationalism","Patronage"},
    terrains=terrains,terrainYields=terrainYields,resources=resources,improvements=improvements,improvementOrder={"Farm","Mine","Pasture","Plantation","Camp","Road"},
    productionCosts=productionCosts,purchaseCosts=purchaseCosts,upgradeCost=40,workerTurns=2,
    cityHp=150,cityBaseYields=yields(2,2,2,2,1),cityWorkRadius=2,foodPerPopulation=2,baseHappiness=9,unhappinessPerCity=2,unhappinessPerPopulation=1,
    growthBase=20,growthPerPopulation=8,starvationLoss=1,unitVision=2,cityVision=2,
    -- Moving between two road tiles costs a third of a move (Civ V), whatever the terrain.
    roadMovement=1/3,
    scienceVictoryTechnology="Rocketry",scienceVictoryBuilding="SpaceProject",cultureVictoryPolicies=6,score={city=10,population=3,unit=2,technology=5,policy=5},
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
}
freeze(rules)
return rules





