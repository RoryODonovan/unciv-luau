# Original bounded strategy simulation

`src/simulation/Game.luau`, `Rules.luau`, and `Save.luau` are original public MPL-2.0 systems. They use attributed HexMath and two partial formula extractions in Mechanics. This is a playable headless strategy prototype, not a conversion of Unciv's full gameplay, AI, ruleset, save format, or assets. The private host owns rendering, authentication, transport and storage. All gameplay and rule definitions documented here are public covered source.

## API

- `Game.new(seed: number?, options: Options?) -> State`: default seed 1, difficulty `Easy`, radius 3 and no forest. Seed is an integer within binary64's exact integer range. Options accept `difficulty = "Easy" | "Normal" | "Hard"`, `radius = 3..5` (integer), and optional `forest = true`. Radius 3 has 37 tiles, radius 4 has 61, and radius 5 has 91. Defaults preserve the seed-1 round-10 winning replay.
- `Game.apply(state, actorId, command) -> {ok, message}`: actor 1 submits commands; actor 2 is automatic AI. Rejected commands leave all state unchanged; accepted commands increment revision once. Unit, tile and city identifiers must be finite positive integers. Unknown commands and malformed identifiers reject without throwing.
- `Game.snapshot(state, actorId) -> View`: detached plain projection with full map visibility; actors 1 and 2 accepted. No fog of war. `legalMoves[tostring(unitId)]` lists currently valid destination tile IDs for that actor's units using the same core validator as commands. Attack destinations appear only for warriors; forest costs and remaining movement are included. Finished games have no legal destinations.
- `Game.serialize(state) -> Saved`: synchronously deep copies validated server state. Invalid internal state raises an assertion. No host service or JSON encoder is used.
- `Game.restore(saved: any) -> (State?, error?)`: rejects unsupported/corrupt data with `nil, "Unsupported or corrupt simulation save."`; success returns a detached state and nil error. Never mutates its input.
- `Game.getRules()`: recursively frozen synthetic rule summary, including `productionCosts`, `purchaseCosts`, `buildingEffects`, `unitStats`, `terrainYields` and technologies.

Commands use `kind`: `MoveUnit {unitId,tileId}`, `FoundCity {unitId}`, `SetProduction {cityId,item}`, `Research {technology}`, `EndTurn`, `FortifyUnit {unitId}`, `UpgradeUnit {unitId}`, and `Purchase {cityId,item}`. All unit/city commands enforce ownership. Purchases validate funds and a valid free deployment tile before spending gold. Repeat purchases of units are allowed when affordable; buildings and upgrades are once per entity. Repeating an already selected production/research or an already fortified warrior rejects. Commands do not accept client balance, damage, movement or researched-state fields.

View retains `turn`, `revision`, `phase` (`Playing`/`Finished`), optional `winner`/`reason`, actor's cumulative `gold`/`science`, optional `research {id,progress,cost}`, owned technology IDs, `tiles {id,x,y,terrain,ownerId?,food,production}`, `units {id,ownerId,kind,tileId,hp,moves,fortified,level}`, `cities {id,ownerId,tileId,name,population,food,production,queue,hp,buildings}`, bounded log strings, `availableProduction`, `availableResearch`, and objectives. City food/production are stored progress. Coordinates follow Unciv HexMath rather than generic axial coordinates.

