# gate.nu — the gate is a script too: test.nu must parse, must keep its two
# modes (the whole machine contract and --ci's pure one), and must run every
# test it finds. A gate that silently skips is worse than no gate.
# covers: /Users/lattenero/Scripts/test.nu
use std/assert

const GATE: string = '/Users/lattenero/Scripts/test.nu'

assert equal ($GATE | path type) "file" "test.nu must exist"
assert equal (nu-check $GATE) true "test.nu must parse"

let src: string = (open --raw $GATE)
assert ($src =~ '--ci') "the --ci mode must stay documented and implemented"
assert ($src =~ 'nu-check') "the gate must check syntax before running"
assert ($src =~ 'nushell-fp') "the fp suite must ride the same gate"

print "gate.nu ok"
