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

# ---- the release feed (the parsed GitHub body) ----------------------------

let release: record = {
    tag_name: "v4.0.0"
    assets: [
        {name: "SHA256SUMS", browser_download_url: "https://h/SHA256SUMS", size: 546}
        {name: "ZCode-4.0.0-mac-arm64.dmg", browser_download_url: "https://h/ZCode-4.0.0-mac-arm64.dmg", size: 241737476}
        {name: "ZCode-4.0.0-mac-x64.dmg", browser_download_url: "https://h/ZCode-4.0.0-mac-x64.dmg", size: 249042957}
        {name: "ZCode-4.0.0-win-x64.exe", browser_download_url: "https://h/win.exe", size: 203234992}
    ]
}
let arm: any = (release-of $release "arm64")
assert equal $arm.version "4.0.0"
assert equal $arm.key (version-key [4 0 0])
assert equal $arm.dmg_url "https://h/ZCode-4.0.0-mac-arm64.dmg"
assert equal $arm.sums_url "https://h/SHA256SUMS"
assert equal $arm.size 241737476
assert equal (release-of $release "x64").dmg_url "https://h/ZCode-4.0.0-mac-x64.dmg"
# no artifact for this architecture = no update, never a crash
assert ((release-of $release "riscv") == null) "an archless release yields null"
# a tag that is not a version is not a release
assert ((release-of {tag_name: "nightly", assets: []} "arm64") == null) "a non-version tag yields null"

# ---- the checksum file ----------------------------------------------------

let sums: string = ([
    "c4ffabb328cca088ea504baaaa7d7ad51a92eed51c8a92a8428ab77d04b956a1  ZCode-4.0.0-mac-arm64.dmg"
    "64fbb25bd002d2329ddd542b40b532c8f730d5490a45e9e698d1e007649164da  ZCode-4.0.0-mac-arm64.zip"
] | str join (char nl))
assert equal (sha-of $sums "ZCode-4.0.0-mac-arm64.dmg") "c4ffabb328cca088ea504baaaa7d7ad51a92eed51c8a92a8428ab77d04b956a1"
# the binary marker "*name" is the same entry
assert equal (sha-of "c4ffabb328cca088ea504baaaa7d7ad51a92eed51c8a92a8428ab77d04b956a1 *ZCode.dmg" "ZCode.dmg") "c4ffabb328cca088ea504baaaa7d7ad51a92eed51c8a92a8428ab77d04b956a1"
# a file the sums do not name can never be verified
assert equal (sha-of $sums "ZCode-9.9.9-mac-arm64.dmg") ""
# a malformed line (short hash) is ignored, never trusted
assert equal (sha-of "deadbeef  ZCode.dmg" "ZCode.dmg") ""

print "versions core ok — 30 laws green"
