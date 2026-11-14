# nushell-fp

Functional-programming library for nushell 0.117+: Haskell-style list
combinators, higher-order combinators over first-class closures, and (growing)
algebraic data types. **Gaps only** — builtins are never re-wrapped.

Before writing new list/table code, check this index first (reuse law): if a
function here covers it, `use` it instead of hand-rolling.

## Usage

```nu
use ~/Projects/nushell-fp/mods/list.nu *
[1 2 3] | intersperse 0
# => [1 0 2 0 3]
```

Run the gate (must be ALL GREEN before any commit):

```nu
nu ~/Projects/nushell-fp/test.nu
```

## Index

### mods/list.nu — list combinators (gaps over builtins)

Builtins already provide: map=`each`, filter=`where`, fold=`reduce`,
`zip`, `chunks`, `uniq`, `flatten`, `transpose`, `interleave`,
`take while`, `skip until`, `sort-by`, `group-by`, `enumerate`.

| function | type | summary |
|---|---|---|
| `replicate` | `n: int, x: any -> list<any>` | exactly n copies of x |
| `intersperse` | `list<any> -> list<any>` | sep between adjacent items (no splice on list items) |
| `span` | `list<any>, closure -> record<taken, rest>` | split at first pred failure |
| `partition` | `list<any>, closure -> record<yes, no>` | disjoint split by pred |
| `scanl` | `list<any>, closure, init -> list<any>` | inclusive prefix fold (running totals) |
| `unfold` | `seed, closure -> list<any>` | anamorphism: step returns {emit, next} or null |
| `zip-with` | `list<any>, other: list<any>, closure -> list<any>` | zipWith, truncates at shorter |
| `cartesian` | `list<any>, other: list<any> -> list<list<any>>` | cartesian product as [a, b] pairs |
| `ap-list` | `list<any>, fs: list<closure> -> list<any>` | <*> for lists: every closure x every value |
| `lift-a2` | `list<any>, other, closure -> list<any>` | liftA2 over the full cartesian product |
| `filter-m` | `list<any>, pred: closure -> list<list<any>>` | filterM: one branch per predicate choice |
| `powerset` | `list<any> -> list<list<any>>` | every sublist (2^n) |
| `replicate-m` | `n: int, ma: list<any> -> list<list<any>>` | n draws from one choice: all tuples |
| `unzip` | `list<list<any>> -> record<first, second>` | pairs -> two lists |
| `map-fst` / `map-snd` | `list<list<any>>, closure -> list<list<any>>` | Bifunctor first/second over pairs |

### mods/combinators.nu — first-class closures

| function | type | summary |
|---|---|---|
| `identity` | `any -> any` | the identity function |
| `konst` | `x: any -> closure` | closure that always yields x |
| `compose` | `f: closure, g: closure -> closure` | (compose f g) x = g (f x) |
| `flip` | `f: closure -> closure` | swap the first two arguments |

### mods/currying.nu — kap-style currying & structure filling

Nushell has no native currying, so this module builds it exactly the way kap
(Kotlin) does: one closure step per argument, partial applications are
values, and records fill field by field from deferred closures.

| function | type | summary |
|---|---|---|
| `curry2` .. `curry23` | `fn: closure -> closure` | the curried() ladder, GENERATED (scripts/gen-curry.nu), Kotlin ceiling 23 |
| `uncurry2` .. `uncurry23` | `fn: closure -> closure` | the inverse ladder, same generator (round-trip laws pinned) |
| `apply-args` | `list<any>, c: closure -> any` | apply a curried chain from a list, one do per rung; short list = partial |
| `papply` | `f: closure, ...fixed -> closure` | fix leading args (kap `.with` by value) |
| `build-record` | `spec: record -> record` | fill record from 0-arg closures (sequential) |
| `build-record-par` | `spec: record -> record` | same, parallel via par-each (order kept) |
| `thread` | `x: any, fs: list<closure> -> any` | left-to-right closure pipeline (`>>>`) |

### mods/algebra.nu — Semigroup/Monoid as operation dictionaries

Typeclasses encode as records {empty, combine}; the laws (associativity,
identity) are test-pinned the way kap's LAWS.md pins them.

| function | type | summary |
|---|---|---|
| `monoid` | `empty: any, combine: closure -> record` | build a monoid dictionary |
| `fold-map` | `list<any>, f: closure, m: record -> any` | THE Foldable star: map into the monoid, combine |
| `mconcat` | `list<any>, m: record -> any` | combine a whole list (fold-map id) |
| `monoid-sum` / `monoid-product` | `-> record` | numbers under + / * |
| `monoid-str` / `monoid-list` | `-> record` | strings / lists under concat |
| `monoid-any` / `monoid-all` | `-> record` | booleans under or / and |

