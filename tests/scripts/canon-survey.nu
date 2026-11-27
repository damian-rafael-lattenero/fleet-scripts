#!/usr/bin/env nu
# canon-survey test — a planted two-package fixture: one var + one !! in the
# first package, clean vals in the second, and a gitignored build/ tree whose
# generated Kotlin must stay out of every count. The script is sourced (the
# house way for scripts whose payload is argv, not stdin).

use std/assert

use /Users/lattenero/Scripts/scripts/canon-survey.nu

# The fixture: pkg-one carries the signals, pkg-two stays clean, build/ is
# ignored and must never be counted.
def fixture []: nothing -> string {
    let root = (mktemp -d | str trim -r -c "\n")
    mkdir $"($root)/pkg-one" $"($root)/pkg-two" $"($root)/build"
    "var hits = 1\nval clean = 2\nval forced = listOf(1)!!\n" | save -f $"($root)/pkg-one/a.kt"
    "val only = 0\nfun pure(): Int = only + 1\n" | save -f $"($root)/pkg-two/b.kt"
    "var generated = true\n" | save -f $"($root)/build/generated.kt"
    "build/\n" | save -f $"($root)/.gitignore"
    $root
}

def main []: nothing -> nothing {
    let root = (fixture)
    let rows: table<repo: string, package: string, files: int, var: int, bang: int> = (canon-survey survey $root)
    let one = ($rows | where package == $"($root)/pkg-one")
    let two = ($rows | where package == $"($root)/pkg-two")
    assert equal ($one | get -o 0?.var | default 0) 1 "pkg-one: exactly one var"
    assert equal ($one | get -o 0?.bang | default 0) 1 "pkg-one: exactly one !!"
    assert equal ($two | get -o 0?.var | default 0) 0 "pkg-two: no var"
    assert equal ($two | get -o 0?.bang | default 0) 0 "pkg-two: no !!"
    print "canon-survey test: 4 assertions green over the fixture"
}
