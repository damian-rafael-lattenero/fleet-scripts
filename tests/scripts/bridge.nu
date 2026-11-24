# bridge.nu — the temporary ram-clean shim at the hub root. The DEPLOYED bot
# build pins /Users/lattenero/Scripts/ram-clean.nu (the pre-hub path); a
# symlink does not work there (relative `use` resolves from the link's dir), so
# the shim must exec the real script through the same interpreter. It is
# gitignored machine state: absent on a fresh clone, and that is fine — the
# test skips instead of failing.
# covers: /Users/lattenero/Scripts/ram-clean.nu
use std/assert

const SHIM: string = '/Users/lattenero/Scripts/ram-clean.nu'
const REAL: string = '/Users/lattenero/Scripts/scripts/ram-clean.nu'

if ($SHIM | path type) == null {
    print "bridge.nu skipped — no shim (the deployed build no longer needs it)"
    return
}

assert equal ($SHIM | path type) "file" "the shim must be a real script, never a symlink"
assert equal (nu-check $SHIM) true "the shim must parse"
let src: string = (open --raw $SHIM)
assert ($src =~ '/Users/lattenero/Scripts/scripts/ram-clean.nu') "the shim must point at the real script"
assert equal ($REAL | path type) "file" "the real script must exist"

print "bridge.nu ok — shim execs the hub's ram-clean"
