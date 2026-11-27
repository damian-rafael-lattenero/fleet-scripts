# versions.nu — the laws the version core must hold: a release name yields its
# numbers, a DATE yields none, and the numeric key orders releases the way a
# human reads them (the exact case plain sort gets wrong).
use std/assert
use ../../lib/versions.nu *

# ---- version-of: the names the fleet really sees ---------------------------

assert equal (version-of "ZCode-3.19.10-mac-arm64.dmg") [3 19 10]
assert equal (version-of "ZCode 3.19.0-arm64") [3 19 0]
assert equal (version-of "ZCode-3.18.2-official.app") [3 18 2]
assert equal (version-of "ZCode-4.0.0-mac-arm64.dmg") [4 0 0]
# a two-part version is legal; a date is NOT a release (the folder name that
# used to be read as version 2026)
assert equal (version-of "ZCode-3.19-mac-arm64.dmg") [3 19]
assert equal (version-of "zcode-official-2026-11-19") []
assert equal (version-of "no-version-here") []
assert equal (version-of "") []

# ---- version-key: numeric order, the one plain sort breaks ----------------

assert greater (version-key [3 19 10]) (version-key [3 19 9])
assert greater (version-key [3 19 9]) (version-key [3 2 0])
assert greater (version-key [4 0 0]) (version-key [3 99 99])
assert less (version-key [3 10 0]) (version-key [3 19 0])
# a missing patch reads as 0, and an unknown version never wins
assert equal (version-key [3 19]) (version-key [3 19 0])
assert equal (version-key []) 0

# ---- version-words: what the receipt says ----------------------------------

assert equal (version-words [3 19 10]) "3.19.10"
assert equal (version-words [4 0]) "4.0"
assert equal (version-words []) "unknown"

print "versions core ok — 15 laws green"
