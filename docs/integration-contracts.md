# Integration contracts

These are design contracts for later simulation work, not currently implemented interfaces. Foundation modules use their documented local APIs. Host adapters must not supply hidden replacements for missing converted gameplay rules.

- RulesProvider: validated immutable rules data plus explicit supported-effect identifiers. Unknown effects are rejected.
- RandomSource: seedable next-integer/next-number operations with documented distribution and reproducibility scope.
- Simulation commands: actor ID, action kind and action parameters; generic legality checked in public simulation; player authorization checked by the private host.
- Simulation results: state revision and structured domain events, independent of rendering and networking.
- Visibility: public gameplay determines visible information; private transport only replicates the resulting per-player projection.
- Persistence: public schema/codec and migration logic where converted; private backend reads/writes bytes or tables and owns operational retries and concurrency.
- Clock and scheduling: public turn rules; private wall-clock deadlines, disconnect handling and server lifecycle.

The initial private development environment imports only the verified foundation modules and runs development smoke checks. It does not implement these larger contracts or a playable match. No advanced-game API is represented as complete by a stub.
