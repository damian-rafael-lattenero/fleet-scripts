#!/usr/bin/env nu
# kotlin-law test — the three laws: 8 rung-1 cases (closed vocabulary), 8
# rung-2 cases (force-unwrap + silent-skip), the end-to-end stdin deny with
# its ledger row, and the census: closed-vocabulary must stay exactly the
# three known sites fleet-wide; the totality counts are printed as the live
# debt numbers (tripwire by rerun, not by assertion).

use std/assert
use /Users/lattenero/Scripts/scripts/hooks/kotlin-law.nu

def main []: nothing -> nothing {
    # ── rung 1: the closed vocabulary ──
    let deny1: table = (kotlin-law findings-of 'private val CORRECTION_KINDS = setOf("steer", "stop", "cancel", "explicit")')
    assert equal ($deny1 | length) 1 "the real BusProducer offender denies"
    assert equal ($deny1 | get 0.rule) 'closed-vocabulary' "the finding names its rule"
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

    # ── rung 2: force-unwrap + silent-skip ──
    let b1: table = (kotlin-law findings-of 'val x = row.file!!')
    assert equal ($b1 | length) 1 "a force-unwrap denies"
    assert equal ($b1 | get 0.rule) 'force-unwrap' "the bang finding names its rule"

    let b2: table = (kotlin-law findings-of 'list.map { it.id!! }')
    assert equal ($b2 | length) 1 "a bang inside a lambda denies"

    let b3: table = (kotlin-law findings-of '@Test fun g() = runBlocking { }')
    assert equal ($b3 | length) 1 "an expression-bodied @Test without Unit denies"
    assert equal ($b3 | get 0.rule) 'silent-skip-test' "the skip finding names its rule"

    let b4: table = (kotlin-law findings-of '@Test fun h() = runTest { }')
    assert equal ($b4 | length) 1 "runTest bodies deny too"

    let a6: table = (kotlin-law findings-of 'val s = "Hello!! world"')
    assert equal ($a6 | length) 0 "a bang inside a string literal is never denied"

    let a7: table = (kotlin-law findings-of '// this!! stays a comment')
    assert equal ($a7 | length) 0 "a bang inside a comment is never denied"

    let a8: table = (kotlin-law findings-of '@Test fun g(): Unit = runBlocking { }')
    assert equal ($a8 | length) 0 "an explicit `: Unit` body is the fix shape"

    let a9: table = (kotlin-law findings-of '@Test fun g() = runBlocking<Unit> { }')
    assert equal ($a9 | length) 0 "a pinned runBlocking<Unit> is the fix shape"

    # ── rung 3: var in main sources ──
    let v1: table = (kotlin-law findings-of 'fun parse(wire: String?): Int { var n = 0; return n }')
    assert equal ($v1 | length) 1 "a local var declares a finding"
    assert equal ($v1 | get 0.rule) 'var-in-main' "the var finding names its rule"

    let v2: table = (kotlin-law findings-of 'private var count = 0')
    assert equal ($v2 | length) 1 "a private var property denies"

    let v3: table = (kotlin-law findings-of 'lateinit var client: HttpClient')
    assert equal ($v3 | length) 1 "a lateinit var denies in main"

    let a10: table = (kotlin-law findings-of 'fun f(vararg xs: String): Int = xs.size')
    assert equal ($a10 | length) 0 "vararg is not a var declaration"

    let a11: table = (kotlin-law findings-of 'val only = 1')
    assert equal ($a11 | length) 0 "a val binds no finding"

    # ── rung 5: the CE law ──
    let c1: table = (kotlin-law findings-of "suspend fun go() { runCatching { client.query() }.getOrNull() }")
    assert equal ($c1 | length) 1 "runCatching over a suspend call denies"
    assert equal ($c1 | get 0.rule) 'ce-laundering' "the laundering finding names its rule"

    let c2: table = (kotlin-law findings-of "runCatching { mutex.withLock { send() } }")
    assert equal ($c2 | length) 1 "runCatching over withLock denies"

    let c3: table = (kotlin-law findings-of "try { go() } catch (e: Exception) { log.warn(\"x\", e) }")
    assert equal ($c3 | length) 1 "a wide Exception arm with no CE arm denies"

    let c4: table = (kotlin-law findings-of "try { go() } catch (t: Throwable) { log.warn(\"x\", t) }")
    assert equal ($c4 | length) 1 "a wide Throwable arm denies too"

    let a12: table = (kotlin-law findings-of "catch (ce: CancellationException) throw ce\ntry { go() } catch (e: Exception) { log.warn(\"x\", e) }")
    assert equal ($a12 | length) 0 "a fragment carrying the CE arm first is the fix shape"

    let a13: table = (kotlin-law findings-of 'runCatching { Json.parseToJsonElement(raw) }.getOrNull()')
    assert equal ($a13 | length) 0 "a pure parse conversion stays legal"

    let a14: table = (kotlin-law findings-of 'catch (e: IOException) { return null }')
    assert equal ($a14 | length) 0 "a narrow arm is not a wide catch"

    let a15: table = (kotlin-law findings-of '// catch (e: Exception) { } in a comment stays prose')
    assert equal ($a15 | length) 0 "a catch in a comment is never denied"

    # ── the end-to-end deny: stdin payload -> exit 2 + ledger row ──
    let payload = {
        session_id: 'kotlin-law-test',
        tool_input: {
            file_path: '/tmp/ScratchVocab.kt',
            content: "val NEW_KINDS = setOf(\"x\", \"y\")\n",
        },
    }
    let log: string = ('/tmp' | path join 'kotlin-law-test.tsv')
    ^rm -f $log
    let res: record = (do { $payload | to json -r | ^nu --stdin /Users/lattenero/Scripts/scripts/hooks/kotlin-law.nu --log $log } | complete)
    assert equal $res.exit_code 2 "the deny exits 2"
    assert ($res.stderr | str contains 'closed-vocabulary law') "the stderr names the law"
    let rows: list<string> = (open --raw $log | lines)
    assert equal ($rows | length) 1 "exactly one ledger row"
    assert ($rows | first | str contains 'closed-vocabulary') "the row names the rule"

    # ── the exemption: the same var content in a TEST path passes ──
    let testPayload = {
        session_id: 'kotlin-law-test',
        tool_input: {
            file_path: '/tmp/proj/src/test/kotlin/ScratchVocab.kt',
            content: "var fixtureState = 1\n",
        },
    }
    let resTest: record = (do { $testPayload | to json -r | ^nu --stdin /Users/lattenero/Scripts/scripts/hooks/kotlin-law.nu --log $log } | complete)
    assert equal $resTest.exit_code 0 "a var in a test source is exempt"

    # ── the census ──
    let files: list<string> = (do { ^rg --files --glob '*.kt' /Users/lattenero/Projects/agent-brain /Users/lattenero/Projects/zcode-bot-kotlin } | complete | get stdout | lines)
    let census: table = ($files
        | each {|f| {file: $f, hits: (kotlin-law findings-of (open --raw $f))} }
        | where {|r| ($r.hits | is-not-empty)})
    let vocabSites: table<file: string, rules: list<string>> = ($census
        | each {|r| {file: ($r.file | path basename), rules: ($r.hits | get rule | uniq)}})
    let vocabOnly: list<string> = ($vocabSites | where {|r| ($r.rules | any {|x| $x == 'closed-vocabulary'})} | get file | sort)
    assert equal $vocabOnly ['BusEvent.kt' 'BusProducer.kt' 'MetricsInventory.kt'] "the vocabulary census stays at the three known files"

    let mainFiles: table = ($census | where {|r| ($r.file | str contains '/src/main/')})
    let debt = {
        bang: ($census | each {|r| ($r.hits | where rule == 'force-unwrap' | length)} | math sum),
        skips: ($census | each {|r| ($r.hits | where rule == 'silent-skip-test' | length)} | math sum),
        vars: ($mainFiles | each {|r| ($r.hits | where rule == 'var-in-main' | length)} | math sum),
        ce: ($mainFiles | each {|r| ($r.hits | where rule == 'ce-laundering' | length)} | math sum),
    }
    print $"kotlin-law census: vocabulary sites 3 of 3 pinned; live debt: ($debt.bang) force-unwraps, ($debt.skips) silent-skip tests, ($debt.vars) var in main sources, ($debt.ce) ce-laundering sites — rerun prints the trend"

    print "kotlin-law test: 29 cases + end-to-end + census green"
}
