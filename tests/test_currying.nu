# test_currying.nu — assertions for mods/currying.nu (kap-translated laws).
# Order: the mechanism (proven ONCE) → idiomatic application → partials as
# values → uncurry round-trip laws → record building → thread pipeline.
use std/assert
use ../mods/currying.nu *

# ── the mechanism, proven once ────────────────────────────────────────────
# Each rung of a curried chain is one `do`. Callers should NOT chain nested
# do's — the idioms below (apply-args, uncurry) exist precisely to avoid
# them. This line is the only nested-do in the suite: it proves closures
# nest and each rung holds exactly one argument.
assert equal (do (do (curry2 {|a: int, b: int| $a - $b}) 10) 3) 7

# ── idiomatic application: the arg list rides the pipeline ────────────────
# apply-args walks the rungs one `do` per element — no nesting needed.
assert equal ([1 2 3] | apply-args (curry3 {|a: int, b: int, c: int| $a * 100 + $b * 10 + $c})) 123
assert equal ([1 2 3 4] | apply-args (curry4 {|a: int, b: int, c: int, d: int| $a + $b + $c + $d})) 10
assert equal ([1 2 3 4 5] | apply-args (curry5 {|a: int, b: int, c: int, d: int, e: int| $a * 10000 + $b * 1000 + $c * 100 + $d * 10 + $e})) 12345

# the FULL generated ladder, arity 2..23, through the one idiom
# (each expected value is the sum of 1..n, so arg order is proven too)
assert equal (seq 1 2 | apply-args (curry2 {|...xs| $xs | math sum})) 3
assert equal (seq 1 3 | apply-args (curry3 {|...xs| $xs | math sum})) 6
assert equal (seq 1 4 | apply-args (curry4 {|...xs| $xs | math sum})) 10
assert equal (seq 1 5 | apply-args (curry5 {|...xs| $xs | math sum})) 15
assert equal (seq 1 6 | apply-args (curry6 {|...xs| $xs | math sum})) 21
assert equal (seq 1 7 | apply-args (curry7 {|...xs| $xs | math sum})) 28
assert equal (seq 1 8 | apply-args (curry8 {|...xs| $xs | math sum})) 36
assert equal (seq 1 9 | apply-args (curry9 {|...xs| $xs | math sum})) 45
assert equal (seq 1 10 | apply-args (curry10 {|...xs| $xs | math sum})) 55
assert equal (seq 1 11 | apply-args (curry11 {|...xs| $xs | math sum})) 66
assert equal (seq 1 12 | apply-args (curry12 {|...xs| $xs | math sum})) 78
assert equal (seq 1 13 | apply-args (curry13 {|...xs| $xs | math sum})) 91
assert equal (seq 1 14 | apply-args (curry14 {|...xs| $xs | math sum})) 105
assert equal (seq 1 15 | apply-args (curry15 {|...xs| $xs | math sum})) 120
assert equal (seq 1 16 | apply-args (curry16 {|...xs| $xs | math sum})) 136
assert equal (seq 1 17 | apply-args (curry17 {|...xs| $xs | math sum})) 153
assert equal (seq 1 18 | apply-args (curry18 {|...xs| $xs | math sum})) 171
assert equal (seq 1 19 | apply-args (curry19 {|...xs| $xs | math sum})) 190
assert equal (seq 1 20 | apply-args (curry20 {|...xs| $xs | math sum})) 210
assert equal (seq 1 21 | apply-args (curry21 {|...xs| $xs | math sum})) 231
assert equal (seq 1 22 | apply-args (curry22 {|...xs| $xs | math sum})) 253
assert equal (seq 1 23 | apply-args (curry23 {|...xs| $xs | math sum})) 276