Additive fields are `seed`, `difficulty`, `legalMoves`, detached `productionCosts`/`purchaseCosts`, two-player `scores`, `statistics` (each player's `cities`, `units`, `population`, `technologies` counts) and up to 32 events. Events have monotonically increasing `id`, `kind`, `message`, optional `tileId`, `unitId`, `ownerId`, `amount`. Kinds are `Move`, `Attack`, `FoundCity`, `Production`, `Research`, `Growth`, `Victory`, `Defeat`, `Purchase`, `Upgrade`. Events are presentation history, not replay commands; hosts may fall back to snapshot changes for actions such as fortification. `amount` means attack damage, purchase gold spent, or grown population where present.

## Synthetic rules

| Item | Production | Purchase gold | Effect |
|---|---:|---:|---|
| Warrior | 12 | 48 | 100 HP, 2 movement, strength 10 |
| Settler | 20 | 80 | 40 HP, 2 movement; consumed by founding |
| Scout | 9 | 36 | 60 HP, 3 movement; cannot attack/found/fortify/upgrade |
| Granary | 16 | 64 | Once per city; +2 food per round |
| Workshop | 22 | 88 | Once per city; +2 production per round |
| Library | 20 | 80 | Once per city; +3 science per round |

All terrain is passable. Plains yield 2 food/1 production, hills and optional forest 1 food/2 production. Forest costs two movement for a peaceful move; an attack spends remaining movement as elsewhere. One unit occupies a tile. Warriors attack adjacent enemies by moving into them; simultaneous damage may kill both. A city reduced to zero HP by a dying attacker remains uncaptured and may heal or be captured on a later action. A surviving warrior captures a defeated city after clearing its garrison. Settlers found cities at least two tiles from existing cities. Claims extend one ring with existing ownership retained except when capture transfers its ring. Production creates at most one item per city per round; blocked unit deployment delays production without spending stored work. Purchased units start with zero movement. Completed building production switches to Warrior; buying the currently queued building also clears that queue, while purchasing other items retains the chosen queue.

Fortification consumes a warrior's remaining movement, grants +3 defensive strength and heals 16 rather than 8 at the following human turn, when eligible for ordinary healing. It persists until moving or attacking, grants no attack bonus, and does not heal immediately. Upgrade costs 30 gold, requires Bronze Working and applies once to a Warrior (`level=1`); it adds +3 strength without changing its kind or movement.

Cities work a deterministic population-limited set of claimed neighboring tiles with original base yields. Switching research discards progress; switching production retains work. Science totals are cumulative; progress receives per-city science and completion discards excess. City healing is 5 per round, or 8 with Masonry. There are no resources, maintenance, starvation, ranged combat, diplomacy or hidden information.

| Technology | Science | Prerequisites | Bonus |
|---|---:|---|---|
| Agriculture | 12 | none | +1 food/city |
| BronzeWorking | 18 | Agriculture | +3 warrior strength; permits upgrade |
| Writing | 24 | Agriculture | +2 science/city |
| Masonry | 22 | Agriculture | City healing 8 rather than 5 |
| Engineering | 36 | Masonry, BronzeWorking | +1 production/city |

EndTurn resolves human economy, AI research/economy/actions, victory checks, then human movement and healing. Easy AI takes one movement point and half production; Normal uses full production and one movement; Hard uses full production and two movement actions. Normal/Hard prioritize nearby vulnerable enemy units and fortify/heal below 45 HP. These are deterministic original planning heuristics with no unseen information, extra gold, damage multipliers or AI-only technologies. They are not Unciv AI. Easy's original behavior remains stable.

The 40th round ends by score: city 10 + population*3, unit 2, technology 5; ties favor AI. Capturing the original rival capital wins immediately; having no human city or settler loses.

## Save contract and trust boundary

Version 1 saves are `{format="unciv-luau-original", version=1, state=<plain State>}`. Only this exact format/version is accepted; there is no upstream Unciv save compatibility or migration promise. State includes scenario options, both players, map/entities, counters, bounded logs/events, turn/revision and outcome. JSON object keys are strings; array keys are contiguous positive integers; optional nil fields may be omitted. Data contains no functions, metatables, host objects or cyclic references.

Validation rejects unexpected keys, missing required fields, sparse/oversized arrays, non-finite/fractional/out-of-range numbers, unknown terrain/items/technologies/events, invalid owners, duplicate entity IDs or unit occupancy, missing tile references, impossible map coordinates/count, duplicate coordinates, invalid yield/stat values, duplicate buildings, owned queued buildings, missing technology prerequisites, invalid research progress/cost, inconsistent city ownership and invalid counters/outcomes. Restored state and exported saves share no mutable tables with their source. The public module cannot authenticate storage: the host must restore only its own trusted server-side stored records, never arbitrary client-supplied saved state. Storage keys, budgets, failures and per-player ownership are the host's responsibility.

## Verification and limits

`tests/winning-replay.luau` supplies 30 legal commands ending in capital capture on turn 10. Tests run the replay deterministically, serialize/restore it throughout, and compare all later snapshots. Release tests cover 18 seeded matches across all difficulties, radii and optional forest, advertised legal destinations, isolated economy/building/purchase/upgrade/fortification effects, detached save copies, malformed commands and corrupt schema cases. Controlled internal fixtures isolate rules; they are not exposed as public commands. Broader strategic balance and Studio presentation still require playtesting; a passing synthetic replay does not establish full-game parity.

Mechanics extracts only upstream `BattleDamage.damageModifier` and the base `CityPopulationManager.getFoodToNextPopulation` formula at revision `42939c6a2cf31aa76f44ffc033015ad12fece9f5`. Speed/difficulty/city-state modifiers are omitted. Luau uses binary64. Combat fixes randomness to 0.5 and applies original health scaling/rounding. Formula tests establish source-derived expectations; the surrounding simulation is original work.
