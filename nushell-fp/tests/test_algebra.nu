# test_algebra.nu — algebraic laws for mods/algebra.nu (mirroring kap LAWS.md).
use std/assert
use ../mods/algebra.nu *

# ── Monoid laws ──────────────────────────────────────────────────────────
# Identity: combining with empty changes nothing (left and right)
assert equal (do (monoid-sum).combine ((monoid-sum).empty) 5) 5
assert equal (do (monoid-sum).combine 5 ((monoid-sum).empty)) 5
# Associativity: (a <> b) <> c == a <> (b <> c)
let s: record<empty: any, combine: closure> = (monoid-sum)
assert equal (do $s.combine (do $s.combine 1 2) 3) (do $s.combine 1 (do $s.combine 2 3))
# mconcat over the empty list is exactly empty
assert equal ([] | mconcat (monoid-sum)) 0
assert equal ([] | mconcat (monoid-str)) ""

# ── fold-map = map then combine ──────────────────────────────────────────
assert equal ([1 2 3] | fold-map {|x: int| $x} (monoid-sum)) 6
# fold-map with a real mapping: word lengths summed
assert equal (["nu" "shell"] | fold-map {|w: string| ($w | str length)} (monoid-sum)) 7
# the classic foldMap-any / foldMap-all pattern
assert equal ([2 4 6] | fold-map {|x: int| ($x mod 2) == 0} (monoid-all)) true
assert equal ([2 5 6] | fold-map {|x: int| ($x mod 2) == 0} (monoid-all)) false
assert equal ([1 3 5] | fold-map {|x: int| $x > 4} (monoid-any)) true
# monoid-list concatenates
assert equal ([[1 2] [3] []] | mconcat (monoid-list)) [1 2 3]
# monoid-str concatenates
assert equal (["a" "b" "c"] | mconcat (monoid-str)) "abc"
# product monoid over a list
assert equal ([1 2 3 4] | mconcat (monoid-product)) 24

# ── the endomorphism monoid: closures under composition ──────────────────
# empty = identity, combine = compose — the laws hold AND mconcat [f g h]
# equals threading: do (mconcat [f g h] endo) x == thread x [f g h]
use ../mods/combinators.nu *
use ../mods/currying.nu *
let endo: record<empty: any, combine: closure> = (monoid {|x: int| $x} {|f: closure, g: closure| compose $f $g})
# identity law: combining with the identity closure changes nothing
let dbl: closure = {|x: int| $x * 2}
assert equal (do (do $endo.combine $endo.empty $dbl) 5) 10
assert equal (do (do $endo.combine $dbl $endo.empty) 5) 10
# associativity with three closures
let inc: closure = {|x: int| $x + 1}
let dec: closure = {|x: int| $x - 3}
let left3: closure = (do $endo.combine (do $endo.combine $inc $dbl) $dec)
let right3: closure = (do $endo.combine $inc (do $endo.combine $dbl $dec))
assert equal (do $left3 10) (do $right3 10)
# THE bridge law: mconcat of the endo monoid IS thread (left-to-right order)
assert equal (do ([$inc $dbl $dec] | mconcat $endo) 10) (thread 10 [$inc $dbl $dec])

# ── the First monoid ≡ option-or: the first some wins, none is empty ────
use ../mods/types.nu *
let firstM: record<empty: any, combine: closure> = (monoid (none) {|a: record<tag: string, value: any>, b: record<tag: string, value: any>| $a | option-or $b})
assert equal ([(some 1) (none) (some 3)] | mconcat $firstM) (some 1)
assert equal ([(none) (none)] | mconcat $firstM) (none)
# identity law for First, both sides
assert equal ([(none) (some 2)] | mconcat $firstM) (some 2)
assert equal ([(some 2) (none)] | mconcat $firstM) (some 2)

# ── fold-map / builtin equivalence (the same denotation, two roads) ─────
assert equal ([1 2 3 4 5] | fold-map {|x: int| $x} (monoid-sum)) ([1 2 3 4 5] | math sum)
assert equal (["a" "bb" "ccc"] | fold-map {|s: string| ($s | str length)} (monoid-sum)) 6

print "test_algebra ok"
