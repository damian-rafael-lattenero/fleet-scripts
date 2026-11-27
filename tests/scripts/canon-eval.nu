#!/usr/bin/env nu
# canon-eval test — the pure projection pinned: verdict-of on a planted
# report (all-green, one miss, empty report). The end-to-end suite run is
# the script's own job, not the test's (minutes, live store).

use std/assert
use /Users/lattenero/Scripts/scripts/canon-eval.nu

def main []: nothing -> nothing {
    let green: record<passed: int, total: int, ok: bool, missed: list<string>> = (canon-eval verdict-of {
        passed: 94,
        total: 94,
        ok: true,
        durationMs: 210000,
        cases: [{id: 'rung1-taxonomy-kt', ok: true, rank: 4}, {id: 'rung2-totality-nu', ok: true, rank: 2}],
    })
    assert equal $green.passed 94 "green report passes through"
    assert $green.ok "green report is ok"
    assert ($green.missed | is-empty) "green report names no missed case"

    let missed: record<passed: int, total: int, ok: bool, missed: list<string>> = (canon-eval verdict-of {
        passed: 89,
        total: 90,
        ok: true,
        durationMs: 202000,
        cases: [{id: 'a', ok: true, rank: 1}, {id: 'canon-hkt-p', ok: false, rank: null}],
    })
    assert equal $missed.passed 89 "missed report keeps the numbers"
    assert equal $missed.missed ['canon-hkt-p'] "the missed case id is named"

    let empty: record<passed: int, total: int, ok: bool, missed: list<string>> = (canon-eval verdict-of {})
    assert equal $empty.total 0 "an empty report degrades to zeros, never an error"

    print "canon-eval test: 7 assertions green"
}
