# Whole-sphere topology and simulation

`SphereTopology.generate(frequency)` creates a service-independent immutable descriptor: `{frequency, cells}`. Cells are contiguous integer IDs, each with `id`, unit-vector `center = {x,y,z}`, ordered unit-vector `corners`, and sorted integer `neighbors`. Polygon corners are shared frozen vector records. The generator retains at most two immutable descriptors; mutable terrain belongs to individual maps.

The original algorithm subdivides each of twenty fixed icosahedron faces using integer barycentric coordinates, merges exact integer edge keys, projects vertices to the unit sphere, and constructs the dual with outward spherical circumcenters. No spatial rounding or external package determines identity. IDs and corner winding are deterministic in CLI and Roblox Luau. Circumcenters form angular Voronoi boundaries, supporting nearest-angular-center picking. Render triangles as center/corner/next-corner with outward winding. All cells cover the complete closed sphere. Twelve cells are pentagons; all remaining cells are hexagons.

Supported integer frequencies are 1 through 22. Named original sphere presets come from `MapSizes.spherePresets` and `MapSizes.getSphere(name)`:

| Name | Frequency | Cells |
| --- | ---: | ---: |
| Duel | 2 | 42 |
| Tiny | 6 | 362 |
| Small | 8 | 642 |
| Medium | 12 | 1,442 |
| Large | 16 | 2,562 |
| Huge | 22 | 4,842 |

These synthetic sphere frequencies approximate existing hex preset sizes; they are original additions, not converted Unciv sphere rules. Existing `MapSizes.get` hex presets remain unchanged.

`BaseGame.new(seed, {mapShape="Sphere", frequency=22})` uses the entire graph. Sphere state and actor snapshots carry only `mapShape` and `frequency` topology metadata. Sphere tile records contain IDs and gameplay fields, with no planar coordinates, centers, corners, neighbors, or radius. Renderers regenerate public topology locally. Seeded [coherent world generation](world-generation.md) covers every cell with terrain and compatible resources. Separated starting sites share a passable land component and provide useful work tiles and deployment neighborhoods. Travel follows the generated land; no Plains corridor is carved between fixed antipodes. The `WorldMap.sphereStarts` helper remains a geometric antipode utility and does not select new game starts.

Movement uses the existing heap-based weighted graph search. Combat ranges, city radius, founding separation, fog and settler distance thresholds use bounded adjacency BFS. Exact unrestricted distance retains at most eight full BFS rows per map, never an all-pairs matrix; BaseGame retains at most 64 local disks per match. The underlying graph has no longitude seam or special pole rules. Original legacy `Game` and numeric-radius BaseGame behavior remain available.

Sphere saves use explicit `unciv-luau-base` version 2 with `mapShape="Sphere"`, `frequency`, and gameplay state. Version 2 rejects planar coordinates and injected geometry. Loading restores the exact stored terrain/resources without invoking generation. NewGame and Restart use the current generator, so same-seed geography is deterministic within a generator version and can change across upgrades. The separate legacy Game remains unchanged. Existing exact hex version 1 remains supported unchanged; there is no implicit cap-to-globe migration. Validation enforces the existing bounded tree work, tile/unit/city limits, duplicate IDs, terrain/resource compatibility, and game-state invariants before copying. Host products may restrict frequencies further to named presets.

`tests/unit/sphere-topology.luau` independently checks every named size: counts, exactly twelve pentagons, shared three-owner corners and two-owner edges, graph/mesh agreement, outward winding, Euler characteristic two, normalized vectors, equal angular distances at circumcenters, total spherical area 4Ï€, connectivity, poles, antipodes, and stable regeneration after cache eviction. `tests/unit/sphere-game.luau` checks all six sizes, both actor fog projections, no geometry in network/save tables, seeded terrain, connected generated starts, seam movement, round-trip saves, real AI turns, malformed schemas and a 169-unit Huge war.

Run `tools/benchmark-sphere.luau` with the official Luau CLI for cold topology, warm terrain creation, snapshots, saves, restoration, real AI rounds and maximum-unit war snapshots/turns. CLI heap observations depend on garbage collection and do not establish a mobile rendering budget or Roblox frame rate. Rendering and camera behavior belong to the consuming host.

One local Windows Luau CLI run measured Huge cold geometry 318 ms, warm map creation 42 ms, snapshot 19 ms, detached save 42 ms, restore 30 ms, solo round including AI 2.2 ms, and both 169-unit war actor snapshots together 101 ms. Observed cold heap delta was 8,953 KiB before forced collection, so it is not retained-heap evidence. Logical counts are 4,842 cells, 9,680 shared corner vectors, 29,040 neighbor IDs and 29,040 corner references. Exact distance storage is capped at 38,736 numeric distances per map, with at most 64 local disks. These measurements document this desktop run only.

This module and original tests are MPL-2.0 source. The generated `roblox/map/SphereTopology.luau` preserves notices and is reproduced by `tools/roblox-export.mjs`. No upstream implementation or media was copied for sphere topology. See `provenance/sphere-original.json` for source availability and attribution.