### mods/types.nu — Option/Result ADTs (tagged records)

Uniform shape {tag, value} (and error for Result), law battery mirroring
kap's LAWS.md. The kap ruling holds: traverse-validated accumulates ALL
errors (applicative) and is intentionally NOT a monad; short-circuit lives
in traverse-option / fold-result.

| function | type | summary |
|---|---|---|
| `some` / `none` | `-> record<tag, value>` | Maybe constructors |
| `option-map` / `option-bind` | `record, closure -> record` | fmap / (>>=) |
| `option-match` | `record, 2 closures -> any` | the eliminator (cata) |
| `option-unwrap-or` / `option-or` | `record -> any/record` | fallback / Alternative (<\|>) |
| `option-guard` | `bool -> record` | branch cutter (comprehension filter) |
| `option-join` / `option-compose` | `-> record/closure` | join / kleisli (<=<) |
| `traverse-option` | `list, closure -> record` | first none collapses; later elements untouched |
| `sequence-option` | `list<record> -> record` | list-of-Options -> Option-of-list |
| `ok` / `err` | `-> record<tag, value, error>` | Either constructors |
| `result-map` / `result-map-err` / `result-bimap` | `record, closure -> record` | map success / failure / both |
| `result-bind` / `result-compose` / `result-join` | `record -> record/closure` | (>>=) / (<=<) / join |
| `result-match` / `result-unwrap-or` / `result-or` | `record -> any` | cata / fallback / Alternative |
| `fold-result` | `list, closure, init -> record` | foldM: first err stops the fold |
| `traverse-validated` | `list, closure -> record` | ACCUMULATES every error, in input order |

### mods/fmt.nu — display formatting

| function | type | summary |
|---|---|---|
| `human-num` | `x: int -> string` | the raw -> K -> M ladder (American system); M fires AT the boundary — 1000000 is "1M", never "1000K"; trailing zeros trimmed |

### mods/json.nu — lenses over structured records

Built on the 0.117 machinery (`merge deep` IS deep-merge), filling what
builtins cannot do: paths that only exist at RUNTIME, n-fold layering, and
the dotted-key flattening round-trip.

| function | type | summary |
|---|---|---|
| `get-in` | `record, path: list<any>, default -> any` | runtime path walk (ints index lists); default on any miss |
| `set-in` | `record, path: list<string>, value -> record` | nested write, creates missing levels, path wins over non-records |
| `update-in` | `record, path: list<string>, f: closure -> record` | transform at a path; missing = no-op |
| `deep-merge-all` | `list<record> -> record` | the config stack: defaults \| user \| env (n-fold merge deep) |
| `flatten-keys` | `record -> record` | {a: {b: 1}} -> {"a.b": 1}; lists are leaves |
| `unflatten-keys` | `record -> record` | the inverse; round-trip law pinned |

### mods/async.nu — the applicative over background jobs

The kap `.with(Kap { ... })` graph translated: each deferred value is a
background job that reports to the main mailbox; collection blocks in
`job recv` (zero polling) and `--timeout` is the failure signal (jobs killed,
honest error). In-process async — jobs are threads and die with nu.

| function | type | summary |
|---|---|---|
| `traverse-jobs` | `list<closure> -> list<any>` | run closures concurrently, collect in structure order |
| `build-record-jobs` | `record -> record` | fill a record: every field a job, record lands when the last does |
| `apply-async` | `list<closure>, c: closure -> any` | concurrent deferred args fed into a curried closure (`.with` chain) |

## Examples

- `examples/agents-dashboard.nu` — the daily cross-session agent check: 355
  metadata.json read as PARALLEL JOBS, git branches per repo as a second
  concurrent wave, builtin `join`, `get-in` nested access, and a pretty
  parsed render (dates humanized, tokens on the K/M ladder). Also the
  crucible that hardened traverse-jobs: crashed elements report through
  the mailbox — no silent deadlocks.

## Deliberately NOT translated (and why)

- **Comonad / Arrow** — need laziness or a typed arrow category; a shell has
  neither, and the encoding would be ceremony without the guarantees.
- **MonadTrans / MTL (Reader/State/Error)** — nushell effects are closures +
  pipeline input; `thread` + `papply` + tagged records already cover the
  composition the transformers solve in Haskell.
- **`forever`** — the reactive law: no unbounded loops; use job spawn + recv
  (see async.nu) or LaunchAgents for long-lived work.
- **`when` / `unless` / `void`** — already idiomatic one-liners (`if $cond
  { do $body }`, `each {|| null}`); wrapping builtins is against repo law.

## Roadmap

- Validated variant over records (field names in the error list).
- Property tests with random inputs (the kap Kotest style) beyond the pinned
  law samples.
