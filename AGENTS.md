# Unciv Luau project instructions

Public library of faithfully attributed Unciv Luau conversions. Upstream: https://github.com/yairm210/Unciv at 42939c6a2cf31aa76f44ffc033015ad12fece9f5. Converted source and derivative tests are MPL-2.0. Preserve upstream notices; use an SPDX header and an upstream path/revision comment in converted modules. No copied media, private Roblox integration, secrets or playable place in this repository.

Use strict typed, service-independent Luau. Test with the official Luau CLI. Pure modules must not use game, workspace, Instance or Roblox services. Public tests run outside Studio. Explicitly document partial implementations and intentional numeric/platform differences. Do not claim parity without evidence.

Parallel agents must use assigned separate worktrees and commit only their own files. Do not change another agent's checkout. Do not delegate peer review recursively. Parent owns integration, release metadata, commits and publication. Do not push, create PRs or create repositories from child sessions.
