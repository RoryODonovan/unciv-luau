# Bounded synthetic simulation

`src/simulation/Game.luau` is an original, public MPL-2.0 playable headless prototype. It uses the attributed HexMath conversion and two partial formula extractions in Mechanics. It is not a conversion of Unciv's full game, AI, ruleset, combat orchestration, or assets. The private host owns rendering, authentication, transport, and restarting by replacing state.

## API

- `Game.new(seed: number?) -> State`: finite integer seed, default 1; deterministic 37-tile hex map. State is server-owned mutable simulation data, never client-supplied.
- `Game.apply(state, actorId, command) -> {ok, message}`: actor 1 alone submits commands; actor 2 is automatic AI. Rejections leave state unchanged; accepted commands increment revision once.
- `Game.snapshot(state, actorId) -> View`: detached JSON-friendly projection, full map visibility; actors 1 and 2 accepted. No fog-of-war claim.
- `Game.getRules()`: recursively frozen synthetic rule summary.

Commands use `kind`: `MoveUnit {unitId,tileId}`, `FoundCity {unitId}`, `SetProduction {cityId,item}`, `Research {technology}`, `EndTurn`. IDs are numbers. Items are `Warrior` and `Settler`; technologies are `Agriculture`, `BronzeWorking`, `Writing`.

View fields: `turn`, `revision`, `phase` (`Playing` or `Finished`), optional `winner`/`reason`, actor's cumulative `gold`/`science`, optional `research {id,progress,cost}`, owned `technologies` string IDs, `tiles {id,x,y,terrain,ownerId?,food,production}`, `units {id,ownerId,kind,tileId,hp,moves}`, `cities {id,ownerId,tileId,name,population,food,production,queue,hp}`, bounded `log` strings, `availableProduction` string items, `availableResearch {id,name,cost,prerequisites}`, and `objectives` strings. City food and production are stored progress. Coordinates follow Unciv HexMath, not generic axial coordinates.

## Deliberately simplified rules

All plains/hills are passable, one unit occupies a tile, movement is adjacent and costs one point. Warriors attack by moving into enemies; attacks spend remaining movement. Simultaneous damage may kill both parties. A surviving warrior captures a defeated city after clearing its garrison. Settlers found cities at least two tiles away from existing cities and are consumed. Claims extend one ring, with existing ownership retained except when capture transfers its ring. There is no diplomacy, resources, maintenance, starvation, ranged combat, upgrades, buildings, or hidden information.

Cities work a deterministic population-limited set of claimed neighboring tiles, with original base yields. Agriculture increases food; Bronze Working increases warrior strength; Writing increases science. Switching research resets its progress; switching production retains stored work. One unit can complete per city per round; occupied spawn tiles delay completion. Science totals are cumulative and research progress receives per-city science; excess research progress is discarded. Gold is a score/display balance without purchases.

EndTurn resolves human economy, AI research/economy and attacks, then human movement and healing. The intentionally easy AI uses one movement point and half production; human warriors have two movement points and heal eight per round. City healing is five. All balance values and greedy AI are original synthetic design, not Unciv balance or AI. The 40th round ends by score: city 10 + population*3, unit 2, technology 5; ties favor AI. Capturing the original AI capital wins immediately; no human city or settler loses.

Mechanics extracts only upstream `BattleDamage.damageModifier` and the base `CityPopulationManager.getFoodToNextPopulation` formula at revision `42939c6a2cf31aa76f44ffc033015ad12fece9f5`. Speed/difficulty/city-state modifiers are omitted. Luau uses binary64. Prototype combat fixes randomness to 0.5 and applies explicitly original health scaling and rounding. Tests establish source-derived formula expectations and prototype behavior, not whole-game parity.

## Legal replay

`tests/winning-replay.luau` contains a seed-1 sequence of 30 commands ending in human capital-capture victory on turn 10. `tests/unit/simulation.luau` runs it twice through the public API without state mutation and compares every snapshot. The same commands can be submitted through the private host for Studio QA. Other tests exercise invalid commands, detached snapshots, economy/research/production, legal inaction loss, and an isolated internal fixture for the 40-round boundary.
