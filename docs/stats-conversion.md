# Statistics and Counter conversion

These are reusable, service-independent Luau conversions from Unciv commit
`42939c6a2cf31aa76f44ffc033015ad12fece9f5`, under MPL-2.0. The upstream
files contain no individual copyright notices. Authorship remains with the
Unciv contributors; see the repository-wide attribution and licence.

## Supported surface

`Stat` provides the seven case-sensitive identifiers, their upstream order,
lookup, purchase eligibility, and city/civilization-wide classification.
`Stat.names()` returns an independent array. Identifier lists and eligibility
sets are frozen.

`Stats` exposes a mutable record with `production`, `food`, `gold`,
`science`, `culture`, `happiness`, and `faith`. Its constructor accepts
seven optional numbers in that order. Use explicit functions:
`Stats.get(value, Stat.Gold)`, `Stats.set(value, Stat.Gold, 5)`, and
`Stats.addStat(value, Stat.Gold, 2)`. No operators or metatable methods are
installed.

- Mutating: `set`, `clear`, `add`, `addStat`, `timesInPlace`,
  `applyRankingWeights`. Both add functions return the modified record.
- Copying: `clone`, `plus`, `minus`, `times`, `div`. Other operands
  remain unchanged.
- Reading: `equals`, `isEmpty`, `entries`, `sum`, `min`, `max`.
  Equality requires the explicit function; table equality compares identity.
- Text: `isStats` and `parse` accept signed integers and exact English
  names separated by comma-space. Repeated stats accumulate, as upstream.
  Invalid input returns false from the predicate and raises from parse.

`entries` returns a snapshot of nonzero entries in upstream stat order.
This differs from Kotlin's lazy iterator when mutation occurs during iteration.
Min/max include all seven fields, including zeros, and use upstream chained
comparison semantics rather than changing NaN handling through a generic reduction.

`Stats.ZERO` and `Stats.DefaultCityCenterMinimum` are runtime-frozen defaults
(an intentional protection beyond upstream). Clone before modifying. They retain
the ordinary Value static type for compatibility with the pure read/copy APIs;
immutability is enforced at runtime.

`Counter` implements the string-key subset used for serialized counters, with
integer values and insertion-order snapshots. Construct with ordered entries:
`Counter.new({{key = "Gold", value = 3}})`. Use `get`, `containsKey`,
`put`, `removeKey`, `add`, `addCounter`, `remove`, `clone`, `plus`,
`times`, `sumValues`, and `entries`. Missing keys read as zero.
`put`/ `removeKey` return the prior value or nil. Zero assignments delete
keys. Replacement preserves order; deleting and reinserting appends.
Negative counts are allowed.

The constructor deliberately preserves zero entries because upstream initializes
through `super.put`; this exception to the usual zero-removal rule also applies
to cloning. Counter.ZERO is deeply runtime-frozen and mutations raise. Cloning
it creates a mutable empty counter. Snapshot traversal makes self-subtraction
well-defined, whereas Kotlin's live collection iteration can invalidate traversal.
Do not directly modify a Counter's `values`, `order`, or `readOnly` fields.

## Omitted surface

Stat UI metadata (font glyphs, notification icons, sounds, LibGDX colors), translated
Stats formatting and icon output, Stats.StatMap, generic non-string Counter keys,
GDX JSON serialization/deserialization, game-info marker interfaces, inheritance,
Kotlin operator overloads, and lazy iteration are not converted. No media is copied.
Stats text parsing does not imply support for translated or fractional stat strings.

## Numeric differences and evidence

Luau numbers are binary64; upstream Stats use binary32 Float. This port does not
round every intermediate calculation to Float. For example, adding 1 to 16777216
retains 16777217 here, whereas binary32 cannot represent that value. Ranking-weight
decimals and arithmetic therefore can differ in low bits. Infinity and NaN are not
filtered from Stats arithmetic, and division follows Luau floating-point rules.

Counter accepts finite integers up to 2^53 - 1 in magnitude and checks computed
results. Kotlin Int is signed 32-bit and overflows; this port does not reproduce
wraparound and allows a wider range. Fractional values are rejected rather than
silently truncated through GDX's JSON read path. External JSON adapters must define
their own compatibility policy.

The self-contained tests verify clone isolation, arithmetic and mutation,
classification, parsing/invalid text, stable order, zero removal, constructor
exceptions, aliasing, and frozen-default protection. Expected results were derived
from the inspected pinned source. No JVM-versus-Luau differential runner has been
executed; full numeric or gameplay parity is not claimed.

Run from the repository root with the official Luau CLI:

```text
luau tests/unit/stats.luau
luau tests/unit/counter.luau
luau-analyze src/models/stats/Stat.luau src/models/stats/Stats.luau src/models/Counter.luau tests/unit/stats.luau tests/unit/counter.luau
```
