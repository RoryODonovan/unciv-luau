# W2-D: pace-scaled costs, October 2026

Implementation base: `5413aa33625614d7bbde04fef71f5390603a8749`. Public, original MPL-2.0 engine balance; these are AI-only measurements, not an Unciv parity or human pacing claim.

## Result and remaining decision

The best sampled single curve brings Science back to Standard and puts Quick and Standard's era arrivals within 25% of Full's rounds multiplied by their round-limit ratio. It **does not meet all acceptance targets**. Quick still ends exclusively by Culture, and both short presets end too early. Cost-only tuning stops here as required by the work order. No policy base scaling, policy growth adjustment, culture threshold adjustment, yield change, per-item balance adjustment or AI priority change was added.

Selected curve, configured in `BaseRules.costPace`:

```text
costPercent = clamp(floor(100 * (maxTurns / 120)^1.5 + 0.5), 30, 200)
cost(base)  = max(1, floor(base * costPercent / 100 + 0.5))
```

| Round limit | 45 | 80 | 120 | 200 |
| --- | ---: | ---: | ---: | ---: |
| costPercent | 30 | 54 | 100 | 200 |

`BaseGame.costPercent(state)` derives the percentage from the saved `maxTurns`. No new state or snapshot field, host option, or save version is needed. The function is monotone over the allowed 20–500 round domain. At 120 rounds, every affected integer cost is exactly its previous value.

Research (current research and every available technology view), unit/building/wonder/Space Project production, city food thresholds and forecasts use the rounded cost. Purchases use the rounded production cost times the existing purchase ratio (4), so they remain exact multiples of production. Upgrades cost `max(cost(upgradeMinimumGold), cost(newUnit) - cost(oldUnit)) * upgradeCostMultiplier`; scaling the minimum prevents a fixed 40-gold floor from dominating short games. Snapshots expose paced production/purchase tables and paced purchase eligibility. AI research, wonder completion estimates, cheapest-building ordering, happiness-per-production ordering and upgrade affordability read paced costs; their priorities, limits, reserves and tie rules are unchanged.

## 24-seed before and after

Command: `node tools/balance-sim.mjs 24 on`. Seeds are `n * 7919`, n = 1–24; Normal difficulty, barbarians on, both civilizations AI-controlled. Quick uses radius 10 / 45 rounds / 4 policies, Standard 15 / 80 / 6, Full 20 / 120 / 6. Policy growth remains 50 / 63 / 140.

End-round medians use the lower middle observation. Technology counts and end eras pool both civilizations (48 observations per preset). First-arrival medians use each game's first civilization reaching an era, conditional on that era being reached before the terminal phase; parenthesized counts are games. The terminal step's technology count and era are included in end metrics. The harness round-limit tie rule now matches W2-B: score first, then technologies plus policies, otherwise Draw. Before was also rerun with this corrected harness; no Draw occurred.

Before, pinned base:

| Preset | Victories | Draw | End round median (range) | Techs median (max) | End era median | Era first reached, median round (games) |
| --- | --- | ---: | --- | --- | --- | --- |
| Quick | Culture 23, Score 1 | 0 | 39 (36–45) | 11 (13) | Classical | Classical 17 (24), Medieval 39 (12) |
| Standard | Culture 22, Domination 1, Score 1 | 0 | 73 (65–80) | 28 (31) | Industrial | Classical 16 (24), Medieval 38 (24), Renaissance 50 (24), Industrial 65 (23) |
| Full | Culture 15, Domination 1, Science 8 | 0 | 100 (77–109) | 39 (40) | Modern | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

After, selected exponent 1.5:

| Preset | Victories | Draw | End round median (range) | Techs median (max) | End era median | Era first reached, median round (games) |
| --- | --- | ---: | --- | --- | --- | --- |
| Quick | Culture 24 | 0 | 25 (22–28) | 22 (25) | Renaissance | Classical 7 (24), Medieval 15 (24), Renaissance 20 (24) |
| Standard | Culture 16, Domination 1, Science 7 | 0 | 59 (51–66) | 38 (40) | Modern | Classical 10 (24), Medieval 24 (24), Renaissance 31 (24), Industrial 41 (24), Modern 50 (23) |
| Full | Culture 15, Domination 1, Science 8 | 0 | 100 (77–109) | 39 (40) | Modern | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

