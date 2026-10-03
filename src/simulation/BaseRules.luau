--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Provenance-Kind: original
-- Original bounded civilization balance; no copied Unciv ruleset or media.
export type Yields = {food: number, production: number, gold: number, science: number, culture: number}
-- Combat values (G7). `attack` is the unit's melee attack strength, `defense` its defence strength and `rangedStrength`
-- the strength of its ranged attack (0 for a unit without one). `strength` is the larger of attack and defence: the
-- unit's headline combat strength, kept from the earlier single-value rules; 0 marks a civilian. Every unit from before
-- G7 has attack = defence = strength, so it fights exactly as before.
-- unitClass: "Melee" (strength above zero, range 1; Scouts included), "Ranged" (range above 1) or "Civilian" (strength 0).
-- It decides which promotions a unit may take, and an upgrade never changes it. `role` is the combat type: "Civilian",
-- "Recon", "Melee", "Mounted", "Archery", "Siege", "Gunpowder" or "Armor". `versus` maps a role to a percentage added to
-- the unit's attack and defence in a strike against a unit of that role (the Spearman line's bonus against Mounted).
-- siegePercent is added to the unit's attack when it strikes a tile holding an enemy city (Civ V's siege bonus against
-- cities); only Siege units have it. A unit with `resource` needs `resourceAmount` of that strategic resource while it
-- lives (see `resources[*].quantity`). `era` is the era of its technology (1 without one).
export type UnitRule = {id: string, name: string, era: number, cost: number, purchaseCost: number, hp: number, moves: number, strength: number, attack: number, defense: number, rangedStrength: number, range: number, maintenance: number, technology: string?, resource: string?, resourceAmount: number?, upgradeTo: string?, unitClass: string, role: string, versus: {[string]: number}, siegePercent: number}
-- A building's `yields` go to its own city and its `happiness` to its owner. A world wonder (`wonder=true`) can be
-- completed once per world. Its empire effects follow the city that holds it (a captured wonder serves its captor):
-- `globalYields` add to every city of the owner, `sciencePercent` raises every city's science, `policyCostPercent` comes
-- off every policy's culture cost, `unitExperience` is given to each new military unit the owner builds or buys, and
-- `startsGoldenAge` starts (or extends) a golden age once, when the wonder is completed. Ordinary buildings have none
-- of these (zero yields, 0 or false). `era` is the era of its technology (1 without one).
export type BuildingRule = {id: string, name: string, era: number, cost: number, purchaseCost: number, maintenance: number, technology: string?, yields: Yields, happiness: number, defense: number,
    wonder: boolean, globalYields: Yields, sciencePercent: number, policyCostPercent: number, unitExperience: number, startsGoldenAge: boolean}
