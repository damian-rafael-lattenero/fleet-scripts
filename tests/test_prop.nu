# test_prop.nu — the property harness proving itself on real laws.
use std/assert
use ../mods/prop.nu *
use ../mods/list.nu *
use ../mods/json.nu *

# a true law holds over 100 random samples: sort is idempotent
let sorted: record<tag: string, value: any, error: any> = (for-all {|s| gen-list-int $s} {|xs| ($xs | sort | sort) == ($xs | sort) })
assert equal ($sorted.tag) "ok"
# append doubles the length (persistence law)
let appended: record<tag: string, value: any, error: any> = (for-all {|s| gen-list-int $s} {|xs| ($xs | append $xs | length) == (2 * ($xs | length)) })
assert equal ($appended.tag) "ok"
# span recombination: taken ++ rest == the original list
let spanned: record<tag: string, value: any, error: any> = (for-all {|s| gen-list-int $s} {|xs|
    let s: record<taken: list<int>, rest: list<int>> = ($xs | span {|x| $x < 0})
    ($s.taken | append $s.rest) == $xs
})
assert equal ($spanned.tag) "ok"
# intersperse length law: n items get exactly n-1 separators
let interspersed: record<tag: string, value: any, error: any> = (for-all {|s| gen-list-int $s --max-len 20} {|xs|
    ($xs | intersperse 0 | length) == ((2 * ($xs | length)) - (if ($xs | is-empty) { 0 } else { 1 }))
})
assert equal ($interspersed.tag) "ok"
# flatten/unflatten round-trip holds for every generated record of int leaves
let roundTrip: record<tag: string, value: any, error: any> = (for-all {|s| gen-list-int $s --max-len 8} {|xs|
    let r: record = ({a: {b: $xs}, c: 1})
    ($r | flatten-keys | unflatten-keys) == $r
})
assert equal ($roundTrip.tag) "ok"
# determinism: same seed, same sample
let a: list<int> = (gen-list-int 99)
let b: list<int> = (gen-list-int 99)
assert equal $a $b

# a FALSE law fails, and the counterexample SHRINKS to the empty list
let falseLaw: record<tag: string, value: any, error: any> = (for-all {|s| gen-list-int $s} {|xs| ($xs | length) > 0 } --runs 50 --seed 5)
assert equal ($falseLaw.tag) "err"
assert equal ($falseLaw.error.shrunk) []
# and determinism on failure: the same seed reproduces the same counterexample
let falseAgain: record<tag: string, value: any, error: any> = (for-all {|s| gen-list-int $s} {|xs| ($xs | length) > 0 } --runs 50 --seed 5)
assert equal ($falseLaw.error.sample) ($falseAgain.error.sample)

print "test_prop ok"
