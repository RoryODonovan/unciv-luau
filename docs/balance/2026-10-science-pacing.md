# W2-D follow-up: category cost pacing, October 2026

Implementation base: `92d3e8bc241b996e570443ed6c2596849fd82f9f`. Original MPL-2.0 engine balance measured with the official Luau CLI; these AI-only results are not Unciv parity or human pacing evidence.

## Selected configuration

Selected tech exponent **1.8** (floor **20%**), production/growth **0.5**, policy base **-0.4**. Quick ends at median **45** (target 35-45) and Standard at **72** (65-78). Standard has Science **18/24 = 75%** and Culture **4/24 = 16.7%**. Quick has Score **13/24 = 54.2%**, Culture **7/24 = 29.2%** and Domination **4/24 = 16.7%**. Targets (1), (2) and the required part of (3) pass. Quick Science is **0/24**, so its 15% stretch goal is unmet. All Full records are identical. Target (4) has one small rounding-sized miss described below; this is the best sampled configuration satisfying (1)-(3) with era medians closest to the requested band.

All categories derive from the same saved round limit, `x = maxTurns / 120`. No new state field, host option or save version is added. Research is the default category of `BaseGame.costPercent(state, category?)`; category is one of `tech`, `production`, `growth`, `policy`.

`percent(category) = clamp(floor(100 * x^exponent + 0.5), categoryFloor, 200)`

| Category | Exponent | Floor | 45 rounds | 80 rounds | 120 rounds | 200 rounds |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Tech | 1.8 | 20 | 20 | 48 | 100 | 200 |
| Production | 0.5 | 30 | 61 | 82 | 100 | 129 |
| Growth | 0.5 | 30 | 61 | 82 | 100 | 129 |
| Policy base | -0.4 | 30 | 148 | 118 | 100 | 82 |

Research, production and growth percentages are monotone nondecreasing over 20-500 rounds; policy percentage is monotone nonincreasing. Every category is exactly 100% at 120 rounds. Production and growth share their exponent, leaving three distinct curves.

Integer category costs use `pacedBase = max(1, floor(base * percent / 100 + 0.5))`. Research uses tech; unit/building/wonder/Space Project costs use production; food thresholds and forecasts use growth. Purchase prices remain rounded production times the existing ratio (4); upgrade minimum gold uses production pacing, as does the difference between rounded unit costs. Snapshot cost tables, availability, actual debits and AI cost reads share these helpers; priorities, reserves and tie rules stay unchanged.

Policies use `floor(pacedBase * (100 + policyCostIncrease * adoptedCount) / 100)`, followed by the existing floored Oracle discount. Only the policy base is scaled. The existing default `policyCostIncrease` calculation is unchanged: 50 / 63 / 140 at Quick / Standard / Full; explicit values still override it. The culture threshold, all per-item rules, yields and AI behavior are unchanged. Full policy costs, including all adopted counts, explicit growth values and Oracle discounts, are identical.

## Before and after, 24 seeds

Command: `node tools/balance-sim.mjs 24 on`. Normal difficulty, barbarians on, both civilizations AI-controlled, seeds `n * 7919`, n = 1-24. Quick: radius 10 / 45 rounds / 4 policies; Standard: 15 / 80 / 6; Full: 20 / 120 / 6. End medians use the lower middle observation. Technologies and end eras pool both civilizations (48 observations); era ids 4/5/6 mean Renaissance/Industrial/Modern. First-arrival medians are each game's first civilization reaching an era, conditional on arrival before the terminal phase; counts in parentheses are games. Terminal-step technologies count in end metrics. The harness uses the W2-B score/knowledge/Draw tie rule.

Before, first pass `92d3e8b` (shared exponent 1.5, floor 30, unscaled policy bases):

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick | 50 | Culture 24 | 0 | 25 (22-28) | 22 (25) | 4 | Classical 7 (24), Medieval 15 (24), Renaissance 20 (24) |
| Standard | 63 | Culture 16, Domination 1, Science 7 | 0 | 59 (51-66) | 38 (40) | 6 | Classical 10 (24), Medieval 24 (24), Renaissance 31 (24), Industrial 41 (24), Modern 50 (23) |
| Full | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

