# json-lines.nu — the shared JSON-lines parse: objects survive, garbage and
# blank lines die. 0.117's `from json` is LENIENT (a non-JSON line answers the
# string itself), so the record filter is the whole honesty of this function.
use std/assert
use ../../lib/json-lines.nu *

# Text is built by joining literal lines: single-quoted nushell strings do not
# interpret \n, and that trap would make the fixture one giant garbage line.
let nl: string = (char nl)

# 1. one object per line, in order, as records.
let two: list<any> = (record-lines (['{"a":1}' '{"a":2}'] | str join $nl))
assert equal ($two | length) 2
assert equal ($two | get 0.a) 1
assert equal ($two | get 1.a) 2

# 2. garbage and blanks are dropped, never surfaced as strings.
let mixed: list<any> = (record-lines (['{"a":1}' 'not json' '' '   ' '{"a":2}'] | str join $nl))
assert equal ($mixed | length) 2
assert equal ($mixed | each {|r| $r.a}) [1 2] "the survivors are the two objects"

# 3. a bare JSON array or scalar is not a record line (the ledger wants objects).
assert equal (record-lines '[1,2,3]') []
assert equal (record-lines '42') []

# 4. empty input answers [].
assert equal (record-lines '') []

print "lib/json-lines ok"
