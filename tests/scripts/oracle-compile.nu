# oracle-compile.nu — the hook end to end: an off-duty file is silent, a
# broken Haskell file is SPOKEN (additionalContext on stdout plus one ledger
# row), and the cooldown keeps the immediate rerun silent. The Kotlin leg's
# real compile is too slow for a suite; its pure laws live in the hook's own
# selftest and its live receipt was U9's on-device run (ScratchOracle.kt).
use std/assert

# The repo copy, found from this test's own directory (tests/scripts →
# scripts/hooks): the suite always judges what the branch ships.
let SCRIPT: string = ($env.FILE_PWD | path dirname | path dirname | path join 'scripts' 'hooks' 'oracle-compile.nu')
const LEDGER: string = '/Users/lattenero/.zcode/hooks/state/oracles.tsv'

# The payload rides the child's stdin (the KB's verified shape: nu --stdin +
# a pipe; without --stdin, $in is nothing inside main).
def fire [payload: string]: nothing -> record {
    let file: string = ('/tmp/oracle-in-' + (random uuid) + '.json')
    $payload | save -f $file
    let raw: string = (open --raw $file)
    rm $file
    let run: record = (do { $raw | ^nu --stdin $SCRIPT } | complete)
    $run
}

def ledger-count []: nothing -> int {
    if not ($LEDGER | path exists) { return 0 }
    open --raw $LEDGER | lines | length
}

# 1. OFF DUTY: a .ts file exits 0 in silence and touches no ledger row.
let before: int = (ledger-count)
let off: record = (fire '{tool_name: "Write", tool_input: {file_path: "/tmp/whatever.ts"}}')
assert equal $off.exit_code 0 'an off-duty extension is silent'
assert equal ($off.stdout | str trim) '' 'an off-duty run prints nothing'
assert equal (ledger-count) $before 'an off-duty run writes no ledger row'

# 2. SPOKEN: a broken Haskell file, written fresh each run.
let broken: path = ('/tmp/oracle-broken-' + (random uuid) + '.hs')
'module Broken where
x :: Int
x = "not an int"' | save -f $broken
let spoken: record = (fire $'{tool_name: "Write", tool_input: {file_path: "($broken)"}}')
assert equal $spoken.exit_code 0 'the oracle is advisory: it always exits 0'
let ctx: string = ($spoken.stdout | from json | get hookSpecificOutput.additionalContext)
assert ($ctx | str contains 'does not compile') 'the advisory names the failure'
assert ($ctx | str contains 'oracle-hs') 'the advisory names the leg'
assert ((ledger-count) > $before) 'a spoken run lands a ledger row'

# 3. COOLDOWN: the immediate rerun of the same file stays silent and adds no
# ledger row — one judgment per file per cooldown.
let afterSpoken: int = (ledger-count)
let again: record = (fire $'{tool_name: "Write", tool_input: {file_path: "($broken)"}}')
assert equal ($again.stdout | str trim) '' 'the cooldown keeps the rerun silent'
assert equal (ledger-count) $afterSpoken 'the rerun adds no ledger row'
rm $broken

print 'oracle-compile test: off duty silent, broken spoken, cooldown honored'
