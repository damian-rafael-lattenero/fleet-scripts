# run-length-encoding.nu — the Exercism / HaskellWiki classic, span-driven.
# "aaaabbbcc" -> [[a 4] [b 3] [c 2]] and BACK (the round-trip law), using
# span to cut each run at the first different char and replicate to expand.
use std/assert
use ../mods/list.nu *

# encode: split each run with span (predicate = equals the run's head)
def rle-encode []: list<string> -> list<list<any>> {
    mut rest: list<string> = $in
    mut out: list<list<any>> = []
    while not ($rest | is-empty) {
        let head: string = ($rest | first)
        let split: record<taken: list<string>, rest: list<string>> = ($rest | span {|c| $c == $head})
        $out = ($out | append [[$head ($split.taken | length)]])
        $rest = $split.rest
    }
    $out
}

# decode: replicate each (char, count) back and flatten
def rle-decode []: list<list<any>> -> list<string> {
    $in | each {|run| replicate ($run.1 | into int) ($run.0)} | flatten
}

let encoded: list<list<any>> = ("aaaabbbcc" | split chars | rle-encode)
assert equal $encoded [[a 4] [b 3] [c 2]]
print $"PASS encode: ($encoded | each {|r| $r | str join} | str join ' ')"

# THE round-trip law: decode . encode == identity
let roundTrip: list<string> = ($encoded | rle-decode)
assert equal ($roundTrip | str join) "aaaabbbcc"
print 'PASS round-trip: decode . encode == identity'

# the empty and singleton edges
assert equal ([] | rle-encode) []
assert equal (["x"] | rle-encode) [[x 1]]
print 'PASS edges: empty and singleton runs'
