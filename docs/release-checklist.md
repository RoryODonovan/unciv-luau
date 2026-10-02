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
