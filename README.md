# ~/Scripts — the fleet's Nushell hub

Every script here is a CLI entry point: effects at the edge, logic in
`lib/`. The gate is the same shape as `nushell-fp`:

```sh
nu ~/Scripts/test.nu      # nu-check every script + lib, run every test
```

## Layout

| Path | What it is |
| --- | --- |
| `*.nu` | the runnable scripts (aliases in `config.nu` point here) |
| `lib/<script>.nu` | each script's PURE core: parsers, predicate tables, projections, verdicts — `export def` only, no effects |
| `tests/test_<script>.nu` | the proofs: `use std/assert` + `use ../lib/<script>.nu *`, one section per rule/parser |
| `test.nu` | the gate: `nu-check` on every root script and lib module, then every `tests/*.nu` (fails by name) |

## Rules for a change

1. Logic that can be answered from its arguments belongs in `lib/`.
   Anything that reads, writes, kills or calls an external stays in the
   script.
2. A new rule/parser/verdict lands WITH its test in the same commit — the
   gate must stay green (`ALL GREEN — N test scripts, M lib modules`).
3. Types are named (`type X = record<...>`) and every `def` is fully
   annotated; dispatch is a predicate table, never an else-if chain.
4. Fixtures are literal text where possible; a live external (git) only
   where its real format is the thing being pinned.
5. The four `zcode-*-deploy.nu` wrappers carry no logic: their test is
   structural (canonical script + nu binary must exist).
