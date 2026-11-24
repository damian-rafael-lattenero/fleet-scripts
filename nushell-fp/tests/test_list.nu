# test_list.nu — assertions for mods/list.nu. Run via ../test.nu (or directly).
use std/assert
use ../mods/list.nu *

# ── basics: construction, splitting, folding ─────────────────────────────
# replicate
assert equal (replicate 3 "x") [x x x]
assert equal (replicate 0 "x") []
assert equal (replicate (-2) "x") []
# intersperse
assert equal ([1 2 3] | intersperse 0) [1 0 2 0 3]
assert equal ([1] | intersperse 0) [1]
assert equal ([] | intersperse 0) []
# items that are lists survive intersperse (no splice)
assert equal ([[1 1] [2 2]] | intersperse 0) [[1 1] 0 [2 2]]
# span
assert equal ([1 2 3 4] | span {|it| $it < 3}) {taken: [1 2], rest: [3 4]}
assert equal ([1 2] | span {|it| $it > 9}) {taken: [], rest: [1 2]}
assert equal ([1 2] | span {|it| true}) {taken: [1 2], rest: []}
# partition
assert equal ([1 2 3 4] | partition {|it| $it mod 2 == 0}) {yes: [2 4], no: [1 3]}
assert equal ([] | partition {|it| true}) {yes: [], no: []}
# partition split law: yes ++ no is a PERMUTATION of the input (sorted equal)
let part4: record<yes: list<int>, no: list<int>> = ([4 1 3 2] | partition {|it| $it mod 2 == 0})
assert equal ($part4.yes | append $part4.no | sort) ([4 1 3 2] | sort)
# scanl — running sums, inclusive of init
assert equal ([1 2 3] | scanl {|acc: int, it: int| $acc + $it} 0) [0 1 3 6]
assert equal ([] | scanl {|acc: int, it: int| $acc + $it} 7) [7]
# THE scanl law: its last element IS the fold (holds for the empty list too)
assert equal ([1 2 3 4] | scanl {|acc: int, it: int| $acc + $it} 0 | last) ([1 2 3 4] | reduce --fold 0 {|it, acc| $acc + $it})
# unfold — corecursion, null stops
assert equal (unfold 1 {|s: int| if $s > 4 { null } else { {emit: $s, next: ($s + 1)} } }) [1 2 3 4]
assert equal (unfold 9 {|s: int| null }) []
# zip-with truncates at the shorter list
assert equal ([1 2 3] | zip-with [10 20 30 40] {|a: int, b: int| $a + $b}) [11 22 33]
assert equal ([1 2 3 4] | zip-with [10 20] {|a: int, b: int| $a + $b}) [11 22]
# cartesian
assert equal ([1 2] | cartesian ["a" "b"]) [[1 a] [1 b] [2 a] [2 b]]
assert equal ([] | cartesian ["a" "b"]) []

# ── the list applicative ─────────────────────────────────────────────────
# ap-list: every closure applied to every value
assert equal ([2 3] | ap-list [{|x: int| $x * 10}, {|x: int| $x + 1}]) [20 30 3 4]
# lift-a2 over the full cartesian product
assert equal ([1 2] | lift-a2 [10 20] {|a: int, b: int| $a * $b}) [10 20 20 40]
# powerset = filter-m with both choices (2^n, prefix-major order)
assert equal ([1 2] | powerset) [[1 2] [1] [2] []]
assert equal ([1 2 3] | powerset | length) 8
# filter-m with a discriminating predicate forks only where the choice forks
assert equal ([1 2 3] | filter-m {|x: int| if $x == 2 { [true false] } else { [true] } }) [[1 2 3] [1 3]]
# replicate-m: n draws from the same choice — every 2-bit tuple
assert equal (replicate-m 2 [0 1]) [[0 0] [0 1] [1 0] [1 1]]
assert equal (replicate-m 0 [1 2]) [[]]
assert equal (replicate-m 3 [0 1] | length) 8

# ── classic laws over builtins + gaps ────────────────────────────────────
# map fusion (free theorem): each f (each g xs) == each (f . g) xs
# (closures to builtins stay untyped — each declares its param as any and
#  0.117 enforces the exact match)
assert equal ([1 2 3] | each {|x| $x * 2} | each {|x| $x + 1}) ([1 2 3] | each {|x| ($x * 2) + 1})
# reverse is an involution (builtin, pinned as a law)
assert equal ([1 2 3] | reverse | reverse) [1 2 3]
# span split law: taken ++ rest == the original list
let spanL: record<taken: list<int>, rest: list<int>> = ([5 1 3 2] | span {|it| $it > 3})
assert equal ($spanL.taken | append $spanL.rest) [5 1 3 2]
# the list applicative obeys identity: pure id <*> xs == xs
assert equal ([1 2 3] | ap-list [{|x| $x}]) [1 2 3]

# ── pairs ────────────────────────────────────────────────────────────────
assert equal ([[1 "a"] [2 "b"]] | unzip) {first: [1 2], second: [a b]}
assert equal ([[1 "a"] [2 "b"]] | map-fst {|x: int| $x * 10}) [[10 a] [20 b]]
assert equal ([[1 "a"] [2 "b"]] | map-snd {|s: string| $s + "!"}) [[1 "a!"] [2 "b!"]]

print "test_list ok"
