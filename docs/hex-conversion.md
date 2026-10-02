# Hex foundation conversion

The modules derive from Unciv's `core/src/com/unciv/logic/map/HexMath.kt` at commit `42939c6a2cf31aa76f44ffc033015ad12fece9f5`. Both modules and the derivative tests are MPL-2.0. The source file contains no additional per-file copyright banner; the conversion credits Unciv's author and contributors. See the repository licence and attribution records.

## Coordinates and API

Unciv's x direction points to 10 o'clock; y points to 2 o'clock. Thus (1,1) moves north, latitude is x+y, longitude is x-y, and an unwrapped distance is max(abs(dx),abs(dy)) when the deltas share a sign, otherwise abs(dx)+abs(dy). These are not the more common axial q/r conventions.

`HexCoord` uses frozen records and static functions instead of Kotlin instance methods. `of(x,y)`, `Zero`, `plus`, `plusXY`, `minus`, `times`, `eq`, `equals`, `cpy`, `toHexCoord`, `toVector2`, `asSerializable`, `toPrettyString`, and `fromString` are supported. Use `equals(a,b)` for value equality: native Luau table equality compares identity. The vector/serializable conversion functions return fresh plain records; they do not serialize JSON.

`HexMath` supports angle vectors; tile counts and area/radius conversions; latitude/longitude; world projection and inverse; equivalent rectangle/hexagon sizes; row/column conversion; cube rounding; nearest wrapped position; rings and disks; unwrapped distances; clock direction coordinates; and zero-based tile indexing. Names follow upstream except overloaded distance APIs are split into `getDistance`, `getDistanceXY`, and `getDistanceVector`.

Ring enumeration preserves the original order, alternating a position with its opposite, rather than returning a clockwise sequence. Wrapped enumeration preserves upstream's seam omissions at the maximum radius: a wrapped nonzero outer ring has 5r-1 records. This helper does not consult map bounds or deduplicate arbitrary world shapes.

`getRow` preserves Kotlin integer division towards zero. For negative odd columns/latitudes, row/column extraction is not generally an inverse of construction; the original fractional-row ambiguity is preserved.

## Explicit limitations

Not converted: `getClockPositionToWorldVector` (drawing convention), `getDistanceFromEdge` (MapParameters dependency), `mapRelativePositionToPositiveIntRedblob` (alternative index implementation), and `tilesAndNeighborUniqueIndex` (Tile/TileMap dependency). LibGDX JSON Serializer, `InlineHexCoord`, JVM serialization/reflection, and the Vector2 extension method are omitted. There is no Unciv-save importer.

This is mathematical foundation support, not map topology, pathfinding, gameplay, or a playable Roblox project. A host must provide its own loading/integration. CLI-relative requires are used in the public source; a Roblox adapter or build step must resolve module imports.

## Numeric behaviour

- Luau numbers are binary64. Kotlin uses binary32 Float for projection, trigonometry, area/radius operations and cube rounding. The converted projection uses the equivalent exact basis (-1.5, sqrt(3)/2) and (1.5, sqrt(3)/2); it does not reproduce Float rounding of the original clock-angle intermediates.
- Cube rounding explicitly uses nearest-even ties, matching Kotlin `round`. Rectangle/radius rounding uses ties towards positive infinity, matching finite `roundToInt`.
- Row division and fractional vector distance components truncate towards zero. Modulo with positive wrap radius is nonnegative, matching Kotlin `mod`.
- Coordinate factories reject fractional, nonfinite and out-of-int32-range inputs. Arithmetic that would overflow a Kotlin Int fails in coordinate construction rather than wrapping. Count/index arithmetic uses binary64 rather than wrapping int32. No overflow parity is claimed.
- Mathematical APIs require finite numbers; integer upstream parameters remain an integer caller precondition. No JVM NaN/infinity saturation emulation is provided. Equivalent rectangle ratio and wrap radius receive explicit domain checks.

## Verification

Run from the repository root:

```powershell
luau tests/unit/hex.luau
luau-analyze src/map/HexMath.luau src/map/HexCoord.luau tests/unit/hex.luau
```

Verified with official Luau 0.740: 124,497 assertions passed; strict analysis clean. Tests adapt the upstream index uniqueness through ring 100 and coordinate format/parse scenarios from `tests/src/com/unciv/logic/map/HexmathTests.kt`. Additional checks cover actual Unciv neighbor order and clock directions, ring/disc counts, translated centers, wrap seams, negative division/modulo, halfway rounding, projection/inverse over a signed coordinate grid, arithmetic and immutable records.

The upstream Kotlin tests were inspected but not executed. These are source-derived expected-value and invariant checks, not a cross-runtime parity suite. JVM serializer tests are deliberately not represented as passing.
