#!/usr/bin/env nu
# census.nu — THE LAW (owner, 24/11): every operational Nushell script on this
# machine has an associated test. This file is the mechanical half: it walks
# the known roots (lib/census.nu holds the map), applies the exemption
# PATTERNS (generated, archived, vendored, the fp subtree's own gate), and
# fails naming every script that no test claims — via a `# covers: <absolute
# glob>` line or its same-named test in the same root.
#
#   nu ~/Scripts/tests/census.nu
use std/assert
use ../lib/census.nu *

def main []: nothing -> nothing {
    let scripts: list<string> = (scripts-under $ROOTS)
    let tests: list<string> = (tests-under $ROOTS)
    let covered: list<string> = (covered-set $scripts $tests $ROOTS)
    let missing: list<string> = (uncovered $scripts $covered)

    if not ($missing | is-empty) {
        let report: string = ($missing | each {|m| '  ' + $m} | str join (char nl))
        print -e $"CENSUS FAILED — ($missing | length) of ($scripts | length) scripts have no test:\n($report)"
        exit 1
    }

    print $"census ok — ($scripts | length) scripts, ($tests | length) test files, law held"
}