Standard has Culture 66.7% and Science 29.2%, satisfying its two-route and Science-share targets. Quick has Science 0%, failing both. End medians 25 and 59 fail the required 35–45 and 65–78. End-era targets pass. Quick's first-era timings differ from scaled Full by +16.7%, +2.6%, +6.7%; Standard's by −6.3%, −7.7%, −7.0%, −8.2%, −11.8%. All are inside the requested 25% band.

## Curve search

Only the exponent changed during this search; clamps stayed at 30–200. Every candidate used all 24 seeds and all three presets. Full's table above was identical in every run.

| Exponent | Quick / Standard costPercent | Quick median / wins | Standard median / wins |
| ---: | --- | --- | --- |
| 0.6 | 56 / 78 | 32 / Culture 24 | 67 / Culture 24 |
| 1.0 | 38 / 67 | 28 / Culture 24 | 63 / Culture 23, Domination 1 |
| 1.2 | 31 / 61 | 25 / Culture 24 | 61 / Culture 24 |
| 1.4 | 30 / 57 | 25 / Culture 24 | 59 / Culture 20, Domination 1, Science 3 |
| **1.5** | **30 / 54** | **25 / Culture 24** | **59 / Culture 16, Domination 1, Science 7** |
| 1.8 | 30 / 48 | 25 / Culture 24 | 55 / Culture 11, Domination 1, Science 12 |

The gentler curve keeps Standard in its timing window but produces no Science wins; it also leaves Quick's median end era at Medieval. The linear curve improves eras but speeds up Culture alongside science infrastructure. Exponent 1.4 just misses the Science-share target (3/24 = 12.5%); 1.5 is the slowest sampled curve satisfying Standard's route targets. Going steeper produces more Science wins but ends Standard even sooner. Quick at the clamp ends by Culture at 25, well before the AI can finish its forty-technology ordered research path: it completes at most one technology per owner economy step. Lower production and food costs also develop population and culture buildings sooner, despite unchanged culture costs and yields.

These measurements establish failure of the sampled family, not a mathematical impossibility proof for every monotone function. The open balance decision is whether to use the work order's policy-base exception or authorize another way to delay Culture while preserving faster science. Neither is implemented here.

## Saves

Save schemas remain version 1 (Hex) and 2 (Sphere). Research validation accepts either the derived current cost or the original base cost for legacy saves, with integer progress below that stored cost. Both restore paths migrate legacy research to the derived cost and preserve its completed fraction: `floor(oldProgress * newCost / oldCost)`. This cannot produce completed research. A paced save round-trips exactly. At Full, migration does nothing. Accumulated food and production remain absolute and are spent against the new thresholds when play resumes. Older engines reject paced non-Full research costs, so do not roll a host back after it writes these saves.

## Golden evidence

`GOLDEN_UPDATE=1 node tests/golden/run.mjs` regenerated all 48 games and passed 12 resume replays. Comparison against the unmodified pinned baseline found exactly 32 changed games: all Quick and Standard games below. All **16 Full games are deeply identical**, including every outcome, winner, round and all **176 checkpoints / 528 state-and-actor-view hashes**. SHA-256 of the JSON-serialized Full game-record array is identical before and after:

```text
01df2cb3862e683b29a570a3d56aff8819638886f817595e774c221403b4f3cd
```

The golden driver controls civilization 1 with a fixed research/EndTurn script and civilization 2 with the engine AI; its outcomes are separate from the AI-against-AI balance sample.

## Validation

The new `base-cost-pacing` fixtures cover literal percentages, monotonicity, all snapshot cost entries, current/menu research, production of units/wonders/Space Project, purchase boundaries and actual debits, forecasts against actual growth/completion, upgrades, an AI reserve decision differing by pace, current save replay and legacy migration. Temporary-copy mutation checks rejected all 14 cost/save regressions. The barbarian cap fixture suppresses AI policy adoption so the faster Culture race cannot terminate it before all camps are scheduled; barbarian rules and timing are unchanged.

