# test_log.nu — the receipt voice for mods/log.nu.
use std/assert
use ../mods/log.nu *

# one call: the line lands on the file with a trailing newline
let tmp: path = (mktemp -t logtestXXXXXX)
emit-to $tmp "first line"
assert equal (open --raw $tmp) "first line\n"

# appends accumulate — the receipt survives the terminal
emit-to $tmp "second line"
assert equal (open --raw $tmp) "first line\nsecond line\n"

^rm $tmp
print "test_log ok"
