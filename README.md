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
| `curry2` .. `curry5` | `f: closure -> closure` | hand-written curried() rungs |
| `curry6` .. `curry23` | `f: closure -> closure` | GENERATED LADDER (scripts/gen-curry.nu), Kotlin ceiling 23 |
| `apply-args` | `list<any>, c: closure -> any` | apply a curried chain from a list, one do per rung; short list = partial |
| `uncurry2` | `g: closure -> closure` | inverse of curry2 (round-trip law) |
| `papply` | `f: closure, ...fixed -> closure` | fix leading args (kap `.with` by value) |
| `build-record` | `spec: record -> record` | fill record from 0-arg closures (sequential) |
| `build-record-par` | `spec: record -> record` | same, parallel via par-each (order kept) |
| `thread` | `x: any, fs: list<closure> -> any` | left-to-right closure pipeline (`>>>`) |

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

## Roadmap

- `mods/json.nu` — structured-record lenses: get-in / set-in / update-in /
  deep-merge / dotted-key flattening (jq-style traversal over nushell records).
- `mods/types.nu` — ADTs as tagged records: Option (some/none), Result
  (ok/err) with map / bind / match (cata) and law tests.
- Validated-style error accumulation for the async applicative (kap's
  traverse that collects ALL errors instead of failing on the first).
- Property tests for the algebraic laws (scanl/unfold duality, span/partition
  recombination, curry/uncurry round-trip).
