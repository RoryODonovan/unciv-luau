# Architecture and roadmap

The public project is a standalone Luau simulation library. It has no playable Roblox place, entrypoint, networking, UI, persistence service or proprietary dependency. Its individual modules can be tested using the official Luau CLI. The private integration is independently authored and kept in a separate repository outside this Git tree.

## Public/private boundary

Public: every converted Unciv implementation, its covered modifications, provenance, tests, types and integration contracts. Private: Roblox service adapters, bootstrap, match orchestration, validation at the player/network boundary, replication, rendering, input, UI, persistence operations and deployment configuration. Generic action legality, gameplay visibility and turn rules derived from upstream remain public when converted.

Public interfaces are documented; other developers can implement their own adapters. No licence restriction prohibits Roblox reuse. Public modules are intentionally a library rather than an immediately playable game. Missing upstream functions are documented, not hidden as private functionality.

## Conversion order

1. Pin upstream, inventory relevant files and import edges, preserve licensing and build provenance.
2. Convert foundations: HexCoord/HexMath, Stats/Stat and Counter.
3. Define ruleset schemas, references, filters, conditional effects and supported-feature validation. Unsupported effects must fail clearly.
4. Convert world model, map queries, topology, visibility, terrain/resource logic, movement and pathfinding; add generation separately.
5. Convert unit actions, improvements, promotion, combat calculations and resolution, including rule dependencies.
6. Convert city founding, population, worked tiles, yields, borders and construction.
7. Convert civilization research, economics, policies, turn transitions, diplomacy, trade and victory conditions.
8. Convert advanced rules such as religion, city-state quests, espionage, events and other inventoried features.
9. Convert automation with bounded decision budgets and legal-action checks; add integration scenarios and release profiles.

Only step 2's supported foundation subsets are part of the initial setup milestone. The inventory identifies planned/deferred/excluded files; it is not a claim that those systems have been ported.

## Data and determinism

Use strict Luau, plain tables, stable entity IDs and explicit state ownership. Separate serialization data from transient caches and runtime references. Randomness, rules access and side effects are supplied through documented interfaces. Do not assume Kotlin and Luau have identical RNG, float precision, integer division, modulo, rounding, unordered iteration or null semantics. Preserve behaviour where tested and disclose differences otherwise. Engine IDs must not be Roblox Instance references.

## Acceptance gates

A converted module needs provenance and notices, documented supported/omitted APIs, passing runtime tests, static analysis, and upstream-referenced expected behaviour or independently justified properties. Whole-game parity, native Unciv save import and full rules support remain unclaimed. No production credentials or player data are needed for public CI.