All required gates passed using the pinned official Luau CLI. Windows PowerShell blocks `npm.ps1`, so npm gates used the equivalent `npm.cmd` entry point; no permission or execution-policy change was needed.

| Gate | Output tail |
| --- | --- |
| `npm.cmd run test:tooling` | `Metadata gate regression checks passed (valid metadata, missing licence, host globals, absent provenance).` |
| `GOLDEN_FULL=1 npm.cmd run check` | `Golden full: 48 games passed, 12 resume replays` / `Passed 27 standalone test files.` |
| `GOLDEN_FULL=1 node tests/golden/run.mjs` | `Golden full: 48 games passed, 12 resume replays` |
| `node tools/roblox-export.mjs --check` | `Roblox module export reproducible (16 modules)` |
| `npm.cmd run test:export` | `Roblox exporter regression checks passed` |

The Roblox export was regenerated with `node tools/roblox-export.mjs`. No export file was hand-edited. The automatic local Claude consultation was deferred because this work order forbids network; the assigned downstream Claude and Astra reviews remain pending. No push or PR was attempted.

## Exact changed golden games

| Game | Old outcome / end round | New outcome / end round |
| --- | --- | --- |
| Quick/Hex/seed-7919/barbarians-on | Culture 41 | Culture 27 |
| Quick/Hex/seed-15838/barbarians-off | Culture 39 | Culture 26 |
| Quick/Hex/seed-23757/barbarians-on | Culture 42 | Culture 28 |
| Quick/Hex/seed-31676/barbarians-off | Culture 38 | Culture 28 |
| Quick/Hex/seed-39595/barbarians-on | Culture 40 | Culture 26 |
| Quick/Hex/seed-47514/barbarians-off | Culture 37 | Culture 27 |
| Quick/Hex/seed-55433/barbarians-on | Culture 38 | Culture 27 |
| Quick/Hex/seed-63352/barbarians-off | Culture 36 | Culture 29 |
| Quick/Sphere/seed-7919/barbarians-on | Culture 41 | Culture 28 |
| Quick/Sphere/seed-15838/barbarians-off | Culture 40 | Culture 25 |
| Quick/Sphere/seed-23757/barbarians-on | Culture 40 | Culture 27 |
| Quick/Sphere/seed-31676/barbarians-off | Culture 38 | Culture 26 |
| Quick/Sphere/seed-39595/barbarians-on | Culture 42 | Culture 28 |
| Quick/Sphere/seed-47514/barbarians-off | Culture 42 | Culture 28 |
| Quick/Sphere/seed-55433/barbarians-on | Culture 41 | Culture 26 |
| Quick/Sphere/seed-63352/barbarians-off | Culture 38 | Culture 26 |
| Standard/Hex/seed-7919/barbarians-on | Culture 76 | Culture 59 |
| Standard/Hex/seed-15838/barbarians-off | Culture 72 | Culture 56 |
| Standard/Hex/seed-23757/barbarians-on | Culture 73 | Culture 55 |
| Standard/Hex/seed-31676/barbarians-off | Domination 63 | Domination 44 |
| Standard/Hex/seed-39595/barbarians-on | Culture 74 | Domination 51 |
| Standard/Hex/seed-47514/barbarians-off | Culture 77 | Culture 57 |
| Standard/Hex/seed-55433/barbarians-on | Culture 80 | Domination 39 |
| Standard/Hex/seed-63352/barbarians-off | Culture 74 | Culture 55 |
| Standard/Sphere/seed-7919/barbarians-on | Culture 73 | Culture 57 |
| Standard/Sphere/seed-15838/barbarians-off | Culture 73 | Culture 55 |
| Standard/Sphere/seed-23757/barbarians-on | Domination 73 | Culture 56 |
| Standard/Sphere/seed-31676/barbarians-off | Domination 72 | Domination 53 |
| Standard/Sphere/seed-39595/barbarians-on | Culture 78 | Culture 53 |
| Standard/Sphere/seed-47514/barbarians-off | Culture 70 | Culture 54 |
| Standard/Sphere/seed-55433/barbarians-on | Culture 72 | Culture 58 |
| Standard/Sphere/seed-63352/barbarians-off | Domination 67 | Domination 44 |
