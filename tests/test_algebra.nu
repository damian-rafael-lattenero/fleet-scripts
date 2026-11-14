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

print "test_algebra ok"
