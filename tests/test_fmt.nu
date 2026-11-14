# test_fmt.nu — the number law ladder for mods/fmt.nu.
use std/assert
use ../mods/fmt.nu *

# raw rung
assert equal (human-num 0) "0"
assert equal (human-num 42) "42"
assert equal (human-num 999) "999"
# K rung
assert equal (human-num 1000) "1K"
assert equal (human-num 1234) "1.23K"
assert equal (human-num 300000) "300K"
assert equal (human-num 999999) "1000K"
# M rung fires AT the boundary — never 1000K once we reach the million
assert equal (human-num 1000000) "1M"
assert equal (human-num 3183196) "3.18M"
assert equal (human-num 300000000) "300M"
# trailing zeros trimmed
assert equal (human-num 2000000) "2M"
assert equal (human-num 2100000) "2.1M"

print "test_fmt ok"
