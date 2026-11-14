# nu-fp

Functional-programming library for nushell 0.117+: Haskell-style list
combinators, higher-order combinators over first-class closures, and (growing)
algebraic data types. **Gaps only** — builtins are never re-wrapped.

Before writing new list/table code, check this index first (reuse law): if a
function here covers it, `use` it instead of hand-rolling.

## Usage

```nu
use ~/Projects/nu-fp/mods/list.nu *
[1 2 3] | intersperse 0
# => [1 0 2 0 3]
```

Run the gate (must be ALL GREEN before any commit):

```nu
nu ~/Projects/nu-fp/test.nu
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

## Roadmap

- `mods/json.nu` — structured-record lenses: get-in / set-in / update-in /
  deep-merge / dotted-key flattening (jq-style traversal over nushell records).
- `mods/types.nu` — ADTs as tagged records: Option (some/none), Result
  (ok/err) with map / bind / match (cata) and law tests.
- `mods/applicative.nu` — traverse over the Result/Option types; error
  accumulation (kap's Validated pattern); parallel variants via `par-each`.
- Property tests for the algebraic laws (scanl/unfold duality, span/partition
  recombination).
