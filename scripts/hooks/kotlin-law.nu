#!/opt/homebrew/bin/nu
# PreToolUse(Write|Edit) on .kt/.kts — Kotlin's gate. Three laws:
#
# 1. THE CLOSED-VOCABULARY LAW (plan U11, rung 1): a taxonomy of wire values
#    is a SUM TYPE — an enum with a `wire` property and a TOTAL parse (byWire
#    map + degraded constructor, the fleet's compiled example: CorrectionKind).
#    A Set/List/array of string literals under a KINDS/VOCAB/STATES/TYPES
#    constant re-declares the taxonomy by hand — DENIED from day 1.
# 2. THE FORCE-UNWRAP LAW (plan U12, rung 2, the totality law): `!!` throws a
#    bare NPE with no context. Replace: `?: return` at the edge,
#    requireNotNull with a message, assertNotNull in tests.
# 3. THE SILENT-SKIP LAW (plan U12, rung 2): an expression-bodied @Test
#    without an explicit `: Unit` infers the tail's type — a nullable tail
#    makes the method not-void and JUnit silently SKIPS the test (measured in
#    U8: a guard law that never ran). Declare `: Unit` or `runBlocking<Unit>`.
# 4. THE IMMUTABILITY LAW (plan U13, rung 3): a `var` declaration added to a
#    MAIN source is denied — bind `val` and produce a new value (a fold for
#    accumulators, a persistent copy for updates, a holder for late wiring).
#    TEST sources are exempt (fixtures and lateinit measured there).
# 5. THE CE LAW (plan U15, rung 5): CancellationException is a channel, never
#    a value. DENIED in main sources: runCatching (or a bare
#    `catch (e: Exception|Throwable)`) whose added fragment carries no
#    CancellationException arm — over suspend code that launders cancellation
#    into a value; the ladder is the CE arm FIRST, then the narrow arm, then
#    the edge conversion (kap catching/settled). The measured census: the
#    17/11 audit's 7 laundering sites are all fixed; the rule keeps them from
#    coming back. Pure parse conversions (runCatching { json.parse... }) are
#    the honest shape and stay legal.
#
# Scope honesty: the gate judges what the edit ADDS (Write: whole content;
# Edit: new_string). Legacy mapOf translation tables are parse tables, not
# vocabularies: allowed. Strings and comments are stripped before the
# totality scan — a "Hello!!" in prose is never denied. Fail-open: any crash
# exits nonzero-but-not-2 and never blocks.

const DENIALS: path = '/Users/lattenero/.zcode/hooks/state/denials.tsv'

# One law violation: the rule dispatches the message, name names the offender.
type Finding = record<rule: string, name: string, kind: string>

# The vocabulary name runs that mark a taxonomy constant (measured census:
# CORRECTION_KINDS, BREAKER_STATES — and zero false positives fleet-wide).
const NAME_RUNS = ['KINDS' 'VOCAB' 'STATES' 'TYPES']

# The code face of an edit: triple-quoted strings, strings, block comments
# and line comments removed, so prose bangs never trip the totality scan.
def code-only [content: string]: nothing -> string {
    $content
    | str replace -a -r '(?s)""".*?"""' ''
    | str replace -a -r '"(?:[^"\\]|\\.)*"' ''
    | str replace -a -r '(?s)/\*.*?\*/' ''
    | str replace -a -r '(?m)//[^\n]*' ''
}

# The law's one predicate. Returns one row per finding:
# {rule, name, kind} — rule is the dispatch key, name the offender.
export def findings-of [content: string]: nothing -> table<rule: string, name: string, kind: string> {
    let vocab: table<rule: string, name: string, kind: string> = ($content
        | parse -r '(?s)(?:const\s+)?val\s+(?<name>[A-Z][A-Za-z0-9_]*)\s*(?::[^=\n]+)?=\s*(?<init>setOf|listOf|arrayOf)\s*\((?<args>[^)]*)\)'
        | where {|row|
            let named: bool = ($NAME_RUNS | any {|run| ($row.name | str contains $run)})
            let literals: int = ($row.args | parse -r '"[^"]*"' | length)
            $named and ($literals >= 2)
        }
        | each {|row| {rule: 'closed-vocabulary', name: $row.name, kind: $row.init}})
    let code: string = (code-only $content)
    let bangs: table<rule: string, name: string, kind: string> = ($code
        | parse -r '(?<prev>\S)\s*!!'
        | each {|row| {rule: 'force-unwrap', name: '!!', kind: ($row.prev | str trim)}})
    let skips: table<rule: string, name: string, kind: string> = ($code
        | parse -r '@Test\s+(?:override\s+)?fun\s+(?<name>\w+)\s*\([^)]*\)\s*=\s*(?<fam>runBlocking|runTest|runBlockingTest)\s*(?<gen><[^>]+>)?'
        | where {|row| ($row.gen | is-empty)}
        | each {|row| {rule: 'silent-skip-test', name: $row.name, kind: $row.fam}})
    let vars: table<rule: string, name: string, kind: string> = ($code
        | parse -r '\bvar\s+(?<name>[A-Za-z_]\w*)'
        | each {|row| {rule: 'var-in-main', name: $row.name, kind: 'var'}})
    # The CE law: runCatching over a suspend-family call, or a wide catch arm
    # with no CancellationException arm anywhere in the fragment. The suspend
    # list is name-based and evidenced (the 17/11 audit's laundering shapes).
    let ceArmed: bool = ($code =~ 'catch \(\w+: CancellationException\)')
    let laundering: table<rule: string, name: string, kind: string> = (if $ceArmed {
        []
    } else {
        let wrapping: table = ($code
            | parse -r '(?s)runCatching\s*\{(?<body>[^}]{0,300})\}'
            | where {|row| ($row.body =~ '\b(withContext|withLock|delay\(|await|\.call\(|client\.query|\.send\(|\.steer\()')}
            | each {|row| {rule: 'ce-laundering', name: 'runCatching', kind: 'suspend-body'}})
        let wide: table = ($code
            | parse -r 'catch \(\w+: (?:Exception|Throwable)\)'
            | each {|row| {rule: 'ce-laundering', name: 'catch Exception', kind: 'wide arm'}})
        [$wrapping $wide] | flatten
    })
    [$vocab $bangs $skips $vars $laundering] | flatten
}

