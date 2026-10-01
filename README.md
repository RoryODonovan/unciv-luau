# Unciv Luau

Reusable MPL-2.0 Luau conversions of selected [Unciv](https://github.com/yairm210/Unciv) modules, pinned to `42939c6a2cf31aa76f44ffc033015ad12fece9f5`. This repository is a module library, not a playable Roblox game. The public library includes an original bounded headless simulation; host networking, UI, rendering and persistence adapters are required to build an experience.

## Current scope

| Module | Supported scope |
| --- | --- |
| `src/map/HexCoord.luau` | Immutable coordinates, arithmetic, conversions and parsing |
| `src/map/MapSizes.luau` | Immutable Tiny through Huge hex presets, matching upstream radii 10/15/20/30/40 |
| `src/map/HexMath.luau` | Distances, rings, world conversion, rounding and indexed coordinates |
| `src/map/SphereTopology.luau` | Original closed icosahedral dual sphere, deterministic IDs, twelve pentagons and remaining hexagons |
| `src/map/WorldGeneration.luau` | Original layered continents, coastlines, mountain belts, climate biomes, resource regions and connected viable starting sites |
| `src/models/stats/Stat.luau` | Identifiers, lookup and classifications |
| `src/models/stats/Stats.luau` | Mutable values, copy arithmetic, aggregates and supported parsing |
| `src/models/Counter.luau` | Ordered string-key integer counters and arithmetic |
| `src/simulation/Mechanics.luau` | Attributed partial combat damage and population growth formulas |
| `src/simulation/Game.luau`, `Rules.luau` | Preserved original single-player simulation and legacy saves |
| `src/simulation/BaseGame.luau`, `BaseRules.luau`, `BaseSave.luau`, `WorldMap.luau` | Two-civilization land game: fog, weighted movement, workers, resources, city economy, technology, culture, diplomacy, trade, ranged combat and four victories |

The foundation modules are partial, tested conversions. [Base game API and limits](docs/base-game.md) document the new two-civilization simulation, including actor-specific snapshots and shared-game command authority. [Map and save foundations](docs/base-foundations.md) document its pathfinding and bounded serialization. [World generation](docs/world-generation.md) explains the original geography layers, starting-region guarantees and seed/save compatibility. [Simulation API and limitations](docs/simulation.md) document the original playable headless slice and its legal winning replay. [Hex limitations](docs/hex-conversion.md) and [statistics/counter limitations](docs/stats-conversion.md) list omitted APIs and numeric/platform differences. Tests use upstream-derived expected values and properties; no Kotlin/JVM differential execution or full-game parity is claimed.

The [inventory](docs/dependency-inventory.md) lists 859 upstream files: 232 planned conversions, 215 deferred and 412 excluded. Its baseline statuses do not represent implemented modules. [Architecture](docs/architecture.md) describes the staged roadmap; [integration contracts](docs/integration-contracts.md) distinguish implemented foundations from future interfaces. Every one of the 102 inventoried data/asset files remains unverified and unimported.

## Run the standalone checks

[Whole-sphere API, saves and validation](docs/sphere.md) cover the six sphere presets, complete globe topology and graph-based BaseGame option. `BaseGame.new(42, {mapShape="Sphere", frequency=22})` creates Huge with 4,842 cells; sphere saves use explicit version 2, while legacy hex version 1 remains supported.

Install Node.js 22+ and the official [Luau CLI 0.740](https://github.com/luau-lang/luau/releases/tag/0.740). No npm dependency installation or Roblox account is needed.

```sh
npm run test:tooling
npm run test:export
npm run check
npm run check:roblox
```

If Luau is not on PATH, set `LUAU_BIN` and `LUAU_ANALYZE_BIN` to the executable paths. The tests currently include 124,497 hex assertions plus statistics and counter scenarios. CI uses the same pinned Luau release and verifies its ZIP checksum.

## Roblox module form

`roblox/` contains generated ModuleScript source only. These files retain MPL notices and reproduce from `src/` using the public exporter:

```sh
npm run export:roblox
npm run check:roblox
```

The exporter adapts static relative requires to ModuleScript references while preserving comments and strings. It is a deliberately limited module packager, not a general Luau transpiler; current source uses direct static imports. The generated manifest records source and output hashes. There is no playable place, bootstrap, network transport, UI or private script in this repository. Other developers are free to implement their own integrations under the licence terms.

## Licensing and provenance

See [LICENSE](LICENSE), [ATTRIBUTIONS.md](ATTRIBUTIONS.md), `upstream.lock.json`, and per-module records in `provenance/`. Preserve upstream notices. Converted covered code and shipped modifications remain MPL-2.0; a private integration folder does not remove source-availability obligations. No upstream media or complete rules datasets are distributed. This independent adaptation is not endorsed by Unciv, Roblox or the owners of Civilization.