After, selected category curves:

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 7, Domination 4, Score 13 | 0 | 45 (33-45) | 38 (40) | 6 | Classical 5 (24), Medieval 16 (24), Renaissance 22 (24), Industrial 31 (24), Modern 40 (20) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 4, Domination 1, Science 18, Score 1 | 0 | 72 (63-80) | 40 (40) | 6 | Classical 11 (24), Medieval 26 (24), Renaissance 33 (24), Industrial 46 (24), Modern 59 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

Era first-arrival medians against Full times maxTurns/120:

| Preset | Era | Scaled Full | Actual | Difference |
| --- | --- | ---: | ---: | ---: |
| Quick | Classical | 6 | 5 | -16.7% |
| Quick | Medieval | 14.625 | 16 | +9.4% |
| Quick | Renaissance | 18.75 | 22 | +17.3% |
| Quick | Industrial | 25.125 | 31 | +23.4% |
| Quick | Modern | 31.875 | 40 | **+25.5%** |
| Standard | Classical | 10.667 | 11 | +3.1% |
| Standard | Medieval | 26 | 26 | 0% |
| Standard | Renaissance | 33.333 | 33 | -1.0% |
| Standard | Industrial | 44.667 | 46 | +3.0% |
| Standard | Modern | 56.667 | 59 | +4.1% |

All but Quick Modern are inside the exact +/-25% band. Quick Modern's upper bound is 39.84375 rounds: the integer median 40 misses by 0.15625 rounds (0.49 percentage points). Reported explicitly rather than claimed as a strict pass.

## Systematic curve search

26 configurations, each all 24 seeds and all three presets. The initial 3-by-3 grid held tech at exponent 1.5 / floor 30, varied shared production/growth exponent 0 / 0.5 / 1 and policy exponent 0 / -0.5 / -1. A six-candidate refinement used production/growth 0.8 / 0.9 / 1 and policy -0.6 / -0.75. Two four-candidate tech refinements tested exponent 2 / floor 15 and exponent 1.8 / floor 20 with gentler infrastructure and policy curves. All other floors were 30 and all ceilings 200.

Reproduce a candidate without changing repository modules: `node tools/balance-sim.mjs 24 on techExponent,productionExponent,growthExponent,policyExponent techFloor`. Overrides apply only to the harness's temporary source copy. Without overrides it tests the committed configuration. Full's table was identical in every candidate. Every complete tried table follows, including Full; no unsuccessful candidate is omitted.