# ── the uncurry inverse: flat args, ONE do, zero nesting ──────────────────
assert equal (do (uncurry2 (curry2 {|a: int, b: int| $a - $b})) 10 3) 7
# position proof at arity 5: every argument lands exactly where it belongs
assert equal (do (uncurry5 (curry5 {|a: int, b: int, c: int, d: int, e: int| $a * 10000 + $b * 1000 + $c * 100 + $d * 10 + $e})) 1 2 3 4 5) 12345
# the FULL round-trip law, every arity: uncurryN . curryN == id
assert equal (do (uncurry2 (curry2 {|...xs| $xs | math sum})) ...(seq 1 2)) 3
assert equal (do (uncurry3 (curry3 {|...xs| $xs | math sum})) ...(seq 1 3)) 6
assert equal (do (uncurry4 (curry4 {|...xs| $xs | math sum})) ...(seq 1 4)) 10
assert equal (do (uncurry5 (curry5 {|...xs| $xs | math sum})) ...(seq 1 5)) 15
assert equal (do (uncurry6 (curry6 {|...xs| $xs | math sum})) ...(seq 1 6)) 21
assert equal (do (uncurry7 (curry7 {|...xs| $xs | math sum})) ...(seq 1 7)) 28
assert equal (do (uncurry8 (curry8 {|...xs| $xs | math sum})) ...(seq 1 8)) 36
assert equal (do (uncurry9 (curry9 {|...xs| $xs | math sum})) ...(seq 1 9)) 45
assert equal (do (uncurry10 (curry10 {|...xs| $xs | math sum})) ...(seq 1 10)) 55
assert equal (do (uncurry11 (curry11 {|...xs| $xs | math sum})) ...(seq 1 11)) 66
assert equal (do (uncurry12 (curry12 {|...xs| $xs | math sum})) ...(seq 1 12)) 78
assert equal (do (uncurry13 (curry13 {|...xs| $xs | math sum})) ...(seq 1 13)) 91
assert equal (do (uncurry14 (curry14 {|...xs| $xs | math sum})) ...(seq 1 14)) 105
assert equal (do (uncurry15 (curry15 {|...xs| $xs | math sum})) ...(seq 1 15)) 120
assert equal (do (uncurry16 (curry16 {|...xs| $xs | math sum})) ...(seq 1 16)) 136
assert equal (do (uncurry17 (curry17 {|...xs| $xs | math sum})) ...(seq 1 17)) 153
assert equal (do (uncurry18 (curry18 {|...xs| $xs | math sum})) ...(seq 1 18)) 171
assert equal (do (uncurry19 (curry19 {|...xs| $xs | math sum})) ...(seq 1 19)) 190
assert equal (do (uncurry20 (curry20 {|...xs| $xs | math sum})) ...(seq 1 20)) 210
assert equal (do (uncurry21 (curry21 {|...xs| $xs | math sum})) ...(seq 1 21)) 231
assert equal (do (uncurry22 (curry22 {|...xs| $xs | math sum})) ...(seq 1 22)) 253
assert equal (do (uncurry23 (curry23 {|...xs| $xs | math sum})) ...(seq 1 23)) 276

# ── partials are VALUES (kap's narrowing object, kept in a variable) ──────
let minus: closure = (curry2 {|a: int, b: int| $a - $b})
let minus10: closure = (do $minus 10)
assert equal (do $minus10 4) 6
assert equal (do $minus10 100) (-90)
# a short arg list through apply-args leaves the remaining rungs open
let minus10b: closure = ([10] | apply-args $minus)
assert equal (do $minus10b 4) 6
# the empty arg list is the identity: nothing applied, the chain comes back
assert equal (([] | apply-args $minus) | describe) closure

# ── papply fixes leading args, rest flow through ──────────────────────────
assert equal (do (papply {|a: int, b: int, c: int| $a + $b * $c} 2) 3 4) 14

# ── record building: the applicative fills the structure ──────────────────
# build-record: sequential, field by field (pipeline input like its family)
assert equal ({x: {|| 1}, y: {|| 2}, z: {|| 3}} | build-record) {x: 1, y: 2, z: 3}
# build-record-par: same record, parallel evaluation, same result
assert equal ({a: {|| 10}, b: {|| 20}} | build-record-par) {a: 10, b: 20}
# mixed types survive the sequential path
assert equal ({n: {|| 1}, s: {|| "hi"}, l: {|| [1 2]}} | build-record) {n: 1, s: hi, l: [1 2]}
# empty spec is {} for both builders (the transpose-on-empty edge)
assert equal ({} | build-record) {}
assert equal ({} | build-record-par) {}
# build-record-par error law (nushell #16083): field failures are caught
# per-field, re-raised AFTER the stream, catchable, and name EVERY failed
# field in input order — the accumulation law
let parErr: any = (try {
    {a: {|| 1}, b: {|| error make {msg: b-boom}}, c: {|| error make {msg: c-boom}}} | build-record-par
} catch {|e| $e.msg})
assert equal $parErr "nushell-fp build-record-par: failed fields — b: b-boom; c: c-boom"
# a single failure still names its one field
let parOne: any = (try {
    {ok: {|| 1}, bad: {|| error make {msg: x}}} | build-record-par
} catch {|e| $e.msg})
assert equal $parOne "nushell-fp build-record-par: failed fields — bad: x"

# ── thread: left-to-right closure pipeline ────────────────────────────────
assert equal (thread 5 [{|x: int| $x + 1}, {|x: int| $x * 2}, {|x: int| $x - 3}]) 9
# no steps is the identity
assert equal (thread 42 []) 42

print "test_currying ok"
