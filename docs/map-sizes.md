# Hex map sizes

`src/map/MapSizes.luau` adapts the ordered names and radii from Unciv's pinned `MapSize.Predefined` enum. Its immutable `presets` records contain `name`, `radius`, and `tileCount`; `get(name)` returns the exact named record or nil (case-sensitive).

| Preset | Radius | Hex tiles |
| --- | ---: | ---: |
| Tiny | 10 | 331 |
| Small | 15 | 721 |
| Medium | 20 | 1,261 |
| Large | 30 | 2,791 |
| Huge | 40 | 4,921 |

`BaseGame.new(seed, {radius=MapSizes.get("Medium").radius})` creates the complete radius-20 hexagon. The base game accepts all integer radii 3–40; its existing radius-4 default and radius-3–7 games/saves are preserved. The same version-1 radius field identifies saved size. The legacy `Game`, `Rules`, and `Save` retain their smaller original bounds.

Only hexagonal scale matches these Unciv presets. Rectangular dimensions, wrapping, Auto/Custom size behavior, civilization counts and size-based technology/policy modifiers are omitted. This remains the original two-civilization land simulation. Total entity limits stay at 169 units and 24 cities regardless of map size, and the round limit remains 20–500. Larger maps do not automatically increase armies, opponents, victory pacing or simulation scope.

Heap Dijkstra retains ascending tile-ID resolution for equal costs; local visibility queries avoid a full map scan per center. Snapshot attack lists inspect occupied tiles rather than every map tile per unit. Save validation keeps exact schema/entity limits and a bounded 81,920-entry traversal budget (65,536 before terrain features and rivers), sufficient for every tile field and both fully explored Huge maps.

## CLI measurements

Run `luau tools/benchmark-map-sizes.luau` with the official Luau 0.740 CLI. It measures complete generation, paths between the generated starting sites (fixed opposite coordinates can be separated by water or mountains on coherent maps), detached actor snapshots, real solo rounds including AI, and detached save-table validation/copy/restore. It does not measure Roblox rendering, JSON encoding, network transfer, storage or client hardware. No runtime performance threshold is asserted by tests.

A Windows run on 2026-10-01 after the changes measured:

| Operation | Radius 7 | Huge (40) | Huge with 169 total units |
| --- | ---: | ---: | ---: |
| Generation | 0.41 ms | 14.40 ms | — |
| Opposite-start path | 0.21 ms | 10.56 ms | — |
| Snapshot | 0.18 ms | 1.86 ms | 4.98 ms |
| Solo round including AI | 0.43 ms | 1.20 ms | 2.17 ms |
| Save table serialization | 0.44 ms | 13.60 ms | 14.79 ms |
| Save table restoration | 0.66 ms | 26.87 ms | 28.73 ms |

Generation uses 10 samples, paths 3, snapshots and rounds 20, and saves 5. The stress fixture has a human capital, AI rival and 167 human units spread over passable tiles, with sufficient treasury to preserve the unit limit across the sampled rounds. Stress saves are measured after those rounds. Timings vary between runs; use the checked-in benchmark on the target host. Before heap/candidate changes, a Huge opposite-start path took about 652 ms and the 169-unit snapshot about 36 ms in the same CLI environment.

Tests generate each complete preset, preserve legacy sizes, compare paths with an independent scan oracle, verify geometric vision against a full-map oracle, round-trip fully populated Huge save tiles/exploration, reject oversized/corrupt inputs, prove fog non-disclosure and detachment, and run 20 actual solo rounds at the 169-unit limit.

See `provenance/map-sizes.json` for the immutable upstream source and scoped omissions. The inventory baseline remains unchanged; the new implemented scope is recorded separately in that fragment and `provenance/source-map.json`.
