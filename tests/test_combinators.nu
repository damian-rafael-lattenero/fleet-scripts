# test_combinators.nu — assertions for mods/combinators.nu.
use std/assert
use ../mods/combinators.nu *

assert equal (7 | identity) 7
assert equal (do (konst 42) "ignored") 42
# compose f g = g (f x): (*2) then (+1) over 5 -> 5*2 + 1
assert equal (do (compose {|x: int| $x * 2} {|x: int| $x + 1}) 5) 11
# flip: f a b = a - b, flipped over (1, 10) -> 10 - 1
assert equal (do (flip {|a: int, b: int| $a - $b}) 1 10) 9
# compose chains through konst: everything mapped to 42, then + 1
assert equal (do (compose (konst 41) {|x: int| $x + 1}) "anything") 42

print "test_combinators ok"
