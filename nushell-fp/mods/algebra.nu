# algebra.nu — Semigroup and Monoid as operation dictionaries.
#
# Nushell has no typeclasses, so a typeclass is encoded the classic way: a
# RECORD of operations (the dictionary-passing translation). A Monoid here is
# {empty: any, combine: closure} — combine MUST be associative with empty as
# identity (the laws are pinned in tests, mirroring kap's LAWS.md).
#
# Verified live on nushell 0.117.0: closure as a record-field type in
# signatures works; null keeps the uniform record shape.

# Build a monoid from an identity element and an associative combine.
export def monoid [empty: any, combine: closure]: nothing -> record<empty: any, combine: closure> {
    {empty: $empty, combine: $combine}
}

# foldMap :: (a -> m) -> t a -> m — map every element into the monoid, then
# combine everything. THE star reduction of Foldable.
export def fold-map [f: closure, m: record<empty: any, combine: closure>]: list<any> -> any {
    let items: list<any> = $in
    $items | each {|x| do $f $x} | reduce --fold ($m.empty) {|it, acc| do $m.combine $acc $it}
}

# mconcat :: [a] -> a — combine a whole list with the monoid (fold-map id).
export def mconcat [m: record<empty: any, combine: closure>]: list<any> -> any {
    let items: list<any> = $in
    $items | fold-map {|x| $x} $m
}

# ── Ready-made monoids (the day-to-day ones) ──────────────────────────────

# Numbers under addition (empty 0).
export def monoid-sum []: nothing -> record<empty: any, combine: closure> {
    monoid 0 {|a: int, b: int| $a + $b}
}

# Numbers under multiplication (empty 1).
export def monoid-product []: nothing -> record<empty: any, combine: closure> {
    monoid 1 {|a: int, b: int| $a * $b}
}

# Strings under concatenation (empty "").
export def monoid-str []: nothing -> record<empty: any, combine: closure> {
    monoid "" {|a: string, b: string| $a + $b}
}

# Lists under append (empty []).
export def monoid-list []: nothing -> record<empty: any, combine: closure> {
    monoid [] {|a: list<any>, b: list<any>| $a | append $b}
}

# Booleans under logical or (empty false) — "does any element satisfy".
export def monoid-any []: nothing -> record<empty: any, combine: closure> {
    monoid false {|a: bool, b: bool| $a or $b}
}

# Booleans under logical and (empty true) — "do all elements satisfy".
export def monoid-all []: nothing -> record<empty: any, combine: closure> {
    monoid true {|a: bool, b: bool| $a and $b}
}