### Candidate 1: exponents 1.5, 0, 0, -0.5; tech floor 30

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Domination 1, Score 23 | 0 | 45 (45-45) | 24 (27) | 4 | Classical 9 (24), Medieval 24 (24), Renaissance 32 (24), Industrial 44 (4) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 1, Domination 1, Science 3, Score 19 | 0 | 80 (73-80) | 39 (40) | 6 | Classical 11 (24), Medieval 29 (24), Renaissance 39 (24), Industrial 54 (24), Modern 69 (23) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 2: exponents 1.5, 0, 0, -1; tech floor 30

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Score 24 | 0 | 45 (45-45) | 24 (29) | 4 | Classical 9 (24), Medieval 24 (24), Renaissance 32 (24), Industrial 43 (3) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Domination 1, Science 2, Score 21 | 0 | 80 (72-80) | 38 (40) | 6 | Classical 11 (24), Medieval 29 (24), Renaissance 39 (24), Industrial 55 (24), Modern 71 (23) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 3: exponents 1.5, 0, 0, 0; tech floor 30

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 24 | 0 | 39 (37-45) | 22 (24) | 4 | Classical 9 (24), Medieval 24 (24), Renaissance 32 (24) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 18, Domination 1, Score 5 | 0 | 75 (63-80) | 37 (40) | 6 | Classical 11 (24), Medieval 29 (24), Renaissance 38 (24), Industrial 54 (24), Modern 68 (22) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 4: exponents 1.5, 0.5, 0.5, -0.5; tech floor 30

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 13, Domination 3, Score 8 | 0 | 44 (30-45) | 33 (38) | 5 | Classical 8 (24), Medieval 19 (24), Renaissance 26 (24), Industrial 36 (23), Modern 44 (5) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 7, Science 16, Score 1 | 0 | 74 (66-80) | 40 (40) | 6 | Classical 11 (24), Medieval 27 (24), Renaissance 35 (24), Industrial 48 (24), Modern 62 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 5: exponents 1.5, 0.5, 0.5, -1; tech floor 30

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 2, Domination 2, Score 20 | 0 | 45 (31-45) | 33 (37) | 5 | Classical 8 (24), Medieval 20 (24), Renaissance 26 (24), Industrial 36 (23), Modern 43 (4) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Domination 1, Science 21, Score 2 | 0 | 76 (62-80) | 40 (40) | 6 | Classical 11 (24), Medieval 27 (24), Renaissance 36 (24), Industrial 48 (24), Modern 63 (23) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 6: exponents 1.5, 0.5, 0.5, 0; tech floor 30

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 24 | 0 | 35 (33-38) | 25 (28) | 4 | Classical 8 (24), Medieval 19 (24), Renaissance 26 (24), Industrial 33 (5) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 19, Domination 1, Science 3, Score 1 | 0 | 68 (61-80) | 38 (40) | 6 | Classical 11 (24), Medieval 26 (24), Renaissance 35 (24), Industrial 48 (24), Modern 61 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 7: exponents 1.5, 0.8, 0.8, -0.6; tech floor 30

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 23, Domination 1 | 0 | 40 (23-44) | 32 (39) | 5 | Classical 8 (24), Medieval 17 (24), Renaissance 23 (23), Industrial 32 (23), Modern 42 (6) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 4, Science 19, Score 1 | 0 | 72 (64-80) | 40 (40) | 6 | Classical 10 (24), Medieval 26 (24), Renaissance 33 (24), Industrial 45 (24), Modern 58 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 8: exponents 1.5, 0.8, 0.8, -0.75; tech floor 30

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 16, Domination 4, Score 4 | 0 | 42 (23-45) | 35 (39) | 6 | Classical 8 (24), Medieval 17 (24), Renaissance 23 (23), Industrial 32 (23), Modern 41 (12) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Science 23, Score 1 | 0 | 70 (66-80) | 40 (40) | 6 | Classical 10 (24), Medieval 26 (24), Renaissance 33 (24), Industrial 45 (24), Modern 58 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 9: exponents 1.5, 0.9, 0.9, -0.6; tech floor 30

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 23, Score 1 | 0 | 38 (36-45) | 32 (40) | 5 | Classical 7 (24), Medieval 16 (24), Renaissance 22 (24), Industrial 31 (24), Modern 40 (4) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 2, Domination 3, Science 19 | 0 | 69 (54-77) | 40 (40) | 6 | Classical 10 (24), Medieval 26 (24), Renaissance 33 (24), Industrial 44 (24), Modern 57 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 10: exponents 1.5, 0.9, 0.9, -0.75; tech floor 30

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 19, Domination 3, Score 2 | 0 | 40 (36-45) | 34 (40) | 5 | Classical 7 (24), Medieval 16 (24), Renaissance 22 (24), Industrial 32 (24), Modern 40 (11) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 2, Domination 2, Science 19, Score 1 | 0 | 70 (57-80) | 40 (40) | 6 | Classical 10 (24), Medieval 26 (24), Renaissance 33 (24), Industrial 44 (24), Modern 57 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 11: exponents 1.5, 1, 1, -0.5; tech floor 30

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 21, Domination 3 | 0 | 35 (30-41) | 30 (36) | 5 | Classical 7 (24), Medieval 15 (24), Renaissance 21 (24), Industrial 30 (23), Modern 40 (1) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 8, Domination 1, Science 15 | 0 | 68 (48-73) | 40 (40) | 6 | Classical 10 (24), Medieval 25 (24), Renaissance 32 (24), Industrial 44 (24), Modern 55 (23) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 12: exponents 1.5, 1, 1, -0.6; tech floor 30

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 22, Domination 2 | 0 | 37 (30-43) | 32 (38) | 5 | Classical 7 (24), Medieval 15 (24), Renaissance 21 (24), Industrial 30 (23), Modern 40 (4) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 2, Domination 1, Science 21 | 0 | 68 (53-74) | 40 (40) | 6 | Classical 10 (24), Medieval 25 (24), Renaissance 32 (24), Industrial 43 (24), Modern 55 (23) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 13: exponents 1.5, 1, 1, -0.75; tech floor 30

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 19, Domination 4, Score 1 | 0 | 39 (30-45) | 34 (40) | 5 | Classical 7 (24), Medieval 15 (24), Renaissance 21 (24), Industrial 31 (23), Modern 40 (10) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 2, Domination 1, Science 21 | 0 | 69 (64-75) | 40 (40) | 6 | Classical 10 (24), Medieval 25 (24), Renaissance 32 (24), Industrial 43 (24), Modern 56 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 14: exponents 1.5, 1, 1, -1; tech floor 30

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 19, Domination 4, Score 1 | 0 | 39 (30-45) | 34 (40) | 5 | Classical 7 (24), Medieval 15 (24), Renaissance 21 (24), Industrial 31 (23), Modern 40 (10) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Domination 2, Science 22 | 0 | 68 (61-76) | 40 (40) | 6 | Classical 10 (24), Medieval 25 (24), Renaissance 33 (24), Industrial 43 (24), Modern 56 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 15: exponents 1.5, 1, 1, 0; tech floor 30

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 24 | 0 | 29 (25-31) | 24 (27) | 4 | Classical 7 (24), Medieval 15 (24), Renaissance 21 (24), Industrial 30 (2) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 22, Science 2 | 0 | 63 (56-73) | 38 (40) | 6 | Classical 10 (24), Medieval 25 (24), Renaissance 32 (24), Industrial 43 (24), Modern 54 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 16: exponents 1.8, 0.5, 0.5, -0.3; tech floor 20

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 21, Domination 3 | 0 | 43 (33-45) | 37 (40) | 6 | Classical 5 (24), Medieval 16 (24), Renaissance 21 (24), Industrial 31 (24), Modern 40 (18) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 1, Domination 1, Science 21, Score 1 | 0 | 71 (63-80) | 40 (40) | 6 | Classical 11 (24), Medieval 26 (24), Renaissance 33 (24), Industrial 46 (24), Modern 58 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 17: exponents 1.8, 0.5, 0.5, -0.4; tech floor 20 (selected)

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 7, Domination 4, Score 13 | 0 | 45 (33-45) | 38 (40) | 6 | Classical 5 (24), Medieval 16 (24), Renaissance 22 (24), Industrial 31 (24), Modern 40 (20) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 4, Domination 1, Science 18, Score 1 | 0 | 72 (63-80) | 40 (40) | 6 | Classical 11 (24), Medieval 26 (24), Renaissance 33 (24), Industrial 46 (24), Modern 59 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 18: exponents 1.8, 0.5, 0.5, -0.5; tech floor 20

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 4, Domination 3, Score 17 | 0 | 45 (32-45) | 38 (40) | 6 | Classical 5 (24), Medieval 16 (24), Renaissance 22 (24), Industrial 31 (24), Modern 40 (22) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 2, Domination 1, Science 20, Score 1 | 0 | 72 (64-80) | 40 (40) | 6 | Classical 11 (24), Medieval 26 (24), Renaissance 33 (24), Industrial 46 (24), Modern 59 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 19: exponents 1.8, 0.6, 0.6, -0.3; tech floor 20

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 21, Domination 3 | 0 | 41 (35-45) | 36 (40) | 6 | Classical 5 (24), Medieval 15 (24), Renaissance 21 (24), Industrial 30 (24), Modern 39 (16) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 3, Domination 1, Science 20 | 0 | 70 (62-77) | 40 (40) | 6 | Classical 11 (24), Medieval 26 (24), Renaissance 33 (24), Industrial 45 (24), Modern 57 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 20: exponents 1.8, 0.6, 0.6, -0.4; tech floor 20

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 20, Domination 2, Score 2 | 0 | 43 (33-45) | 38 (40) | 6 | Classical 5 (24), Medieval 15 (24), Renaissance 21 (24), Industrial 30 (24), Modern 39 (20) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 1, Domination 1, Science 22 | 0 | 70 (63-78) | 40 (40) | 6 | Classical 11 (24), Medieval 26 (24), Renaissance 33 (24), Industrial 45 (24), Modern 57 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 21: exponents 1.8, 0.75, 0.75, -0.4; tech floor 20

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 22, Domination 2 | 0 | 40 (34-45) | 35 (40) | 6 | Classical 5 (24), Medieval 14 (24), Renaissance 20 (24), Industrial 29 (24), Modern 38 (14) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 2, Domination 1, Science 21 | 0 | 68 (62-76) | 40 (40) | 6 | Classical 10 (24), Medieval 25 (24), Renaissance 32 (24), Industrial 43 (24), Modern 55 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 22: exponents 1.8, 0.75, 0.75, -0.5; tech floor 20

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 20, Domination 2, Score 2 | 0 | 41 (36-45) | 37 (40) | 6 | Classical 5 (24), Medieval 15 (24), Renaissance 20 (24), Industrial 29 (24), Modern 38 (18) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 1, Domination 1, Science 22 | 0 | 68 (63-77) | 40 (40) | 6 | Classical 10 (24), Medieval 25 (24), Renaissance 32 (24), Industrial 43 (24), Modern 56 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 23: exponents 2, 0.5, 0.5, -0.5; tech floor 15

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Domination 4, Science 5, Score 15 | 0 | 45 (37-45) | 40 (40) | 6 | Classical 4 (24), Medieval 13 (24), Renaissance 19 (24), Industrial 28 (24), Modern 37 (22) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Domination 1, Science 23 | 0 | 71 (62-79) | 40 (40) | 6 | Classical 10 (24), Medieval 25 (24), Renaissance 33 (24), Industrial 45 (24), Modern 57 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 24: exponents 2, 0.5, 0.5, -0.6; tech floor 15

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Domination 3, Science 5, Score 16 | 0 | 45 (38-45) | 40 (40) | 6 | Classical 4 (24), Medieval 13 (24), Renaissance 19 (24), Industrial 28 (24), Modern 37 (23) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 1, Science 22, Score 1 | 0 | 70 (62-80) | 40 (40) | 6 | Classical 10 (24), Medieval 25 (24), Renaissance 32 (24), Industrial 44 (24), Modern 57 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 25: exponents 2, 0.75, 0.75, -0.5; tech floor 15

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 14, Domination 3, Science 7 | 0 | 41 (33-45) | 40 (40) | 6 | Classical 4 (24), Medieval 13 (24), Renaissance 18 (24), Industrial 27 (24), Modern 36 (23) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Science 24 | 0 | 65 (61-76) | 40 (40) | 6 | Classical 10 (24), Medieval 24 (24), Renaissance 31 (24), Industrial 42 (24), Modern 53 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

