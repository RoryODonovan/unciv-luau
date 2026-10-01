# Attribution and licensing

This library contains adaptations of Unciv, an open-source strategy game maintained by yairm210 and the Unciv contributors: https://github.com/yairm210/Unciv.

Pinned source revision: `42939c6a2cf31aa76f44ffc033015ad12fece9f5`.

Unciv-derived source and derivative tests are provided under Mozilla Public License 2.0. The original license is reproduced without modification in LICENSE. Existing notices must remain intact. Per-module source links, supported functions, omissions and differences are recorded in provenance/ and docs/; consult those before reuse. Contributors retain their respective copyrights. Conversion tooling and project-authored public documentation are also provided under MPL-2.0 unless a file explicitly states another license.

Upstream contributor history: https://github.com/yairm210/Unciv/graphs/contributors. Immutable source links use the revision above rather than the changing master branch. Repository authorship of a conversion does not imply authorship of the original algorithms.

No Unciv artwork, sound, logos or complete rules datasets are included in this release. Unciv media have separate licensing and attribution requirements: https://github.com/yairm210/Unciv/blob/42939c6a2cf31aa76f44ffc033015ad12fece9f5/docs/Credits.md. Audit individual files and their original sources before importing any media or datasets. Code licensing does not automatically cover all content.

MPL obligations apply to files containing covered code. Independently authored integration in separate files can form a larger work under separate terms. A private folder does not exempt converted code from distribution obligations. When distributing covered executable code, provide recipients timely access to the corresponding covered source and its license. Our Roblox integration must display a public source/attribution link and keep shipped modifications to covered modules available. See https://www.mozilla.org/en-US/MPL/2.0/FAQ/ and LICENSE sections 3.1-3.4.

This is an independent adaptation and is not endorsed by the Unciv project, Roblox, or the owners of Civilization. No trademark rights are granted by this repository's source license.

Simulation Mechanics partially extracts BattleDamage.kt and city/managers/CityPopulationManager.kt at the pinned upstream revision; see provenance/simulation-mechanics.json. Game.luau and Rules.luau are original MPL-2.0 synthetic prototype code, not upstream gameplay conversions; see provenance/simulation-original.json and docs/simulation.md.

MapSizes.luau adapts the five predefined names/radii from core/src/com/unciv/logic/map/MapSize.kt at the pinned revision; see provenance/map-sizes.json. The surrounding land map generation and simulation remain original bounded implementations.
