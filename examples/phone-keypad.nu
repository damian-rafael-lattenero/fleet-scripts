# phone-keypad.nu — LeetCode 17, the list-APPLICATIVE showcase (Haskell
# sequenceA / Scala for-comprehension over Lists): every letter choice per
# digit combines with every other choice. The combination engine is
# lift-a2 (cartesian product), folded across the digit choices.
use std/assert
use ../mods/list.nu *

# sequence for lists, inline: fold (lift-a2 append-one) over the choice
# sets, seeding with the unit [[]] — the empty product is one empty combo
def all-combos []: list<list<string>> -> list<list<string>> {
    mut acc: list<list<string>> = [[]]
    for set in $in {
        $acc = ($acc | lift-a2 $set {|prefix, letter| $prefix | append [$letter]})
    }
    $acc
}

# (nu has no map<k, v> generic: record<A, B> names FIELDS, so an honest
# string-keyed record is annotated bare `record`)
const KEYPAD: record = {
    "2": [a b c]
    "3": [d e f]
    "4": [g h i]
    "7": [p q r s]
}

# "23" -> 3 x 3 = 9 combos; structure order: first digit varies slowest
let combos23: list<list<string>> = (["2" "3"] | each {|d| $KEYPAD | get -o $d} | all-combos)
assert equal ($combos23 | length) 9
assert equal ($combos23 | first) [a d]
assert equal ($combos23 | last) [c f]
print $"PASS 23: ($combos23 | length) combos, first ($combos23 | first | str join) last ($combos23 | last | str join)"

# "72" crosses the 4-letter key: 4 x 3 = 12
let combos72: list<list<string>> = (["7" "2"] | each {|d| $KEYPAD | get -o $d} | all-combos)
assert equal ($combos72 | length) 12
print $"PASS 72: the 4-letter key gives ($combos72 | length) combos"

# the empty product law: no digits -> exactly ONE combo, the empty one
assert equal ([] | all-combos) [[]]
# unknown digit yields an empty choice set -> zero combos (honest collapse)
assert equal (["2" "?"] | each {|d| $KEYPAD | get -o $d | default []} | all-combos) []
print 'PASS laws: unit for no digits, empty collapses unknown digits'
