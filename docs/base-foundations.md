# Original base foundations

`BaseRules`, `WorldMap`, and `BaseSave` are original MPL-2.0 systems for the bounded civilization base game. They use the separately attributed `HexMath` coordinate distance; their map generation, balance, paths, projections, and validation are not converted Unciv systems. No full Unciv gameplay parity is claimed.

## Rules

The deeply frozen rule tree defines eleven unit kinds, sixteen technologies, eleven buildings, six policies, six resources, and six improvements. Unit and building maps expose production and purchase costs, maintenance, prerequisites, and yields. Resources distinguish bonus, strategic, and luxury benefits. The numeric balance is synthetic and intended for small deterministic matches, with radius 3 through 7 (37 through 169 tiles), 20 through 500 rounds (120 by default), and population capped at 100 per city. Science victory requires Rocketry and SpaceProject; the engine owns evaluation of these rules.

## Indexed maps and movement

`WorldMap.generate(seed, radius)` returns `{radius, tiles, index, neighbors}`. IDs correspond to array indexes. Coordinates use the pinned HexMath skew hex convention; the six offsets are `(1,0)`, `(0,1)`, `(1,1)` and their opposites. `fromTiles(tiles, radius)` builds fresh topology indexes around the supplied mutable tile array. Indexes and neighbors are derived runtime caches, excluded from saves.

`shortestPath(map, start, goal, cost?)` returns a path including both endpoints and its total cost, or two nil values when blocked. `reachable(map, start, budget, cost?)` returns minimum costs, including the starting tile at zero. The cost callback receives `(fromId, toId)`. Costs apply to entering a tile, must be positive finite numbers, and nil blocks passage. Default movement rejects water and mountains, charges two for hills and forests, one elsewhere, and one on roads. Dijkstra uses a bounded scan over at most 169 nodes; ties resolve by ascending tile ID. Deterministic generation uses integer Park-Miller arithmetic, not platform random services. A plains spine connects opposite central starting areas; maps are not tectonic or historically realistic.

`visibility(map, centers, range)` returns ascending visible tile IDs. It is geometric range without line-of-sight occlusion. `projectTiles(map, discovered, visible)` returns detached presentation data: unknown tiles reveal only coordinates/ID and fog flags; discovered tiles additionally reveal terrain/resources; currently visible tiles additionally reveal owner/improvement/road. Explored terrain/resources are static knowledge; it does not maintain historical ownership snapshots. The engine separately filters units, cities, events, legal commands, and private player information.

## Validation boundary

`BaseSave.valid(save)` checks the exact versioned state schema before recursive copying. `serialize(state)` validates then returns detached data; `restore(save)` returns detached state or nil and an error. Unknown fields, invalid references, unsupported versions, metatables, nonfinite numbers, unsupported values, cycles, shared table references, sparse arrays, and out-of-budget trees are rejected. The format is `unciv-luau-base`, version 1, distinct from the unchanged legacy simulation save.

Tests cover deep immutability, map determinism and topology, weighted optimality against an independent Bellman-Ford oracle, unreachable maps, bounded map settings, and fog field disclosure. Save tests exercise detached data and corrupt trust-boundary inputs.

