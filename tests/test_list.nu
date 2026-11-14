# test_list.nu — assertions for mods/list.nu. Run via ../test.nu (or directly).
use std/assert
use ../mods/list.nu *

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
# scanl — running sums, inclusive of init
assert equal ([1 2 3] | scanl {|acc: int, it: int| $acc + $it} 0) [0 1 3 6]
assert equal ([] | scanl {|acc: int, it: int| $acc + $it} 7) [7]
# unfold — corecursion, null stops
assert equal (unfold 1 {|s: int| if $s > 4 { null } else { {emit: $s, next: ($s + 1)} } }) [1 2 3 4]
assert equal (unfold 9 {|s: int| null }) []
# zip-with truncates at the shorter list
assert equal ([1 2 3] | zip-with [10 20 30 40] {|a: int, b: int| $a + $b}) [11 22 33]
assert equal ([1 2 3 4] | zip-with [10 20] {|a: int, b: int| $a + $b}) [11 22]
# cartesian
assert equal ([1 2] | cartesian ["a" "b"]) [[1 a] [1 b] [2 a] [2 b]]
assert equal ([] | cartesian ["a" "b"]) []

print "test_list ok"
