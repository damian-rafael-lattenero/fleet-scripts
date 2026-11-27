# ~/Scripts — the fleet's Nushell hub

Every operational script on this machine lives here, and answers to one
stable name: `fleet <verb>` (the symlink `~/.local/bin/fleet`). Effects at
the edge, logic in `lib/`, a proof for everything.

```sh
nu ~/Scripts/test.nu      # nu-check every script + lib, run every test
fleet list                # every verb and the script behind it
```

## Layout

| Path | What it is |
| --- | --- |
| `scripts/<name>.nu` | the runnable CLIs: effects, I/O, the `main` edge |
| `scripts/fleet.nu` | THE door: `fleet <verb> [args...]`, `list`, `help`, `healthcheck` |
| `scripts/hooks/` | the house's git hooks (symlinked from `~/.zcode/hooks` and the repos) |
| `lib/<name>.nu` | each script's PURE core: parsers, predicate tables, projections, verdicts — `export def` only, no effects |
| `tests/lib/<name>.nu` | the proofs of `lib/<name>.nu` |
| `tests/scripts/<name>.nu` | the end-to-end invariants of `scripts/<name>.nu` (structure, exit codes, symlinks) |
| `tests/census.nu` | the law: every `.nu` on the machine has its test |
| `nushell-fp/` | the house FP library (git subtree — history preserved) |
| `test.nu` | the gate: `nu-check` everything, then run every test (fails by name) |

## How the world consumes it

| Consumer | Mechanism |
| --- | --- |
| a script inside the hub | relative `use ../lib/x.nu *` |
| a script inside a repo | ONE absolute line `use /Users/lattenero/Scripts/lib/x.nu *` |
| Kotlin / TS / launchd | `fleet <verb> [args]` — no clone, no path |
| interactive shell | the `fleet` alias in config.nu |
| nushell-fp | `use /Users/lattenero/Scripts/nushell-fp/mods/x.nu` |

No repo clones the hub. The only cross-repo lines are those absolute `use`s,
and `tests/scripts/census` verifies they point inside the hub.

## Rules for a change

1. Logic that can be answered from its arguments belongs in `lib/`.
   Anything that reads, writes, kills or calls an external stays in the
   script.
2. **Every `.nu` has its test** (the owner's law, 24/11). A new
   rule/parser/verdict lands WITH its test in the same commit; an
   effect-only script is proven structurally (nu-check, its paths/labels
   resolve, its `--check`/`--dry-run` exits 0).
3. Types are named (`type X = record<...>`) and every `def` is fully
   annotated; dispatch is a predicate table, never an else-if chain.
4. Fixtures are literal text where possible; a live external (git) only
   where its real format is the thing being pinned.
5. A new script is a new verb: add `scripts/<name>.nu`, its test, and
   `fleet list` shows it — the door discovers the glob.
6. The four thin deploy wrappers (`deploy-bot`, `deploy-brain`, `deploy-fork`,
   `deploy-whatsapp`) carry no logic: their test is structural (canonical
   script + nu binary must exist).
