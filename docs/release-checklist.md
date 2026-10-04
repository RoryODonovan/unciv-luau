# Release checklist

- Pin upstream and verify source/reference hashes.
- Update every module's conversion status, notices, source mapping and tested limitations.
- Run runtime tests and official Luau static analysis; check public-source hygiene.
- Audit the exact tracked release files for private scripts, credentials, assets and unlicensed data.
- Publish corresponding covered source for distributed executable versions.
- Pin the private integration to a public library Git commit and verify vendored module hashes.
- Build the private Rojo development place and run Studio smoke checks when a connected session is available.
- Confirm experience credits expose the public source and licence notices before any Roblox publication.
- Do not claim full port, full game, native save compatibility or complete rules support until separately verified.

## Golden replays

`npm run check` includes the corpus through a Node adapter for baseline I/O. Run it alone with `node tests/golden/run.mjs`. Default: 12 games (Quick/Standard/Full × Hex/Sphere × seeds 7919/15838, barbarians on/off, Normal). Full: 48 games with fixed seeds `7919 × 1..8`, barbarians on at odd indices. PowerShell:

```powershell
$env:GOLDEN_FULL='1'; node tests/golden/run.mjs; Remove-Item Env:GOLDEN_FULL
$env:GOLDEN_UPDATE='1'; node tests/golden/run.mjs; Remove-Item Env:GOLDEN_UPDATE
```

Updates warn loudly, always regenerate all 48 games, and replace `tests/golden/baseline.json` only after success. Review the diff. **A PR that changes golden hashes must say why in its description; refactors must not change them.**

Balance-harness options: radii 10/15/20, limits 45/80/120, culture thresholds 4/6/6, implicit policy growth 50/63/140; corresponding sphere frequencies 6/8/12 (`MapSizes`). Zero humans are unsupported: player 1 follows `base-content.luau`'s first-city/first-available-research/end-turn policy; player 2 uses engine AI.

Hash the complete save and both fog snapshots after founding, every tenth completed round and at victory. Round-10 checkpoints usually hold state round 11; final records include round, phase, winner and victory type. Both modes also replay the 12 default games with restore after **every** EndTurn, checking all three hashes. Failures name game, checkpoint and hash, with expected/actual values.

Canonical encoding sorts object keys, preserves array order, escapes strings and emits exact integers/`%.17g` doubles without rounding or filtering. Empty tables mean `{}` (Luau has no array/object identity). FNV-1a 64-bit uses exact 32-bit limbs and reference vectors. Keep the pinned CLI; investigate any platform differences. This fixed corpus provides non-cryptographic regression evidence, not all-game equality or upstream Unciv parity. Adapter failure/update tests: `node --test tests/golden/run.test.mjs`.
