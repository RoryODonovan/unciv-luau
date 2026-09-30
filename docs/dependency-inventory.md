# Dependency inventory and public checks

The machine-readable inventory is `provenance/inventory.json`, generated from Unciv revision `42939c6a2cf31aa76f44ffc033015ad12fece9f5`. It covers all 859 tracked files in `core/src`, `tests` and `android/assets/jsons` in the pinned checkout, including 96 upstream test/build files and 102 data files. No implementation or asset content is copied into the inventory.

| Disposition | Files | Meaning |
| --- | ---: | --- |
| convert | 232 | Planned gameplay/supporting model conversion; no implementation claim |
| defer | 215 | Requires corresponding modules, host contracts or individual data licence audit |
| exclude | 412 | UI, views, JVM/application services or build configuration replaced by integration |

Each entry records its upstream path, content hash, byte count, subsystem, disposition, reason, risk, licence status, implementation status, imports and resolved dependency candidates. `implementationStatus: not-converted` describes the inventory baseline. Current implemented modules belong in separate provenance fragments and the parent-maintained conversion status, never inferred from these planned classifications.

The principal conversion subsystems are ruleset (66 files), map (46), civilization (37), automation (26), battle (15), city (13), trade (6) and stats (6). Foundations and simulation complete the planned source group. Import presence does not automatically make the imported file a conversion target: presentation and service dependencies need interfaces or explicit behavioural replacements.

## Dependency evidence and limits

The extractor records 9,754 Kotlin import declarations and 5,875 distinct per-file internal dependency candidates. It resolves package wildcard imports and declared class/object/interface/typealias/function/property names, and attempts enclosing-symbol resolution for member imports. Wildcards identify candidate files, not actual usage. Multiple symbol candidates stay visible rather than pretending to be one exact dependency.

1,266 internal imports remain unresolved by textual matching. Kotlin extension receivers, overloads, generated declarations, aliases, nested objects and compiler behaviour make a textual index incomplete. Same-package references and fully qualified references without imports are not included. The inventory is a source dependency aid, not a compiler call graph or proof of a complete port. A subsystem audit must inspect unresolved imports and implicit dependencies before implementation.

The classification is an initial path-based planning policy with per-file import evidence. Some files mix useful gameplay with host or presentation effects; their `convert` disposition requires extracting that reusable behaviour, not blindly translating every dependency. Excluded view interfaces may still inform the integration contract design. A later decision to bring a deferred/excluded file into scope needs an explicit documented change.

## Assets and rules data

Every tracked file beneath `android/assets/jsons` is separately enumerated as `unverified-not-imported`: 48 rules/data files, 51 localization files and 3 rendering configuration files. These are inventory records only. A code licence is insufficient evidence to import data, media references, tutorials, translations or borrowed mapping content. Importing any such file requires a file-specific source, licence decision and attribution record. The current library includes none of those assets.

## Reproduce the inventory

Use Node 22 or later and a clean pinned Unciv checkout containing the three scoped directories:

```sh
node tools/inventory.mjs /path/to/Unciv
```

The generator requires the exact pinned HEAD and writes a deterministic inventory to `provenance/inventory.json`. It does not clone, fetch or change the upstream checkout. Inventory classifications are in the generator, so policy changes can be reviewed and reproduced.

## Public verification and tests

The standalone official Luau CLI is the runtime. The public repository intentionally contains no playable Roblox place or host bootstrap. Test scripts can import public modules without Roblox services or unpublished code.

```sh
npm run test:tooling
npm run check
```

`npm run check` runs metadata/hygiene verification, `luau-analyze`, then every `tests/unit/*.luau` script recursively in sorted order. Individual stages are `npm run verify`, `npm run analyze` and `npm test`. Override CLI paths using `LUAU_BIN` and `LUAU_ANALYZE_BIN` when binaries are not on PATH. Windows PowerShell example:

```powershell
$env:LUAU_BIN = 'C:/path/to/luau.exe'
$env:LUAU_ANALYZE_BIN = 'C:/path/to/luau-analyze.exe'
npm run check
```

Verification requires the root licence, attribution file, upstream lock and inventory. Every public Luau module must carry an MPL-2.0 SPDX header, upstream Kotlin path and pinned revision, and must be named in a JSON provenance fragment. Tests also require SPDX headers. Metadata must parse and inventory revision/counts must agree. Obvious Roblox host/service references, tracked private/secrets files and place files are rejected. This is a hygiene gate, not a secret scanner or legal opinion; review remains necessary. Assets require a path-specific licence record before inclusion.

CI downloads the official Linux Luau release 0.740 and uses Node 22. No Roblox authentication or private scripts are needed. The fixed version matches the local toolchain and upstream-lock toolchain metadata; version updates must be coordinated. Release URLs are version pinned, but the workflow does not yet pin a binary checksum.