### Candidate 26: exponents 2, 0.75, 0.75, -0.6; tech floor 15

| Preset | Policy cost growth | Victories | Draw | End round, median (range) | Technologies at the end, median (max) | Highest era at the end, median | Eras first reached, median round (games) |
| --- | ---: | --- | ---: | --- | --- | ---: | --- |
| Quick (radius 10, 45 rounds, 4 policies) | 50 | Culture 7, Domination 1, Science 16 | 0 | 43 (33-45) | 40 (40) | 6 | Classical 4 (24), Medieval 13 (24), Renaissance 18 (24), Industrial 27 (24), Modern 36 (23) |
| Standard (radius 15, 80 rounds, 6 policies) | 63 | Culture 1, Domination 1, Science 22 | 0 | 66 (61-73) | 40 (40) | 6 | Classical 10 (24), Medieval 24 (24), Renaissance 32 (24), Industrial 42 (24), Modern 54 (24) |
| Full (radius 20, 120 rounds, 6 policies) | 140 | Culture 15, Domination 1, Science 8 | 0 | 100 (77-109) | 39 (40) | 6 | Classical 16 (24), Medieval 39 (24), Renaissance 50 (24), Industrial 67 (24), Modern 85 (23) |

The final three nearby candidates used tech 1.8 / floor 20, production/growth 0.5 / 0.6 and policy -0.3 / -0.4. They improved Quick's end median or Modern arrival but failed one or both route targets. The selected candidate improves the era band substantially over the first passing coarse-grid candidate (1.5 / 0.5 / 0.5 / -0.5), whose Quick Classical, Medieval, Renaissance and Industrial medians were +33.3%, +29.9%, +38.7% and +43.3% late.

