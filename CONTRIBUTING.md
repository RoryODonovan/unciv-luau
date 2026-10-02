# Contributing

Use the pinned upstream revision in upstream.lock.json. Convert only inventoried, reviewed source scopes. Each converted module needs MPL notices, exact Kotlin source references, a provenance fragment, explicit supported/omitted APIs and meaningful tests. Preserve existing notices and original author credit; do not present a translation as independently authored gameplay.

Run npm run test:tooling, npm run test:export, npm run check and npm run check:roblox. Regenerate roblox/ with npm run export:roblox when src/ changes and commit the matching generated source and manifest. The Roblox form remains covered public source; no private conversion step may hide shipped modifications.

Public src modules must use strict service-independent Luau. Avoid Roblox globals and implicit host dependencies. Document numeric, mutation and ordering differences, and reject unsupported rules explicitly. Keep fixtures minimal. Importing rules data, translations, artwork or audio needs an individual licence and source audit before files enter this repository.

For parallel implementation use separate assigned worktrees; one agent owns each changed file. The project owner integrates, tests and publishes changes. Do not include private integration, credentials, compiled places or player data.
