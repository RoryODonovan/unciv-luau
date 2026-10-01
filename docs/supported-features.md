# Supported features

Initial foundation milestone: immutable HexCoord, documented HexMath subset, Stat identifiers/classification, mutable Stats arithmetic and aggregates, and ordered string-key Counter. Exact API coverage lives in provenance/hex.json and provenance/stats.json and their linked conversion documents.

Verified: standalone Luau 0.740 runtime tests, strict static analysis, source/provenance hygiene, deterministic generated Roblox-form source. Public foundation tests require no private adapters. Verification does not imply full upstream parity.

Pending: ruleset/effects, map state and generation, resources and visibility, units and movement, combat, cities and production, civilization research/economics/policies, turn simulation, diplomacy/trade/victory, religion/city-state/espionage/events, automation and native save compatibility.

Excluded from this library: upstream LibGDX UI/rendering, Android/Desktop/JVM infrastructure, original networking services and copied media. The private development harness supplies a Studio smoke board only. Future game functionality must be tracked explicitly rather than represented as working placeholders.

The original bounded simulation now implements synthetic seeded map state, adjacent movement/combat/capture, founding, growth, unit production, three technologies, automatic AI turns and bounded victory/loss. These are prototype semantics, not completed upstream conversions. See [simulation API and limitations](simulation.md); all broader Unciv features above remain pending.