Quick's required route diversity is met. Its Science stretch is blocked in this sampled neighborhood by the forty-technology sequential AI research path and subsequent Space Project build: even 40 technologies at the round limit need not mean a completed project. Cheaper tech and stronger infrastructure did produce 5-16 Quick Science wins, but each such candidate made Standard nearly or entirely Science (22-24 wins), failing its second >=15% route. Reducing policy inflation in neighboring candidates often left Quick dominated by Culture. This is evidence for this sampled family, not an impossibility proof for every permitted curve. No AI, culture threshold, policyCostIncrease formula or per-item rule was changed to repair those tradeoffs.

## Saves, regressions and goldens

Save versions remain 1 (Hex) / 2 (Sphere). Research validation and both restore paths use the tech curve. Legacy base-cost research and first-pass W2-D research (exponent 1.5 / floor 30) are accepted and migrate while preserving completed fraction, rounded down; paced saves round-trip exactly. Full restore is an identity. Food and production remain absolute stores spent against the new thresholds. Policy pace is derived on restore; saved culture and policyCostIncrease remain unchanged. Earlier engines reject non-Full paced research they do not recognize.

The expanded `base-cost-pacing` tests assert literal category values at 45 / 80 / 120 / 200 rounds, monotonicity, every snapshot production/purchase entry, current/menu research, growth and production forecasts against completion, upgrades, AI affordability and research, and saves. Policy tests cover every rule-order adoption count at explicit growth 0 / 50 / 140, exact refusal/debit boundaries, Oracle and Full identity. AI tests check just-below and exact policy costs, with and without Oracle, at all four round limits; they account separately for following economy income. The older `base-events` AI escalation fixture now runs at Full to isolate its original 37-culture Liberty assertion.

