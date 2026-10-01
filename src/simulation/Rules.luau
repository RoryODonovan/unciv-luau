--!strict
-- SPDX-License-Identifier: MPL-2.0
-- Original synthetic prototype rules; not converted Unciv rules or assets.
-- Provenance-Kind: original
local technologies = {
    {id = "Agriculture", name = "Agriculture", cost = 12, prerequisites = {} :: {string}},
    {id = "BronzeWorking", name = "Bronze Working", cost = 18, prerequisites = {"Agriculture"}},
    {id = "Writing", name = "Writing", cost = 24, prerequisites = {"Agriculture"}},
}
for _, technology in technologies do table.freeze(technology.prerequisites); table.freeze(technology) end
local rules = {
    maxTurns = 40,
    radius = 3,
    productionCosts = table.freeze({Warrior = 12, Settler = 20}),
    technologies = table.freeze(technologies),
    terrainYields = table.freeze({Plains = table.freeze({food = 2, production = 1}), Hills = table.freeze({food = 1, production = 2})}),
    unitStats = table.freeze({Warrior = table.freeze({hp = 100, moves = 2, strength = 10}), Settler = table.freeze({hp = 40, moves = 2, strength = 0})}),
}
return table.freeze(rules)
