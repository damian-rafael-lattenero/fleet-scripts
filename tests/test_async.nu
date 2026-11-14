# test_async.nu — assertions for mods/async.nu (job applicative).
use std/assert
use ../mods/async.nu *
use ../mods/currying.nu *

# concurrent results come back in structure order
assert equal ([{|| 10}, {|| 20}, {|| 30}] | traverse-jobs) [10 20 30]
# staggered completion (slow first job) still restores spawn order
assert equal ([{|| sleep 200ms; 2}, {|| 1}] | traverse-jobs) [2 1]
# empty input is the empty list
assert equal ([] | traverse-jobs) []
# a crashed element reports through the mailbox — no silent hang, honest
# error naming the element index (learned live: the 355-file agent hang)
let exploded: any = (try { [{|| 1}, {|| error make {msg: "boom element"}}, {|| 3}] | traverse-jobs } catch {|e| $e.msg})
assert equal $exploded "nushell-fp traverse-jobs: element 1 failed: boom element"
# record filling runs all fields concurrently
assert equal ({a: {|| 1}, b: {|| 2}} | build-record-jobs) {a: 1, b: 2}
# a slow field still fills — the record waits for the last one
assert equal ({fast: {|| "x"}, slow: {|| sleep 150ms; "y"}} | build-record-jobs) {fast: x, slow: y}
# apply-async: concurrent deferred args feed a curried closure (kap .with)
assert equal ([{|| 10}, {|| 3}] | apply-async (curry2 {|a: int, b: int| $a - $b})) 7
assert equal ([{|| 1}, {|| 2}, {|| 3}] | apply-async (curry3 {|a: int, b: int, c: int| $a * 100 + $b * 10 + $c})) 123

print "test_async ok"
