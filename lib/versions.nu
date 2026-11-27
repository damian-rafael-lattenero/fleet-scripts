# versions.nu core — the version a NAME carries, as a NUMBER. The trap it
# removes (measured 27/11): plain order puts 3.19.9 after 3.19.10 and 3.2.0
# last, so "the newest file" chosen lexicographically is the wrong one — that
# bug shipped in zcode-original and it had been opening a stale build.
#
# A version here always carries at least one dot: "ZCode-3.19.10-mac-arm64.dmg"
# is a release, "zcode-official-2026-11-19" is not (a date is not a version).

# The first dotted number run in a name, as integers; [] when the name carries
# no version at all.
export def version-of [name: string]: nothing -> list<int> {
    let hits: list<string> = (($name | parse -r '(?<v>\d+\.\d+(?:\.\d+){0,2})' | get --optional v | default []) | into string)
    if ($hits | is-empty) { return [] }
    ($hits | first) | split row '.' | each {|part| $part | into int }
}

# One comparable integer: 3.19.10 → 3_019_010. Fixed slots keep the order total
# and obvious, and an unknown version is 0 so it can never win. Slot ceilings:
# minor and patch < 1000, major < 1_000_000 (real release numbers never reach
# them; a version that did would collide, and that is a redesign signal).
export def version-key [parts: list<int>]: nothing -> int {
    let p: list<int> = (($parts | first 3) | append [0 0 0] | first 3)
    (($p | get 0) * 1_000_000) + (($p | get 1) * 1_000) + ($p | get 2)
}

# The words a receipt speaks: [3 19 10] → "3.19.10"; [] → "unknown".
export def version-words [parts: list<int>]: nothing -> string {
    if ($parts | is-empty) { return "unknown" }
    $parts | each {|p| $p | into string } | str join "."
}
