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

# ── the classic property corpus (swlaschin categories: involution,
#    fusion, invariant-permutation, partial-round-trip) ────────────────────
# reverse is an involution: reverse . reverse == id
let involution: record<tag: string, value: any, error: any> = (for-all {|s| gen-list-int $s} {|xs| ($xs | reverse | reverse) == $xs })
assert equal ($involution.tag) "ok"
# map fusion (free theorem): each f . each g == each (f . g)
# (params stay untyped inside property closures — the flow type is any)
let fusion: record<tag: string, value: any, error: any> = (for-all {|s| gen-list-int $s} {|xs|
    ($xs | each {|x| $x + 1} | each {|x| $x * 2}) == ($xs | each {|x| ($x + 1) * 2})
})
assert equal ($fusion.tag) "ok"
# partition permutation: sorted (yes ++ no) == sorted xs — nothing lost, nothing invented
let permLaw: record<tag: string, value: any, error: any> = (for-all {|s| gen-list-int $s} {|xs|
    let p: record<yes: list, no: list> = ($xs | partition {|x| $x mod 2 == 0})
    ($p.yes | append $p.no | sort) == ($xs | sort)
})
assert equal ($permLaw.tag) "ok"
# scanl's last element is the fold — including the empty list ([init] vs init)
let scanlLaw: record<tag: string, value: any, error: any> = (for-all {|s| gen-list-int $s} {|xs|
    ($xs | scanl {|acc, it| $acc + $it} 0 | last) == ($xs | reduce --fold 0 {|it, acc| $acc + $it})
})
assert equal ($scanlLaw.tag) "ok"
# deep-merge-all associativity over generated layers: grouping never matters
let assocLaw: record<tag: string, value: any, error: any> = (for-all {|s| gen-list-int $s --max-len 6} {|xs|
    let l1: record = {v: $xs}
    let l2: record = {v: 9, w: 1}
    let l3: record = {w: 2}
    let m12: record = ([$l1 $l2] | deep-merge-all)
    let m23: record = ([$l2 $l3] | deep-merge-all)
    ([$m12 $l3] | deep-merge-all) == ([$l1 $m23] | deep-merge-all)
})
assert equal ($assocLaw.tag) "ok"

# a FALSE law fails, and the counterexample SHRINKS to the empty list
let falseLaw: record<tag: string, value: any, error: any> = (for-all {|s| gen-list-int $s} {|xs| ($xs | length) > 0 } --runs 50 --seed 5)
assert equal ($falseLaw.tag) "err"
assert equal ($falseLaw.error.shrunk) []
# and determinism on failure: the same seed reproduces the same counterexample
let falseAgain: record<tag: string, value: any, error: any> = (for-all {|s| gen-list-int $s} {|xs| ($xs | length) > 0 } --runs 50 --seed 5)
assert equal ($falseLaw.error.sample) ($falseAgain.error.sample)

print "test_prop ok"
