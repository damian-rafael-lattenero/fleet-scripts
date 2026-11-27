#!/usr/bin/env nu
# kotlin-law test — 8 unit cases over findings-of, one end-to-end stdin run
# proving the exit-2 deny + the ledger row, and the fleet census: the detector
# must find exactly the two known sites and nothing else (0 false positives).

use std/assert
use /Users/lattenero/Scripts/scripts/hooks/kotlin-law.nu

def main []: nothing -> nothing {
    # ── the 8 selftest cases ──
    let deny1: table = (kotlin-law findings-of 'private val CORRECTION_KINDS = setOf("steer", "stop", "cancel", "explicit")')
    assert equal ($deny1 | length) 1 "the real BusProducer offender denies"
    assert equal ($deny1 | get 0.name) 'CORRECTION_KINDS' "the finding names the constant"

    let deny2: table = (kotlin-law findings-of 'private val BREAKER_STATES = listOf("Closed", "Open", "HalfOpen")')
    assert equal ($deny2 | length) 1 "the real MetricsInventory offender denies"

    let deny3: table = (kotlin-law findings-of 'const val MIME_VOCAB: Set<String> = setOf("a", "b")')
    assert equal ($deny3 | length) 1 "const val with a type annotation denies"

    let allow1: table = (kotlin-law findings-of 'val LEGACY_KINDS = mapOf("a" to "b")')
    assert equal ($allow1 | length) 0 "a legacy mapOf parse table is allowed by design"

    let allow2: table = (kotlin-law findings-of 'val kinds = listOf("a", "b")')
    assert equal ($allow2 | length) 0 "a lowercase local is not a taxonomy constant"

    let allow3: table = (kotlin-law findings-of 'val KINDS = entries.associateBy { it.wire }')
    assert equal ($allow3 | length) 0 "a derived set with no literals is allowed"

    let allow4: table = (kotlin-law findings-of 'val DEFAULT_PATHS = listOf("/a", "/b")')
    assert equal ($allow4 | length) 0 "a name without a vocabulary run is allowed"

    let allow5: table = (kotlin-law findings-of 'val SINGLE_KINDS = setOf("only")')
    assert equal ($allow5 | length) 0 "a single literal sits below the >=2 threshold"

    # ── the end-to-end deny: stdin payload -> exit 2 + ledger row ──
    let payload = {
        session_id: 'kotlin-law-test',
        tool_input: {
            file_path: '/tmp/ScratchVocab.kt',
            content: "val NEW_KINDS = setOf(\"x\", \"y\")\n",
        },
    }
    let log = ('/tmp' | path join 'kotlin-law-test.tsv')
    ^rm -f $log
    let res: record = (do { $payload | to json -r | ^nu --stdin /Users/lattenero/Scripts/scripts/hooks/kotlin-law.nu --log $log } | complete)
    assert equal $res.exit_code 2 "the deny exits 2"
    assert ($res.stderr | str contains 'closed-vocabulary law') "the stderr names the law"
    let rows = (open --raw $log | lines)
    assert equal ($rows | length) 1 "exactly one ledger row"
    assert ($rows | first | str contains 'closed-vocabulary') "the row names the rule"

    # ── the census: exactly the three known sites, fleet-wide ──
    let files: list<string> = (do { ^rg --files --glob '*.kt' /Users/lattenero/Projects/agent-brain /Users/lattenero/Projects/zcode-bot-kotlin } | complete | get stdout | lines)
    let census: table = ($files
        | each {|f| {file: $f, hits: (kotlin-law findings-of (open --raw $f))} }
        | where {|r| ($r.hits | length) > 0})
    assert equal ($census | length) 3 "the census finds exactly three sites"
    let names: list<string> = ($census | get file | each {|f| $f | path basename} | sort)
    assert equal $names ['BusEvent.kt' 'BusProducer.kt' 'MetricsInventory.kt'] "the census names the three known files"

    print "kotlin-law test: 8 selftest cases + end-to-end + census green"
}
