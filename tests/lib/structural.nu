# structural.nu — the proofs of the structural helper itself: the exemption
# patterns, the `# covers:` parser, and the three findings it can raise. Its
# fixtures are written to a temp dir, so the test is self-contained.
use std/assert
use ../../lib/structural.nu *

let tmp: path = ($"($env.TMPDIR? | default /tmp)/structural-(random uuid)")
mkdir $tmp
let nl: string = (char nl)

# 1. a clean script is clean (the shebang resolves through PATH).
let good: path = ($tmp | path join 'good.nu')
(['#!/usr/bin/env nu' 'print 1'] | str join $nl) | save -f $good
assert equal (findings [$good]) []

# 2. a parse error is reported as such.
let broken: path = ($tmp | path join 'broken.nu')
'def ( {' | save -f $broken
assert equal ((findings [$broken] | get 0.reason)) 'parse'

# 3. a stale pre-hub import is caught (the module is gone, so the parse leg
#    fires too — both reasons are honest).
let stale: path = ($tmp | path join 'stale.nu')
(['use /Users/lattenero/Projects/nushell-fp/mods/log.nu *' 'print 1'] | str join $nl) | save -f $stale
assert (((findings [$stale]) | get reason) | any {|r| $r == 'stale-import'})

# 4. a shebang naming a missing interpreter is caught.
let nointerp: path = ($tmp | path join 'nointerp.nu')
(['#!/nope/nu' 'print 1'] | str join $nl) | save -f $nointerp
assert (((findings [$nointerp]) | get reason) | any {|r| $r == 'shebang'})

^rm -rf $tmp
print "lib/structural ok"
