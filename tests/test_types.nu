# test_types.nu — ADT laws for mods/types.nu, mirroring kap's LAWS.md.
use std/assert
use ../mods/types.nu *

# ── Option: functor laws ─────────────────────────────────────────────────
# identity: map id == id (some and none)
assert equal (some 5 | option-map {|x: int| $x}) (some 5)
assert equal (none | option-map {|x| $x}) (none)
# composition: map f then g == map (g . f)
let f: closure = {|x: int| $x + 1}
let g: closure = {|x: int| $x * 2}
assert equal (some 5 | option-map $f | option-map $g) (some 5 | option-map {|x: int| do $g (do $f $x)})
assert equal (some 5 | option-map $f | option-map $g) (some 12)

# ── Option: monad laws ───────────────────────────────────────────────────
# left identity: (some x) >>= f == f x
let halfEven: closure = {|x: int| if $x mod 2 == 0 { some ($x / 2) } else { none }}
assert equal (some 10 | option-bind $halfEven) (do $halfEven 10)
assert equal (some 10 | option-bind $halfEven) (some 5)
# right identity: m >>= some == m
assert equal (some 7 | option-bind {|x: int| some $x}) (some 7)
assert equal (none | option-bind {|x: int| some $x}) (none)
# associativity: (m >>= f) >>= g == m >>= (x -> f x >>= g)
let add1: closure = {|x: int| some ($x + 1)}
let mul3: closure = {|x: int| some ($x * 3)}
assert equal ((some 4 | option-bind $add1) | option-bind $mul3) (some 4 | option-bind {|x: int| do $add1 $x | option-bind $mul3})
assert equal ((some 4 | option-bind $add1) | option-bind $mul3) (some 15)

# ── Option: the rest of the interface ────────────────────────────────────
assert equal (some 5 | option-match {|x: int| $"got ($x)"} {|| "nothing"}) "got 5"
assert equal (none | option-match {|x| "got"} {|| "nothing"}) "nothing"
assert equal (none | option-unwrap-or 99) 99
assert equal (some 5 | option-unwrap-or 99) 5
assert equal (none | option-or (some 3)) (some 3)
assert equal (some 1 | option-or (some 3)) (some 1)
assert equal (some 1 | option-or (none)) (some 1)
assert equal (option-guard (1 < 2)) (some null)
assert equal (option-guard (2 < 1)) (none)
assert equal (some (some 3) | option-join) (some 3)
assert equal (some (none) | option-join) (none)
assert equal (none | option-join) (none)
# kleisli composition (f then g): x -> g(f(x))
assert equal (do (option-compose $add1 $halfEven) 4) (none)      # add1(4)=5, odd -> none
assert equal (do (option-compose $add1 $halfEven) 3) (some 2)    # add1(3)=4, even -> some 2

# traverse-option: the first none collapses everything, nothing later runs
assert equal ([1 2 3] | traverse-option {|x: int| if $x == 2 { none } else { some ($x * 10) } }) (none)
assert equal ([1 2 3] | traverse-option {|x: int| some ($x * 10)}) (some [10 20 30])
# short-circuit proof: touching element 3 would explode — and it never does
assert equal ([1 2 3] | traverse-option {|x: int|
    if $x == 3 { error make {msg: "element 3 was touched after the none"} }
    if $x == 2 { none } else { some $x }
}) (none)
# sequence flips the contexts (constructor calls need parens inside literals)
assert equal ([(some 1) (some 2)] | sequence-option) (some [1 2])
assert equal ([(some 1) (none)] | sequence-option) (none)

# ── Result: same law battery, error channel edition ─────────────────────
let okAdd1: closure = {|x: int| ok ($x + 1)}
let okMul3: closure = {|x: int| ok ($x * 3)}
assert equal (ok 5 | result-map {|x: int| $x + 1}) (ok 6)
assert equal (err "boom" | result-map {|x| $x}) (err "boom")
assert equal (err "boom" | result-map-err {|e: string| $e + "!"}) (err "boom!")
assert equal (ok 5 | result-map-err {|e| $e}) (ok 5)
assert equal (ok 5 | result-bimap {|x: int| $x * 2} {|e| $e}) (ok 10)
assert equal (err "e" | result-bimap {|x| $x} {|e: string| $e + "!"}) (err "e!")
# monad laws
assert equal (ok 10 | result-bind $okAdd1) (do $okAdd1 10)
assert equal (ok 7 | result-bind {|x: int| ok $x}) (ok 7)
assert equal ((ok 4 | result-bind $okAdd1) | result-bind $okMul3) (ok 4 | result-bind {|x: int| do $okAdd1 $x | result-bind $okMul3})
# bind short-circuits on err
assert equal (err "stop" | result-bind {|x: int| ok ($x + 1)}) (err "stop")
assert equal (ok 5 | result-match {|x: int| $"ok=($x)"} {|e: string| $"err=($e)"}) "ok=5"
assert equal (err "bad" | result-match {|x| "ok"} {|e: string| $"err=($e)"}) "err=bad"
assert equal (err "bad" | result-unwrap-or 0) 0
assert equal (ok 5 | result-unwrap-or 0) 5
assert equal (err "a" | result-or (ok 2)) (ok 2)
assert equal (ok 1 | result-or (err "b")) (ok 1)
assert equal (ok (ok 3) | result-join) (ok 3)
assert equal (ok (err "inner") | result-join) (err "inner")
assert equal (err "outer" | result-join) (err "outer")
# kleisli: the first error survives the composition
assert equal (do (result-compose $okAdd1 {|x: int| if $x > 5 { ok $x } else { err "too small" }}) 4) (err "too small")

# fold-result: foldM — the first err stops the fold, later steps never run
assert equal ([1 2 3] | fold-result {|acc: int, x: int| ok ($acc + $x)} 100) (ok 106)
assert equal ([1 2 3] | fold-result {|acc: int, x: int| if $x == 2 { err $"bad at ($x)" } else { ok ($acc + $x) }} 0) (err "bad at 2")
# short-circuit proof: step 3 would explode — the err at 2 stops the fold first
assert equal ([1 2 3] | fold-result {|acc: int, x: int|
    if $x == 3 { error make {msg: "step 3 ran after the err"} }
    if $x == 2 { err "halt" } else { ok ($acc + $x) }
} 0) (err "halt")

# ── Validated: accumulation, the kap ruling ──────────────────────────────
# every element inspected, ALL errors collected in input order
let validate: closure = {|x: int| if $x > 0 { ok $x } else { err $"negative: ($x)" }}
assert equal ([1 2 3] | traverse-validated $validate) (ok [1 2 3])
assert equal ([-1 2 -3] | traverse-validated $validate) (err ["negative: -1" "negative: -3"])
# accumulation vs short-circuit: same shape, two semantics
assert equal ([-1 2 -3] | traverse-option {|x: int| if $x > 0 { some $x } else { none }}) (none)

print "test_types ok"
