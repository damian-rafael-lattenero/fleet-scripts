# list.nu — Haskell-style list combinators for nushell.
# Gaps only: builtins already cover map (each), filter (where), fold (reduce),
# zip, chunks, uniq, flatten, transpose, interleave, take while, skip until,
# sort-by, group-by. Never re-wrap those.
# Syntax verified live against nushell 0.117.0.

# Replicate `x` exactly `n` times (Haskell `replicate`).
export def replicate [n: int, x: any]: nothing -> list<any> {
    if $n <= 0 { return [] }
    1..$n | each {|| $x }
}

# Insert `sep` between every two adjacent items (Haskell `intersperse`).
# Trap: `append` splices list args — wrap each value in [.] so items that are
# themselves lists still enter as single elements.
export def intersperse [sep: any]: list<any> -> list<any> {
    let items: list<any> = $in
    if ($items | is-empty) { return [] }
    let head: any = $items | first
    let tail: list<any> = $items | skip 1
    $tail | reduce --fold [$head] {|it, acc| $acc | append [$sep] | append [$it]}
}

# Split at the first item where `pred` fails (Haskell `span`).
export def span [pred: closure]: list<any> -> record<taken: list<any>, rest: list<any>> {
    let items: list<any> = $in
    let n: int = ($items | enumerate | take while {|row| do $pred $row.item} | length)
    {taken: ($items | first $n), rest: ($items | skip $n)}
}

# Split items into disjoint yes/no lists by `pred` (Haskell `partition`).
export def partition [pred: closure]: list<any> -> record<yes: list<any>, no: list<any>> {
    let items: list<any> = $in
    {yes: ($items | where {|it| do $pred $it}), no: ($items | where {|it| not (do $pred $it)})}
}

# Inclusive prefix fold: [init, f init x1, f (f init x1) x2, ...] (Haskell `scanl`).
export def scanl [f: closure, init: any]: list<any> -> list<any> {
    let items: list<any> = $in
    $items | reduce --fold [$init] {|it, acc| $acc | append (do $f ($acc | last) $it)}
}

# Anamorphism: grow a list from `seed`. `step` receives the current seed and
# returns {emit: any, next: any}, or null to stop. Termination is a contract
# of `step` — the library corecursion is caller-owned, not library-bounded.
export def unfold [seed: any, step: closure]: nothing -> list<any> {
    mut out: list<any> = []
    mut cur: any = $seed
    loop {
        let step_result: any = do $step $cur
        if $step_result == null { break }
        $out = ($out | append $step_result.emit)
        $cur = $step_result.next
    }
    $out
}

# Pairwise combine both lists with `f`, truncating at the shorter (Haskell `zipWith`).
export def zip-with [other: list<any>, f: closure]: list<any> -> list<any> {
    zip $other | each {|pair| do $f $pair.0 $pair.1}
}

# Cartesian product as [a, b] pairs: input x other.
export def cartesian [other: list<any>]: list<any> -> list<list<any>> {
    let left: list<any> = $in
    $left | each {|a| $other | each {|b| [$a, $b]} } | flatten
}

# ── The list APPLICATIVE (nondeterminism) ─────────────────────────────────
# In Haskell the list Applicative is combinatorics: <*> takes every function
# from the left list with every value from the right one.

# <*> for lists: apply every closure in `fs` to every input value.
export def ap-list [fs: list<closure>]: list<any> -> list<any> {
    let xs: list<any> = $in
    $fs | cartesian $xs | each {|pair| do $pair.0 $pair.1}
}

# liftA2 for lists: combine input and `other` over the FULL cartesian
# product. lift-a2 (*) [1 2] [10 20] == [10 20 20 40].
export def lift-a2 [other: list<any>, f: closure]: list<any> -> list<any> {
    let xs: list<any> = $in
    $xs | cartesian $other | each {|pair| do $f $pair.0 $pair.1}
}

# filterM with a list-valued predicate: every choice combination survives —
# filter-m with both choices is the powerset. Each kept prefix forks into
# one branch per choice the predicate returns.
export def filter-m [pred: closure]: list<any> -> list<list<any>> {
    let xs: list<any> = $in
    $xs | reduce --fold [[]] {|x, acc|
        $acc | each {|prefix| (do $pred $x) | each {|choice|
            if $choice { $prefix | append [$x] } else { $prefix }
        }} | flatten
    }
}

# The powerset: every sublist of the input.
export def powerset []: list<any> -> list<list<any>> {
    let xs: list<any> = $in
    $xs | filter-m {|| [true false]}
}

# replicateM for lists: n draws from the same nondeterministic choice —
# replicate-m 3 [0 1] is every 3-bit tuple (test matrices, combos).
export def replicate-m [n: int, ma: list<any>]: nothing -> list<list<any>> {
    if $n <= 0 { return [[]] }
    1..$n | reduce --fold [[]] {|_, acc|
        $acc | each {|prefix| $ma | each {|x| $prefix | append [$x]} } | flatten
    }
}

# ── Pairs (the Bifunctor-on-tuples staples) ──────────────────────────────

# unzip: list of pairs -> two lists.
export def unzip []: list<list<any>> -> record<first: list<any>, second: list<any>> {
    let pairs: list<list<any>> = $in
    {first: ($pairs | each {|p| $p.0}), second: ($pairs | each {|p| $p.1})}
}

# first for pairs: map the closure over the left element of every pair.
export def map-fst [f: closure]: list<list<any>> -> list<list<any>> {
    $in | each {|pair| [(do $f $pair.0), $pair.1]}
}

# second for pairs: map the closure over the right element of every pair.
export def map-snd [f: closure]: list<list<any>> -> list<list<any>> {
    $in | each {|pair| [$pair.0, (do $f $pair.1)]}
}
