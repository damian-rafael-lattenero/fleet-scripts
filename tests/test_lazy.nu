# test_lazy.nu — the deference proofs for mods/lazy.nu. The side-effect
# file is the clock: a lazy build NEVER touches it until force does.
use std/assert
use ../mods/lazy.nu *

# 1. the thunk builds free: the side effect does NOT run at build time.
# The marker path must NOT pre-exist — mktemp CREATES its file and would
# lie about the deference (measured 21/11).
let marker: path = ($"($env.TMPDIR | default /tmp)/lz-(random uuid)")
let t: record = (thunk {|| "computed!" | save --append --raw $marker; "computed!" })
assert equal ($marker | path exists) false

# 2. force runs it: the side effect lands AND the value returns
let value: string = (force $t)
assert equal $value "computed!"
assert equal ($marker | path exists) true
assert str contains "computed!" (open --raw $marker)

# 3. force-with: the deferred function receives its argument
let squared: record = (thunk {|x| $x * $x })
assert equal (force-with $squared 12) 144

# 4. re-force runs again (the owner decides the caching policy — the stdlib
#    stays honest and stateless)
assert equal (force-with $squared 5) 25

^rm $marker
print "test_lazy ok"