# The denial ledger: same shape and same law as the nushell hooks' (the row is
# written right before the deny; a failed write never moves the verdict).
def log-denial [log: path, sid: string, hook: string, rule: string, language: string, target: string]: nothing -> nothing {
    try {
        mkdir ($log | path dirname)
        [(date now | format date '%FT%T%:z') $sid $hook $rule $language ($target | str replace -a "\t" ' ' | str replace -a "\n" ' ' | str replace -a "\r" ' ' | str substring 0..119)]
        | str join "\t"
        | $"($in)\n"
        | save --append $log
    } catch { }
}

def main [--log: path = $DENIALS]: string -> nothing {
    let payload: record = ($in | from json)
    let path: string = ($payload | get -o tool_input.file_path | default '')
    if not (($path | str ends-with '.kt') or ($path | str ends-with '.kts')) { exit 0 }
    let added: string = ($payload
        | get -o tool_input.content
        | default ($payload | get -o tool_input.new_string | default ''))
    if ($added | is-empty) { exit 0 }
    let sid: string = ($payload | get -o session_id | default '')

    let hits: table<rule: string, name: string, kind: string> = (findings-of $added)
    # The immutability + CE laws' jurisdiction: test sources are exempt —
    # fixtures, lateinit and test-time catching live there.
    let isTest: bool = ($path | str contains '/src/test/')
    let relevant: table<rule: string, name: string, kind: string> = (if $isTest {
        $hits | where rule in ['closed-vocabulary', 'force-unwrap', 'silent-skip-test']
    } else {
        $hits
    })
    if ($relevant | is-not-empty) {
        let hit: Finding = ($relevant | first)
        log-denial $log $sid 'kotlin-law' $hit.rule 'kotlin' $path
        match $hit.rule {
            'closed-vocabulary' => {
                print -e $"⛔ The closed-vocabulary law, plan U11: ($hit.name) re-declares a taxonomy as a collection of string literals via ($hit.kind). Declare the SUM TYPE instead: an enum with a `wire` property and a TOTAL parse — byWire map + degraded constructor, never enumValueOf, which throws on an unknown wire. The fleet's compiled example: dev.lattenero.brain.bus.CorrectionKind. Map: ~/Projects/kotlin-kb/notes/canon-map.md, section sum-product-types."
            }
            'force-unwrap' => {
                print -e $"⛔ The totality law, plan U12: `!!` throws a bare NPE with no context — the failure says nothing about which row was null. Replace it: `?: return` at the edge, `requireNotNull x { message }` when the invariant is real, or `assertNotNull x` before the use in a test, so the failure NAMES its row. Map: ~/Projects/kotlin-kb/notes/canon-map.md, section total-functions."
            }
            'silent-skip-test' => {
                print -e $"⛔ The totality law, plan U12: ($hit.name) is an expression-bodied @Test without an explicit `: Unit` — the inferred tail type can be nullable, and a not-void JUnit method is SILENTLY SKIPPED, measured in U8: a guard law that never ran. Declare `fun ($hit.name): Unit = runBlocking { ... }` and end the block with an explicit Unit statement, or pin the type with `($hit.kind)<Unit> { ... }`."
            }
            'var-in-main' => {
                print -e $"⛔ The immutability law, plan U13: ($hit.name) is a var declared in a MAIN source — mutable state is the bug budget. Bind `val` and produce a NEW value instead: a fold or reduce for accumulators, a persistent copy for updates, a holder class for late wiring. The fleet's own shape: state records snapshot without deep copies, so a new value costs nothing. Map: ~/Projects/kotlin-kb/notes/canon-map.md, section immutable-data."
            }
            'ce-laundering' => {
                print -e $"⛔ The CE law, plan U15: ($hit.name) over suspend code launders CancellationException into a value — the rescue leg then runs after the caller cancelled, and structured scopes hang or lose work. The ladder: the CancellationException arm rethrown FIRST, then the narrow arm, then the edge conversion, kap catching or settled. Pure parse conversions stay legal — runCatching over json.parse is honest. Companion: ~/Projects/fp-kb/notes/kotlin-error-taxonomy.md. Map: ~/Projects/kotlin-kb/notes/canon-map.md, section errors-as-values-in-coroutines."
            }
        }
        exit 2
    }
    exit 0
}
