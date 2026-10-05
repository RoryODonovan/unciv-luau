# G15: military and civilian stacking

The original `BaseGame` now supports one military unit and one civilian unit of the same owner on a tile. `BaseRules.units[kind].unitClass == "Civilian"` defines the civilian slot; every other class uses the military slot, including Scouts and ranged units. Different owners cannot share a tile. This applies on Hex and Sphere maps.

## Occupancy audit and change

Before G15, `BaseGame.occupants` retained only the last unit on each tile. Movement, its Dijkstra search, legal destinations and move previews blocked every other unit, even friendly Workers and Settlers. `BaseSave` rejected any repeated unit tile. City production and purchase searched the city plus its immediate neighbors in ascending tile ID order for an entirely empty tile; the city was not preferred. A lone civilian took ordinary combat damage and was destroyed on reaching zero HP; there was no civilian ownership transfer.

Now movement can end on a friendly unit of the other class. Friendly same-class tiles can be traversed but never selected as destinations, even with movement left. A step exhausting movement through terrain cost, an unbridged river, a camp or zone of control cannot pass through a filled class slot. The command, AI, snapshots, river destinations and on-demand move previews share the same search and ending checks. Intermediate occupied tiles remain in the preview path. Existing visibility, terrain, borders and movement costs still apply.

Production and purchase prefer the city when the new unit's class slot is free. Otherwise the existing adjacent fallback remains, ordered by tile ID, with the same terrain, territory, city and camp restrictions. There is no wider deployment search: if the city and its neighbors have no legal slot, production reports `NoSpace` and purchase refuses. Forecasts account for the class of units projected to complete earlier in the same economy step.

Founding removes only the Settler, leaving its military companion as garrison. Existing upgrades keep the military slot. The military occupant supplies city garrison strength, flanking and zone of control regardless of the order of units in state. Workers supply none of these. Embarkation, naval units and Great People are not implemented by this ruleset; there is no embark transition to audit.

The separate legacy synthetic `Game`/`Rules`/`Save` prototype still uses its original single-unit occupancy and adjacent-only movement. It has no Worker or Civ V combat-class model and is not the `BaseGame` rules API covered by G15. Its existing regression suites and saves remain unchanged.

## Combat and capture

A stacked military unit always defends against unit attacks and city strikes. Naming the protected civilian's unit ID cannot bypass that defender in `CityRangedStrike` or its preview. A civilian takes no damage and cannot be captured while the military unit survives. A ranged kill leaves the civilian in place with its original owner.

