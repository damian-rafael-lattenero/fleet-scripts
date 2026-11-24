# test_wait.nu — the bounded-poll proofs for mods/wait.nu: readiness on the
# first call is free, an expired budget answers FALSE honestly after waiting,
# and the probe is called more than once inside the window (it really polls).
use std/assert
use ../mods/wait.nu *

# 1. ready immediately: true, and the interval is never paid.
let t0: datetime = (date now)
let instant: bool = (wait-until 2sec {|| true })
assert equal $instant true
assert equal (((date now) - $t0) < 1sec) true

# 2. never ready: the deadline is the answer — false, and it waited for it.
let t1: datetime = (date now)
let never: bool = (wait-until 1sec {|| false } --interval 200ms)
assert equal $never false
assert equal (((date now) - $t1) >= 900ms) true

# 3. it really POLLS: the probe appends to a file and flips true on the
#    third call (a mutable `mut` cannot be captured in a closure — measured
#    24/11 "Capture of mutable variable" — the file is the honest counter).
let counter: path = ($"($env.TMPDIR? | default /tmp)/wait-count-(random uuid)")
touch $counter
let third: bool = (wait-until 2sec {||
    "x\n" | save --append --raw $counter
    (open --raw $counter | lines | length) >= 3
} --interval 100ms)
assert equal $third true
assert equal ((open --raw $counter | lines | length) == 3) true

^rm $counter
print "test_wait ok"
