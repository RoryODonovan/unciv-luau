--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original synthetic prototype rules; not converted Unciv rules or assets.
-- Provenance-Kind: original
local technologies = {
    {id = "Agriculture", name = "Agriculture", cost = 12, prerequisites = {} :: {string}},
    {id = "BronzeWorking", name = "Bronze Working", cost = 18, prerequisites = {"Agriculture"}},
    {id = "Writing", name = "Writing", cost = 24, prerequisites = {"Agriculture"}},
    {id = "Masonry", name = "Masonry", cost = 22, prerequisites = {"Agriculture"}},
    {id = "Engineering", name = "Engineering", cost = 36, prerequisites = {"Masonry", "BronzeWorking"}},
}
for _, technology in technologies do table.freeze(technology.prerequisites); table.freeze(technology) end
local rules = {
    maxTurns = 40,
    radius = 3,
    productionCosts = table.freeze({Warrior = 12, Settler = 20, Scout = 9, Granary = 16, Workshop = 22, Library = 20}),
    purchaseCosts = table.freeze({Warrior = 48, Settler = 80, Scout = 36, Granary = 64, Workshop = 88, Library = 80}),
    upgradeCost = 30,
    buildingEffects = table.freeze({Granary = table.freeze({food = 2}), Workshop = table.freeze({production = 2}), Library = table.freeze({science = 3})}),
    technologies = table.freeze(technologies),
    terrainYields = table.freeze({Plains = table.freeze({food = 2, production = 1}), Hills = table.freeze({food = 1, production = 2}), Forest = table.freeze({food = 1, production = 2})}),
    unitStats = table.freeze({Scout = table.freeze({hp = 60, moves = 3, strength = 0}), Warrior = table.freeze({hp = 100, moves = 2, strength = 10}), Settler = table.freeze({hp = 40, moves = 2, strength = 0})}),
}
return table.freeze(rules)
