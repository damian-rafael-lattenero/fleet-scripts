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