-- Golden-age numbers (see `goldenAge` in the rule table below).
export type GoldenAgeRule = {threshold: number, thresholdIncrease: number, turns: number, tileGold: number, productionPercent: number, paceTurns: number, minPacePercent: number, maxPacePercent: number}
-- `era` (1-6) indexes `eras`; a civilization's era is the highest era among the technologies it knows.
export type Technology = {id: string, name: string, era: number, cost: number, prerequisites: {string}}
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
-- `quantity`: what one improved tile of the resource supplies. For a strategic resource it is the number of units that
-- tile supports (each living unit needing the resource uses its `resourceAmount`); bonus and luxury resources have 1.
export type Resource = {id: string, name: string, category: string, quantity: number, yields: Yields, happiness: number, improvement: string}
-- Barbarians: a non-playing hostile faction whose units carry `ownerId` (0, never a civilization's id). See `barbarians`
-- in the rule table below for the meaning of each value.
export type BarbarianRule = {ownerId: number, firstCampTurn: number, campInterval: number, spawnInterval: number, tilesPerCamp: number, maxCamps: number,
    unitsPerCamp: number, maxUnits: number, campCityDistance: number, campSpacing: number, huntRadius: number, leashRadius: number, campGold: number,
    maxExperience: number, healing: number, difficultyPercent: {[string]: number}, eraUnits: {{string}}}
local function yields(food: number?, production: number?, gold: number?, science: number?, culture: number?): Yields
    return {food=food or 0, production=production or 0, gold=gold or 0, science=science or 0, culture=culture or 0}
end
local function freeze(value: any)
    if type(value) ~= "table" or table.isfrozen(value) then return end
    for _, child in value do freeze(child) end
    table.freeze(value)
end
-- Eras, earliest first; a technology's `era` indexes this list.
local eras={"Ancient","Classical","Medieval","Renaissance","Industrial","Modern"}
local units: {[string]: UnitRule} = {}
local unitOrder: {string}={}
-- A unit's combat values. `strength` alone gives attack = defence = strength (every unit from before G7); `attack` and
-- `defense` set them apart. `ranged` and `range` make a ranged unit, `siege` its bonus against cities.
type UnitSpec = {name: string?, cost: number, hp: number, moves: number, role: string, strength: number?, attack: number?, defense: number?, ranged: number?, range: number?,
    technology: string?, resource: string?, upgradeTo: string?, versus: {[string]: number}?, siege: number?}
local function unit(id: string, spec: UnitSpec)
    local attack=spec.attack or spec.strength or 0; local defense=spec.defense or spec.strength or 0
    local strength=spec.strength or math.max(attack,defense); local range=spec.range or 1
    local class=if strength<=0 then "Civilian" elseif range>1 then "Ranged" else "Melee"
    units[id]={id=id,name=spec.name or id,era=1,cost=spec.cost,purchaseCost=spec.cost*4,hp=spec.hp,moves=spec.moves,strength=strength,attack=attack,defense=defense,
        rangedStrength=spec.ranged or 0,range=range,maintenance=if strength>0 then 1 else 0,technology=spec.technology,resource=spec.resource,
        resourceAmount=if spec.resource then 1 else nil,upgradeTo=spec.upgradeTo,unitClass=class,role=spec.role,versus=spec.versus or {},siegePercent=spec.siege or 0}
    table.insert(unitOrder,id)
end
-- The roster by era. The eleven units from before G7 keep their numbers (attack = defence = strength); the Pikeman gains
-- the Spearman line's +50% against mounted units, and the Scout, Archer, Swordsman, Pikeman, Knight, Catapult and
-- Rifleman gain upgrades. Original synthetic values under generic historical names.
-- Ancient
unit("Scout",{cost=9,hp=60,moves=3,strength=4,role="Recon",upgradeTo="Explorer"})
unit("Warrior",{cost=12,hp=100,moves=2,strength=10,role="Melee",upgradeTo="Swordsman"})
unit("Settler",{cost=24,hp=50,moves=2,strength=0,role="Civilian"})
unit("Worker",{cost=16,hp=50,moves=2,strength=0,role="Civilian"})
unit("Archer",{cost=18,hp=70,moves=2,strength=5,ranged=12,range=2,technology="Archery",role="Archery",upgradeTo="CompositeBowman"})
unit("Chariot",{cost=22,hp=100,moves=3,attack=13,defense=8,technology="AnimalHusbandry",resource="Horses",role="Mounted",upgradeTo="Horseman"})
-- Classical
unit("Spearman",{cost=18,hp=100,moves=2,attack=12,defense=14,technology="BronzeWorking",role="Melee",versus={Mounted=50},upgradeTo="Pikeman"})
unit("Horseman",{cost=30,hp=100,moves=3,attack=18,defense=11,technology="HorsebackRiding",resource="Horses",role="Mounted",upgradeTo="Knight"})
unit("Swordsman",{cost=28,hp=100,moves=2,strength=18,technology="IronWorking",resource="Iron",role="Melee",upgradeTo="Longswordsman"})
unit("CompositeBowman",{name="Composite Bowman",cost=26,hp=75,moves=2,attack=6,defense=8,ranged=16,range=2,technology="Mathematics",role="Archery",upgradeTo="Crossbowman"})
unit("Catapult",{cost=32,hp=65,moves=2,strength=5,ranged=22,range=2,technology="Engineering",role="Siege",siege=50,upgradeTo="Trebuchet"})
-- Medieval
unit("Pikeman",{cost=30,hp=100,moves=2,strength=20,technology="CivilService",role="Melee",versus={Mounted=50},upgradeTo="Musketman"})
unit("Knight",{cost=42,hp=100,moves=3,strength=26,technology="CivilService",resource="Horses",role="Mounted",upgradeTo="Lancer"})
unit("Longswordsman",{cost=40,hp=100,moves=2,attack=25,defense=23,technology="Steel",resource="Iron",role="Melee",upgradeTo="Musketman"})
unit("Crossbowman",{cost=36,hp=75,moves=2,attack=8,defense=11,ranged=20,range=2,technology="Machinery",role="Archery",upgradeTo="GatlingGun"})
unit("Trebuchet",{cost=44,hp=70,moves=2,attack=6,defense=7,ranged=30,range=2,technology="Machinery",resource="Iron",role="Siege",siege=50,upgradeTo="Cannon"})
-- Renaissance
unit("Explorer",{cost=30,hp=80,moves=3,attack=8,defense=9,technology="Astronomy",role="Recon"})
unit("Musketman",{cost=48,hp=100,moves=2,strength=30,technology="Gunpowder",role="Gunpowder",upgradeTo="Rifleman"})
unit("Lancer",{cost=56,hp=100,moves=3,attack=34,defense=24,technology="Metallurgy",resource="Horses",role="Mounted",upgradeTo="Cavalry"})
unit("Cannon",{cost=58,hp=70,moves=2,attack=8,defense=10,ranged=40,range=2,technology="Chemistry",resource="Saltpeter",role="Siege",siege=50,upgradeTo="Artillery"})
-- Industrial
unit("Rifleman",{cost=62,hp=100,moves=2,strength=42,technology="Rifling",role="Gunpowder",upgradeTo="Infantry"})
unit("Cavalry",{cost=70,hp=100,moves=4,attack=46,defense=32,technology="MilitaryScience",resource="Horses",role="Mounted",upgradeTo="Tank"})
unit("GatlingGun",{name="Gatling Gun",cost=68,hp=90,moves=2,attack=12,defense=32,ranged=34,range=2,technology="Industrialization",resource="Saltpeter",role="Archery",upgradeTo="MachineGun"})
unit("Artillery",{cost=84,hp=70,moves=2,attack=10,defense=14,ranged=62,range=3,technology="Dynamite",resource="Saltpeter",role="Siege",siege=50,upgradeTo="RocketArtillery"})
-- Modern
unit("Infantry",{cost=90,hp=100,moves=2,attack=58,defense=60,technology="Ballistics",role="Gunpowder"})
unit("MachineGun",{name="Machine Gun",cost=92,hp=90,moves=2,attack=14,defense=46,ranged=50,range=2,technology="Ballistics",resource="Saltpeter",role="Archery"})
unit("AntiTankGun",{name="Anti-Tank Gun",cost=86,hp=100,moves=2,attack=40,defense=52,technology="Ballistics",role="Gunpowder",versus={Armor=75}})
unit("Tank",{cost=110,hp=100,moves=4,attack=70,defense=54,technology="Combustion",resource="Oil",role="Armor",upgradeTo="BattleTank"})
unit("RocketArtillery",{name="Rocket Artillery",cost=120,hp=75,moves=3,attack=14,defense=20,ranged=90,range=3,technology="Rocketry",resource="Oil",role="Siege",siege=50})
unit("BattleTank",{name="Battle Tank",cost=150,hp=100,moves=4,attack=96,defense=76,technology="Computers",resource="Oil",role="Armor"})
local buildings: {[string]: BuildingRule} = {}
local buildingNames: {[string]: string}={GuildHall="Guild Hall",SpaceProject="Space Project",StockExchange="Stock Exchange",PowerPlant="Power Plant",ResearchLab="Research Lab"}
local function building(id: string, cost: number, maintenance: number, technology: string?, effect: Yields, happiness: number?, defense: number?)
    buildings[id]={id=id,name=buildingNames[id] or id,era=1,cost=cost,purchaseCost=cost*4,maintenance=maintenance,technology=technology,yields=effect,happiness=happiness or 0,defense=defense or 0,
        wonder=false,globalYields=yields(),sciencePercent=0,policyCostPercent=0,unitExperience=0,startsGoldenAge=false}
end
-- The eleven buildings from before G7 keep their values (the Space Project now needs Space Flight, the science victory's
-- technology). Each new one has one or two plain effects through the existing city yields, happiness and defence.
building("Granary",16,1,"Agriculture",yields(2)); building("Monument",14,0,nil,yields(0,0,0,0,2))
building("Library",22,1,"Writing",yields(0,0,0,3)); building("Workshop",28,2,"Engineering",yields(0,3))
building("Market",24,1,"Currency",yields(0,0,4)); building("Walls",22,1,"Masonry",yields(),0,8)
building("Temple",26,1,"Philosophy",yields(0,0,0,0,3),2); building("University",40,2,"Education",yields(0,0,0,6))
building("SpaceProject",250,0,"SpaceFlight",yields()); building("Observatory",55,3,"Astronomy",yields(0,0,0,8)); building("GuildHall",48,2,"CivilService",yields(0,0,2,0,5))
building("Shrine",18,1,"Pottery",yields(1),1); building("Forge",34,1,"IronWorking",yields(0,2))
building("Aqueduct",38,1,"Engineering",yields(3)); building("Colosseum",36,1,"Construction",yields(),3)
building("Monastery",46,2,"Theology",yields(0,0,0,2,2)); building("Castle",44,1,"Chivalry",yields(),0,6)
building("Bank",60,1,"Banking",yields(0,0,5)); building("Theatre",66,2,"PrintingPress",yields(0,0,0,0,2),3)
building("StockExchange",80,2,"Economics",yields(0,0,6)); building("Factory",96,3,"Industrialization",yields(0,6))
building("Hospital",90,2,"Medicine",yields(4)); building("PowerPlant",110,3,"Electricity",yields(0,6))
building("Stadium",104,2,"Radio",yields(),4); building("ResearchLab",120,3,"Computers",yields(0,0,0,10))
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
-- Ordinary buildings by era (each era's in a fixed order), then the wonders.
local buildingOrder={"Monument","Granary","Shrine","Walls",
    "Library","Market","Forge","Workshop","Aqueduct","Temple","Colosseum",
    "University","GuildHall","Monastery","Castle",
    "Observatory","Bank","Theatre","StockExchange",
    "Factory","Hospital","PowerPlant",
    "Stadium","ResearchLab","SpaceProject"}
for _, id in wonderOrder do table.insert(buildingOrder,id) end
-- Forty technologies in six eras. The sixteen from before G7 keep their ids, costs and prerequisites (so every earlier
-- save's knowledge and research stay valid); the new ones join the tree around them and after them. Eras follow the
-- tree: Classical opens with Bronze Working or Writing, Medieval with Civil Service, Theology or Machinery, Renaissance
-- with Astronomy, Gunpowder, Banking or Printing Press, Industrial with Rifling and Modern with Rocketry.
-- `technologyOrder` is the recommended research order, which the AI follows (the first technology it may research):
-- the tree's main line first, with side branches after the era's core. It lists every prerequisite before the
-- technologies needing it.
local technologies: {[string]: Technology} = {}
local technologyOrder: {string}={"Agriculture","Mining","Archery","BronzeWorking","Writing","Masonry","Pottery","IronWorking","Currency","Engineering","Philosophy",
    "CivilService","AnimalHusbandry","Mathematics","Education","Construction","Astronomy","HorsebackRiding","Machinery","Theology","Gunpowder","Steel","Chivalry",
    "Banking","PrintingPress","Rifling","Chemistry","Metallurgy","Economics","Industrialization","MilitaryScience","Medicine","Electricity","Dynamite","Rocketry",
    "Radio","Combustion","Ballistics","Computers","SpaceFlight"}
local technologyNames: {[string]: string}={BronzeWorking="Bronze Working",IronWorking="Iron Working",CivilService="Civil Service",AnimalHusbandry="Animal Husbandry",
    HorsebackRiding="Horseback Riding",PrintingPress="Printing Press",MilitaryScience="Military Science",SpaceFlight="Space Flight"}
local function tech(id: string, era: number, cost: number, prerequisites: {string})
    technologies[id]={id=id,name=technologyNames[id] or id,era=era,cost=cost,prerequisites=prerequisites}
end
-- Ancient
tech("Agriculture",1,12,{}); tech("Mining",1,14,{}); tech("Archery",1,16,{"Agriculture"}); tech("Masonry",1,22,{"Mining"})
tech("Pottery",1,16,{"Agriculture"}); tech("AnimalHusbandry",1,18,{"Agriculture"})
-- Classical
tech("BronzeWorking",2,22,{"Mining"}); tech("Writing",2,24,{"Agriculture"}); tech("IronWorking",2,38,{"BronzeWorking"}); tech("Currency",2,38,{"Writing"})
tech("Engineering",2,44,{"Masonry","BronzeWorking"}); tech("Philosophy",2,42,{"Writing"}); tech("HorsebackRiding",2,34,{"AnimalHusbandry"})
tech("Mathematics",2,40,{"Archery","Writing"}); tech("Construction",2,46,{"Masonry","Pottery"})
-- Medieval
tech("CivilService",3,60,{"Currency","Philosophy"}); tech("Education",3,70,{"Philosophy","Engineering"}); tech("Theology",3,66,{"Philosophy"})
tech("Machinery",3,68,{"Engineering","Mathematics"}); tech("Chivalry",3,72,{"CivilService","HorsebackRiding"}); tech("Steel",3,76,{"IronWorking","Machinery"})
-- Renaissance
tech("Astronomy",4,100,{"Education"}); tech("Gunpowder",4,90,{"Engineering","Education"}); tech("Banking",4,96,{"CivilService"}); tech("PrintingPress",4,100,{"Education","Machinery"})
tech("Chemistry",4,106,{"Gunpowder","Astronomy"}); tech("Metallurgy",4,110,{"Gunpowder","Steel"}); tech("Economics",4,115,{"Banking","PrintingPress"})
-- Industrial
tech("Rifling",5,130,{"Gunpowder"}); tech("Industrialization",5,150,{"Economics","Metallurgy"}); tech("Medicine",5,140,{"Chemistry"})
tech("MilitaryScience",5,155,{"Rifling","Metallurgy"}); tech("Dynamite",5,160,{"MilitaryScience","Chemistry"}); tech("Electricity",5,170,{"Industrialization"})
-- Modern
tech("Rocketry",6,180,{"Astronomy","Rifling"}); tech("Combustion",6,210,{"Electricity","Dynamite"}); tech("Ballistics",6,200,{"Dynamite","Electricity"})
tech("Radio",6,215,{"Electricity"}); tech("Computers",6,250,{"Radio","Combustion"}); tech("SpaceFlight",6,300,{"Computers","Rocketry"})
-- A unit's or building's era is its technology's (1 without one).
for _, rule in units do if rule.technology then rule.era=technologies[rule.technology].era end end
for _, rule in buildings do if rule.technology then rule.era=technologies[rule.technology].era end end
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
-- Strategic resources (G7 quantities): each improved tile supplies `quantity` of the resource, and every living unit
-- needing it uses its `resourceAmount` (1). Saltpeter (gunpowder-era siege and machine guns) and Oil (armour and rocket
-- artillery) are the two later strategic resources.
local resources: {[string]: Resource} = {
    Wheat={id="Wheat",name="Wheat",category="Bonus",quantity=1,yields=yields(1),happiness=0,improvement="Farm"},
    Iron={id="Iron",name="Iron",category="Strategic",quantity=2,yields=yields(0,1),happiness=0,improvement="Mine"},
    Horses={id="Horses",name="Horses",category="Strategic",quantity=2,yields=yields(0,1),happiness=0,improvement="Pasture"},
    Saltpeter={id="Saltpeter",name="Saltpeter",category="Strategic",quantity=2,yields=yields(0,1),happiness=0,improvement="Mine"},
    Oil={id="Oil",name="Oil",category="Strategic",quantity=2,yields=yields(0,1,1),happiness=0,improvement="Well"},
    Gold={id="Gold",name="Gold",category="Luxury",quantity=1,yields=yields(0,0,2),happiness=3,improvement="Mine"},
    Spices={id="Spices",name="Spices",category="Luxury",quantity=1,yields=yields(0,0,1),happiness=3,improvement="Plantation"},
    Deer={id="Deer",name="Deer",category="Bonus",quantity=1,yields=yields(1),happiness=0,improvement="Camp"},
}
local improvements: {[string]: Improvement} = {
    Farm={id="Farm",technology="Agriculture",terrains={"Plains","Grassland"},resources={"Wheat"},turns=2,yields=yields(1),road=false},
    Mine={id="Mine",technology="Mining",terrains={"Hills","Plains","Desert"},resources={"Iron","Gold","Saltpeter"},turns=3,yields=yields(0,1),road=false},
    -- A Well always needs its Oil, like a Pasture its Horses.
    Well={id="Well",technology="Combustion",terrains={"Plains","Desert","Tundra","Hills"},resources={"Oil"},turns=4,yields=yields(0,1),road=false},
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
    -- Units in era order (see the roster above); buildings by era, then the wonders.
    unitOrder=unitOrder,buildingOrder=buildingOrder,wonderOrder=wonderOrder,eras=eras,
    resourceOrder={"Wheat","Deer","Horses","Iron","Saltpeter","Oil","Gold","Spices"},
    policies=policies,policyOrder={"Tradition","Liberty","Honor","Commerce","Rationalism","Patronage"},
    terrains=terrains,terrainYields=terrainYields,features=features,featureOrder={"Forest","Jungle","Marsh","Oasis"},resources=resources,improvements=improvements,improvementOrder={"Farm","Mine","Pasture","Plantation","Camp","Well","Road"},
    -- UpgradeUnit costs max(upgradeMinimumGold, new cost - old cost) x upgradeCostMultiplier gold (upgradeCost is an unused
    -- legacy field, kept for hosts that read it).
    productionCosts=productionCosts,purchaseCosts=purchaseCosts,upgradeCost=40,upgradeMinimumGold=20,upgradeCostMultiplier=2,workerTurns=2,
    cityHp=150,cityBaseYields=yields(2,2,2,2,1),cityWorkRadius=2,foodPerPopulation=2,baseHappiness=9,unhappinessPerCity=2,unhappinessPerPopulation=1,
    growthBase=20,growthPerPopulation=8,starvationLoss=1,unitVision=2,cityVision=2,
    -- Moving between two road tiles costs a third of a move (Civ V), whatever the terrain.
    roadMovement=1/3,
    -- Rivers run along tile edges (the optional tile mask `river`). A tile with a river on any edge yields riverGold more
    -- gold, and a Farm on it riverFarmFood more food (fresh water). A step across a river edge spends all remaining
    -- movement unless both tiles have roads (the road bridges it), and a melee attack across a river loses
    -- riverAttackPercent of its attack (Civ V's -20%).
    riverGold=1,riverFarmFood=1,riverAttackPercent=20,
    -- The science victory needs Space Flight, the last technology (G7; it was Rocketry), and a completed Space Project.
    scienceVictoryTechnology="SpaceFlight",scienceVictoryBuilding="SpaceProject",cultureVictoryPolicies=6,score={city=10,population=3,unit=2,technology=5,policy=5,wonder=10},
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
    -- buildings' defence (Walls, Castle) + garrisonPercent of the defence of a military unit standing in it (rounded
    -- down). The era is the owner's: the highest era among its technologies (1-6).
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
    -- Barbarians (an original, Civ V-flavoured "barbarians-lite"). Their units carry ownerId 0, which no civilization
    -- uses; every civilization is always at war with them, and they have no cities, diplomacy, score or research.
    -- Rounds are scaled by the match pace (the golden-age pace: the round limit against 120 rounds, 50-200%) and by
    -- difficultyPercent: a value of `n` rounds becomes max(1, round(n x pace% x difficulty% / 10000)).
    -- * Encampments. The first may appear at round firstCampTurn and one more every campInterval rounds after it, up
    --   to max(1, min(maxCamps, floor(tiles / tilesPerCamp))) camps (Tiny 1, Small 2, Medium 3, Large 8, Huge 12). A
    --   camp stands on passable land no civilization can see, with no unit or city, at least campCityDistance hexes
    --   from every city and campSpacing hexes from every other camp; tiles neither civilization has explored are
    --   preferred. The tile is chosen deterministically from the seed and the round.
    -- * Units. A new camp starts with a guard. Every spawnInterval rounds a camp adds a unit (on the camp tile if it is
    --   free, which makes that unit its guard, otherwise beside it) while there are fewer than unitsPerCamp barbarian
    --   units per camp and fewer than maxUnits in all. eraUnits lists the kinds for the lower of the two
    --   civilizations' eras (the public era); a guard is always the first kind.
    -- * Behaviour. A unit on a camp tile guards it: it never moves and attacks only from range. Other units hunt the
    --   nearest civilization unit or city within huntRadius hexes and attack when the strike is favourable; without
    --   a target they wander within leashRadius of their nearest camp. They can damage cities but never capture them.
    --   A resting barbarian heals `healing` hit points at the start of its phase.
    -- * Clearing. A civilization's military unit that enters a camp destroys it and earns campGold gold, scaled by
    --   the match pace (rounded down). Experience from fighting barbarians stops at maxExperience (Civ V's cap).
    barbarians={ownerId=0,firstCampTurn=10,campInterval=8,spawnInterval=6,tilesPerCamp=320,maxCamps=12,unitsPerCamp=3,maxUnits=30,
        campCityDistance=4,campSpacing=4,huntRadius=5,leashRadius=4,campGold=25,maxExperience=30,healing=10,
        difficultyPercent={Easy=150,Normal=100,Hard=75},
        eraUnits={{"Warrior","Archer"},{"Spearman","Swordsman","CompositeBowman","Horseman"},{"Pikeman","Longswordsman","Crossbowman","Knight"},{"Musketman","Lancer","Cannon"},
            {"Rifleman","Cavalry","GatlingGun"},{"Infantry","MachineGun","Artillery"}}} :: BarbarianRule,
}
freeze(rules)
return rules