A surviving civilization melee attacker that defeats the military defender and legally advances captures the civilian too. An unprotected civilian outside a city is captured immediately, without damage, retaliation or experience. A Worker changes owner; a Settler becomes a Worker. The captured unit keeps its ID and HP (bounded by the resulting kind's maximum), has zero movement, and loses work, sentry, fortification and experience/promotion orders. Both units then occupy the destination. The old owner receives the retained `UnitLost` event with `cause="Captured"`, original kind and a capture message; the new owner receives `Capture`. No new event kind is needed.

A city also protects its civilian. A civilian alone in a city is not a combat defender; attacks hit the city. Defeating a military garrison while the city survives does not permit advance or civilian capture. On city capture its civilian is captured as well. Existing city combat, capture and garrison bonuses are otherwise unchanged.

Known Civ V differences retained: lone civilians can still be damaged/killed by ranged unit attacks and city strikes. Barbarians still destroy civilians rather than owning them; barbarian saves permit military units only. No escort AI was added. These are explicit limitations, not a claim of full Civ V parity. The previous damage-and-destruction behavior for civilization melee attacks on civilians was changed deliberately to implement capture consistently for both lone and stacked targets. No external Civ V reference or private client was accessed in this offline work order.

## Snapshot and save compatibility

`units` remains the array of unit records keyed by each record's stable `id`, with both visible units sharing `tileId`. `TileView` has no single-unit field, so no field is removed or versioned. `legalMoves`, `riverMoves`, `attackPreviews`, city `strikeTargets`, `cityStrikePreviews` and `previewMove` retain their shapes and now reflect class occupancy/protection.

`AttackPreview` adds optional `civilianUnitId` and `capturesCivilian` (`"Yes"`, `"No"` or `"Maybe"`) when the visible target tile contains a civilian. Existing `captures` still means city capture; existing `defenderHp` and damage describe the selected military defender or city. For a lone melee civilian capture, damage is zero, `defenderDefeated="Yes"` means neutralized by capture, and `advances=true`. Protected civilians use `capturesCivilian="No"` until the attacker can advance; hidden city defense can give `"Maybe"`. These additions disclose only visible units and preserve existing fields. Hosts must render all records in `units` on a tile; a private client assuming unique `tileId` needs its own renderer update. That client is not present in this public checkout and was not inspected.

Save format and versions stay unchanged: Hex version 1, Sphere version 2. Old valid single-unit saves remain valid. The validator additionally accepts opposite-class pairs of one owner, and rejects repeated classes, three units or mixed owners. An older engine reader still rejects newly stacked saves; backward loading compatibility does not imply forward-reader compatibility.

## Verification and replay changes

`tests/unit/base-stacking.luau` covers both movement directions, military-class grouping, refusal, transit and forced stops, protection and capture in both unit-array orders, ranged protection, city strike ID validation, per-class production/purchase/fallback/menus/forecasts, founding, garrison, upgrades and save validation/round trips on both map shapes. Existing movement references now independently permit friendly transit and filter destinations by class. Existing blocked-production fixtures fill military slots. Civilian combat sweeps and loss-event fixtures assert capture rather than destruction.

The full 48-game golden corpus is deliberately regenerated for changed placement, movement and combat rules. The per-game checkpoint and result comparison follows below; initial differences in actor projections can precede state differences because additional legal destinations are visible immediately. The replay driver, seeds, balance constants and canonical hash encoder are unchanged.

All 48/48 games change checkpoint hashes; 32/48 change the final victory type, winner or round. This table compares base `964645c` with G15. A disposable offline audit ran both public versions under the same replay driver through their first state divergence: the second column identifies the first differing unit placement or movement. Deployment differences are caused by city-first class slots; route differences follow expanded friendly destinations/transit. Later combat, protection and civilian capture can compound those changes. The table does not attribute an eventual victory to a single earlier move. Initial state hashes remain unchanged; initial actor differences reflect expanded legal moves and optional visible-civilian preview fields.

| Game | First state divergence (completed round, unit) | First changed state checkpoint | First changed P1 / P2 view | Before: victory, round | G15: victory, round |
| --- | --- | --- | --- | --- | --- |
| Quick/Hex/seed-7919/barbarians-on | R3: AI route: Warrior #4 tile 220 -> 254; moves 0 -> 1 | round-10 | initial / round-10 | Culture (P2), 45 | Culture (P2), 40 |
| Quick/Hex/seed-15838/barbarians-off | R2: Deployment: Warrior #6 tile 27 -> 28; moves 2 -> 2 | round-10 | initial / round-10 | Score (P2), 45 | Score (P2), 45 |
| Quick/Hex/seed-23757/barbarians-on | R2: Deployment: Warrior #6 tile 164 -> 165; moves 2 -> 2 | round-10 | initial / round-10 | Score (P2), 45 | Score (P2), 45 |
| Quick/Hex/seed-31676/barbarians-off | R3: Deployment: Warrior #6 tile 108 -> 109; moves 2 -> 2 | round-10 | initial / round-10 | Culture (P2), 45 | Culture (P2), 44 |
| Quick/Hex/seed-39595/barbarians-on | R3: Deployment: Warrior #6 tile 106 -> 107; moves 2 -> 2 | round-10 | initial / round-10 | Domination (P2), 33 | Domination (P2), 45 |
| Quick/Hex/seed-47514/barbarians-off | R1: AI route: Warrior #4 tile 61 -> 49; moves 0 -> 0 | round-10 | initial / round-10 | Score (P2), 45 | Score (P2), 45 |
| Quick/Hex/seed-55433/barbarians-on | R3: Deployment: Warrior #6 tile 89 -> 90; moves 2 -> 2 | round-10 | initial / round-10 | Culture (P2), 43 | Culture (P2), 43 |
| Quick/Hex/seed-63352/barbarians-off | R3: Deployment: Warrior #6 tile 243 -> 244; moves 2 -> 2 | round-10 | initial / round-10 | Culture (P2), 45 | Culture (P2), 44 |
| Quick/Sphere/seed-7919/barbarians-on | R2: AI route: Warrior #4 tile 162 -> 156; moves 0 -> 0 | round-10 | initial / round-10 | Culture (P2), 40 | Culture (P2), 40 |
| Quick/Sphere/seed-15838/barbarians-off | R2: Deployment: Warrior #6 tile 148 -> 149; moves 2 -> 2 | round-10 | initial / round-10 | Culture (P2), 44 | Culture (P2), 45 |
| Quick/Sphere/seed-23757/barbarians-on | R2: Deployment: Warrior #6 tile 262 -> 267; moves 2 -> 2 | round-10 | initial / round-10 | Culture (P2), 45 | Culture (P2), 45 |
| Quick/Sphere/seed-31676/barbarians-off | R3: Deployment: Warrior #6 tile 327 -> 328; moves 2 -> 2 | round-10 | initial / round-10 | Score (P2), 45 | Score (P2), 45 |
| Quick/Sphere/seed-39595/barbarians-on | R3: Deployment: Warrior #6 tile 22 -> 23; moves 2 -> 2 | round-10 | initial / round-10 | Domination (P2), 42 | Domination (P2), 45 |
| Quick/Sphere/seed-47514/barbarians-off | R4: Deployment: Warrior #6 tile 93 -> 95; moves 2 -> 2 | round-10 | initial / round-10 | Culture (P2), 42 | Culture (P2), 42 |
| Quick/Sphere/seed-55433/barbarians-on | R2: AI route: Warrior #4 tile 120 -> 114; moves 0 -> 0 | round-10 | initial / round-10 | Score (P2), 45 | Score (P2), 45 |
| Quick/Sphere/seed-63352/barbarians-off | R3: Deployment: Warrior #6 tile 335 -> 339; moves 2 -> 2 | round-10 | initial / round-20 | Score (P2), 45 | Score (P2), 45 |
| Standard/Hex/seed-7919/barbarians-on | R2: Deployment: Warrior #6 tile 595 -> 596; moves 2 -> 2 | round-10 | initial / round-20 | Science (P2), 69 | Science (P2), 67 |
| Standard/Hex/seed-15838/barbarians-off | R2: Deployment: Warrior #6 tile 57 -> 58; moves 2 -> 2 | round-10 | initial / round-10 | Science (P2), 69 | Science (P2), 69 |
| Standard/Hex/seed-23757/barbarians-on | R1: AI route: Warrior #4 tile 421 -> 394; moves 0 -> 0 | round-10 | initial / round-10 | Science (P2), 67 | Science (P2), 71 |
| Standard/Hex/seed-31676/barbarians-off | R4: Deployment: Warrior #6 tile 95 -> 96; moves 2 -> 2 | round-10 | initial / round-10 | Science (P2), 66 | Science (P2), 66 |
| Standard/Hex/seed-39595/barbarians-on | R2: Deployment: Warrior #6 tile 300 -> 301; moves 2 -> 2 | round-10 | initial / round-10 | Science (P2), 72 | Science (P2), 75 |
| Standard/Hex/seed-47514/barbarians-off | R2: Deployment: Warrior #6 tile 101 -> 102; moves 2 -> 2 | round-10 | initial / round-10 | Culture (P2), 75 | Culture (P2), 72 |
| Standard/Hex/seed-55433/barbarians-on | R5: Deployment: Warrior #6 tile 217 -> 218; moves 2 -> 2 | round-10 | initial / round-10 | Science (P2), 74 | Domination (P2), 44 |
| Standard/Hex/seed-63352/barbarians-off | R4: Deployment: Warrior #6 tile 504 -> 505; moves 2 -> 2 | round-10 | initial / round-10 | Science (P2), 69 | Science (P2), 73 |
| Standard/Sphere/seed-7919/barbarians-on | R2: AI route: Warrior #4 tile 264 -> 3; moves 1 -> 0 | round-10 | initial / round-10 | Science (P2), 69 | Science (P2), 68 |
| Standard/Sphere/seed-15838/barbarians-off | R2: AI route: Warrior #4 tile 36 -> 30; moves 0 -> 0 | round-10 | initial / round-10 | Science (P2), 68 | Science (P2), 68 |
| Standard/Sphere/seed-23757/barbarians-on | R2: AI route: Warrior #4 tile 303 -> 297; moves 0 -> 0 | round-10 | initial / round-10 | Culture (P2), 77 | Science (P2), 74 |
| Standard/Sphere/seed-31676/barbarians-off | R1: AI route: Warrior #4 tile 100 -> 94; moves 0 -> 1 | round-10 | initial / round-10 | Science (P2), 68 | Science (P2), 72 |
| Standard/Sphere/seed-39595/barbarians-on | R4: Deployment: Warrior #6 tile 633 -> 634; moves 2 -> 2 | round-10 | initial / round-10 | Science (P2), 69 | Science (P2), 68 |
| Standard/Sphere/seed-47514/barbarians-off | R5: Deployment: Warrior #7 tile 132 -> 127; moves 2 -> 2 | round-10 | initial / round-10 | Science (P2), 71 | Science (P2), 68 |
| Standard/Sphere/seed-55433/barbarians-on | R3: Deployment: Warrior #6 tile 293 -> 300; moves 2 -> 2 | round-10 | initial / round-10 | Science (P2), 70 | Science (P2), 69 |
| Standard/Sphere/seed-63352/barbarians-off | R5: Deployment: Warrior #7 tile 187 -> 138; moves 2 -> 2 | round-10 | initial / round-20 | Science (P2), 69 | Science (P2), 69 |
| Full/Hex/seed-7919/barbarians-on | R3: Deployment: Warrior #6 tile 181 -> 182; moves 2 -> 2 | round-10 | initial / round-10 | Culture (P2), 94 | Culture (P2), 96 |
| Full/Hex/seed-15838/barbarians-off | R3: Deployment: Warrior #6 tile 202 -> 203; moves 2 -> 2 | round-10 | initial / round-10 | Culture (P2), 100 | Science (P2), 94 |
| Full/Hex/seed-23757/barbarians-on | R3: Deployment: Warrior #6 tile 625 -> 626; moves 2 -> 2 | round-10 | initial / round-10 | Culture (P2), 100 | Culture (P2), 100 |
| Full/Hex/seed-31676/barbarians-off | R3: Deployment: Warrior #6 tile 231 -> 232; moves 2 -> 2 | round-10 | initial / round-20 | Science (P2), 100 | Culture (P2), 98 |
| Full/Hex/seed-39595/barbarians-on | R4: Deployment: Warrior #6 tile 400 -> 401; moves 2 -> 2 | round-10 | initial / round-10 | Domination (P2), 76 | Domination (P2), 100 |
| Full/Hex/seed-47514/barbarians-off | R4: Deployment: Warrior #6 tile 399 -> 400; moves 2 -> 2 | round-10 | initial / round-20 | Science (P2), 102 | Science (P2), 106 |
| Full/Hex/seed-55433/barbarians-on | R4: Deployment: Warrior #6 tile 70 -> 71; moves 2 -> 2 | round-10 | initial / round-20 | Domination (P2), 75 | Domination (P2), 87 |
| Full/Hex/seed-63352/barbarians-off | R4: Deployment: Warrior #6 tile 895 -> 896; moves 2 -> 2 | round-10 | initial / round-10 | Science (P2), 101 | Science (P2), 100 |
| Full/Sphere/seed-7919/barbarians-on | R3: Deployment: Warrior #6 tile 1121 -> 1122; moves 2 -> 2 | round-10 | initial / round-10 | Science (P2), 101 | Culture (P2), 101 |
| Full/Sphere/seed-15838/barbarians-off | R4: Deployment: Warrior #6 tile 1168 -> 1178; moves 2 -> 2 | round-10 | initial / round-20 | Science (P2), 101 | Culture (P2), 101 |
| Full/Sphere/seed-23757/barbarians-on | R3: Deployment: Warrior #6 tile 827 -> 828; moves 2 -> 2 | round-10 | initial / round-20 | Domination (P2), 55 | Domination (P2), 55 |
| Full/Sphere/seed-31676/barbarians-off | R3: Deployment: Warrior #6 tile 1245 -> 1246; moves 2 -> 2 | round-10 | initial / round-10 | Culture (P2), 99 | Science (P2), 101 |
| Full/Sphere/seed-39595/barbarians-on | R4: Deployment: Warrior #6 tile 1193 -> 1201; moves 2 -> 2 | round-10 | initial / round-10 | Culture (P2), 95 | Science (P2), 101 |
| Full/Sphere/seed-47514/barbarians-off | R6: Deployment: Warrior #7 tile 267 -> 258; moves 2 -> 2 | round-10 | initial / round-10 | Science (P2), 99 | Science (P2), 100 |
| Full/Sphere/seed-55433/barbarians-on | R3: Deployment: Warrior #6 tile 691 -> 692; moves 2 -> 2 | round-10 | initial / round-20 | Domination (P2), 84 | Culture (P2), 96 |
| Full/Sphere/seed-63352/barbarians-off | R6: Deployment: Warrior #7 tile 397 -> 276; moves 2 -> 2 | round-10 | initial / round-10 | Culture (P2), 94 | Culture (P2), 98 |

Final local verification: all four requested gates passed; the full 48-game golden comparison and 12 resume replays passed. The balance harness completed all 24 AI-versus-AI games (8 seeds each for Quick, Standard and Full) without hanging. Astra high review found one barbarian city-forecast mismatch; the fix and focused regressions were re-reviewed with no remaining findings. No push or PR was performed.
