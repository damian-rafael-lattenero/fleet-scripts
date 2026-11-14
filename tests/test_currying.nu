# test_currying.nu — assertions for mods/currying.nu (kap-translated laws).
use std/assert
use ../mods/currying.nu *

# curry2: full application through both steps
assert equal (do (do (curry2 {|a: int, b: int| $a - $b}) 10) 3) 7
# curry3: three chained steps
assert equal (do (do (do (curry3 {|a: int, b: int, c: int| $a * 100 + $b * 10 + $c}) 1) 2) 3) 123
# curry4 / curry5: the kap curried() ladder completed
assert equal (do (do (do (do (curry4 {|a: int, b: int, c: int, d: int| $a + $b + $c + $d}) 1) 2) 3) 4) 10
assert equal (do (do (do (do (do (curry5 {|a: int, b: int, c: int, d: int, e: int| $a * 10000 + $b * 1000 + $c * 100 + $d * 10 + $e}) 1) 2) 3) 4) 5) 12345
# a curried step is a VALUE: reusable partial holding the first argument
let minus: closure = curry2 {|a: int, b: int| $a - $b}
let minus10: closure = do $minus 10
assert equal (do $minus10 4) 6
assert equal (do $minus10 100) (-90)
# uncurry2 inverts curry2 (round-trip law)
assert equal (do (uncurry2 $minus) 10 3) 7
# papply fixes leading args, rest flow through
assert equal (do (papply {|a: int, b: int, c: int| $a + $b * $c} 2) 3 4) 14
# build-record: deferred closures fill the structure field by field
assert equal (build-record {x: {|| 1}, y: {|| 2}, z: {|| 3}}) {x: 1, y: 2, z: 3}
# build-record-par: same record, parallel evaluation
assert equal (build-record-par {a: {|| 10}, b: {|| 20}}) {a: 10, b: 20}
# build-record over mixed types
assert equal (build-record {n: {|| 1}, s: {|| "hi"}, l: {|| [1 2]}}) {n: 1, s: hi, l: [1 2]}
# thread: left-to-right closure pipeline
assert equal (thread 5 [{|x: int| $x + 1}, {|x: int| $x * 2}, {|x: int| $x - 3}]) 9
# thread with no steps is the identity
assert equal (thread 42 []) 42

print "test_currying ok"
