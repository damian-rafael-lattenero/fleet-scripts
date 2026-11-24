# test_proc.nu — the complete-record folding for mods/proc.nu.
use std/assert
use ../mods/proc.nu *

# the string shape passes through untouched
assert equal (fold-stderr {exit_code: 1, stderr: "boom", stdout: ""}) "boom"

# the list-of-lines shape folds to text (the measured trap: the 15/11 drill
# crashed HERE and hid the real error)
assert equal (fold-stderr {exit_code: 1, stderr: ["boom" "line 2"], stdout: ""}) "boom\nline 2"

# a missing/null stderr is the honest empty string, never a crash
assert equal (fold-stderr {exit_code: 0, stdout: "ok"}) ""

print "test_proc ok"