Temporary-copy mutation checks reject all 10 regressions: each of four category curves; production and growth routing; policy-base scaling; the AI reading an unscaled policy cost; save research using production pace; and removal of first-pass save compatibility. Each fails an assertion in the expanded pacing tests; the unmutated tests pass. The source checkout is never mutated by these checks.

Only Quick and Standard baseline records were regenerated. The complete corpus was executed to verify resume replay and Full identity; the updater retained the original Full records and refused to write if any Full record differed. All 16 Full games, including 176 checkpoints / 528 state-and-actor-view hashes, remain deeply identical. SHA-256 of the JSON-serialized Full record array:

`01df2cb3862e683b29a570a3d56aff8819638886f817595e774c221403b4f3cd`

The golden script drives civilization 1 by fixed research/EndTurn commands and civilization 2 by AI; its outcomes differ from the AI-against-AI sample. The changed Quick/Standard games (state/view hashes changed even where outcome/round agree) are:

| Game | Before outcome / round | After outcome / round |
| --- | --- | --- |
| Quick/Hex/seed-7919/barbarians-on | Culture 27 | Score 45 |
| Quick/Hex/seed-15838/barbarians-off | Culture 26 | Score 45 |
| Quick/Hex/seed-23757/barbarians-on | Culture 28 | Domination 32 |
| Quick/Hex/seed-31676/barbarians-off | Culture 28 | Culture 45 |
| Quick/Hex/seed-39595/barbarians-on | Culture 26 | Domination 44 |
| Quick/Hex/seed-47514/barbarians-off | Culture 27 | Culture 41 |
| Quick/Hex/seed-55433/barbarians-on | Culture 27 | Domination 39 |
| Quick/Hex/seed-63352/barbarians-off | Culture 29 | Score 45 |
| Quick/Sphere/seed-7919/barbarians-on | Culture 28 | Score 45 |
| Quick/Sphere/seed-15838/barbarians-off | Culture 25 | Culture 45 |
| Quick/Sphere/seed-23757/barbarians-on | Culture 27 | Score 45 |
| Quick/Sphere/seed-31676/barbarians-off | Culture 26 | Domination 33 |
| Quick/Sphere/seed-39595/barbarians-on | Culture 28 | Score 45 |
| Quick/Sphere/seed-47514/barbarians-off | Culture 28 | Score 45 |
| Quick/Sphere/seed-55433/barbarians-on | Culture 26 | Score 45 |
| Quick/Sphere/seed-63352/barbarians-off | Culture 26 | Score 45 |
| Standard/Hex/seed-7919/barbarians-on | Culture 59 | Science 70 |
| Standard/Hex/seed-15838/barbarians-off | Culture 56 | Science 65 |
| Standard/Hex/seed-23757/barbarians-on | Culture 55 | Domination 59 |
| Standard/Hex/seed-31676/barbarians-off | Domination 44 | Science 69 |
| Standard/Hex/seed-39595/barbarians-on | Domination 51 | Domination 53 |
| Standard/Hex/seed-47514/barbarians-off | Culture 57 | Culture 76 |
| Standard/Hex/seed-55433/barbarians-on | Domination 39 | Science 75 |
| Standard/Hex/seed-63352/barbarians-off | Culture 55 | Science 70 |
| Standard/Sphere/seed-7919/barbarians-on | Culture 57 | Science 70 |
| Standard/Sphere/seed-15838/barbarians-off | Culture 55 | Science 71 |
| Standard/Sphere/seed-23757/barbarians-on | Culture 56 | Domination 73 |
| Standard/Sphere/seed-31676/barbarians-off | Domination 53 | Domination 68 |
| Standard/Sphere/seed-39595/barbarians-on | Culture 53 | Science 72 |
| Standard/Sphere/seed-47514/barbarians-off | Culture 54 | Science 69 |
| Standard/Sphere/seed-55433/barbarians-on | Culture 58 | Science 68 |
| Standard/Sphere/seed-63352/barbarians-off | Domination 44 | Domination 62 |

## Public gates

| Gate | Output tail |
| --- | --- |
| `npm.cmd run test:tooling` | `Metadata gate regression checks passed (valid metadata, missing licence, host globals, absent provenance).` |
| `npm.cmd run check` | `Golden default: 12 games passed, 12 resume replays` / `Passed 27 standalone test files.` |
| `GOLDEN_FULL=1 node tests/golden/run.mjs` | `Golden full: 48 games passed, 12 resume replays` |
| `node tools/roblox-export.mjs --check` | `Roblox module export reproducible (16 modules)` |
| `npm.cmd run test:export` | `Roblox exporter regression checks passed` |

Roblox modules and manifest were generated by `node tools/roblox-export.mjs`; no export was hand-edited. npm gates use `npm.cmd` because PowerShell blocks `npm.ps1`. The required claude-collaborator review was deferred because this work order prohibits network access; no peer review is claimed, no push/fetch/clone or PR was attempted.
