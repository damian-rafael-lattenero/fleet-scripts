#!/opt/homebrew/bin/nu
# PreToolUse(Write|Edit) on .kt/.kts — THE CLOSED-VOCABULARY LAW (plan U11,
# rung 1, the measured #1 violation: stringly-typed taxonomies).
#
# A taxonomy of wire values is a SUM TYPE: declare an enum with a `wire`
# property and a TOTAL parse (byWire map + degraded constructor — the fleet's
# compiled example: CorrectionKind). A `Set<String>`/`List<String>`/array of
# string literals under a constant name that names a vocabulary (KINDS, VOCAB…,
# STATES, TYPES) re-declares the taxonomy by hand — DENIED from day 1.
#
# Scope honesty (v1): the gate judges what the edit ADDS (Write: the whole
# content; Edit: only new_string) — a one-line addition to an existing
# vocabulary set is caught only when the set itself is rewritten. Legacy
# TRANSLATION tables (mapOf of wire → wire) are the parse-table shape, not a
# vocabulary: allowed on purpose. Fail-open: any crash exits nonzero-but-not-2
# and never blocks.

const DENIALS: path = '/Users/lattenero/.zcode/hooks/state/denials.tsv'

# The vocabulary name runs that mark a taxonomy constant (measured census:
# CORRECTION_KINDS, BREAKER_STATES — and zero false positives fleet-wide).
const NAME_RUNS = ['KINDS' 'VOCAB' 'STATES' 'TYPES']

# The law's one predicate: the string-literal collections that re-declare a
# taxonomy. Returns one row per finding: {name, kind}.
export def findings-of [content: string]: nothing -> table<name: string, kind: string> {
    ($content | parse -r '(?s)(?:const\s+)?val\s+(?<name>[A-Z][A-Za-z0-9_]*)\s*(?::[^=\n]+)?=\s*(?<init>setOf|listOf|arrayOf)\s*\((?<args>[^)]*)\)')
    | where {|row|
        let named: bool = ($NAME_RUNS | any {|run| ($row.name | str contains $run)})
        let literals: int = ($row.args | parse -r '"[^"]*"' | length)
        $named and ($literals >= 2)
    }
    | select name init
    | rename name kind
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

    let hits: table<name: string, kind: string> = (findings-of $added)
    if ($hits | is-not-empty) {
        let hit: record<name: string, kind: string> = ($hits | first)
        log-denial $log $sid 'kotlin-law' 'closed-vocabulary' 'kotlin' $path
        print -e $"⛔ The closed-vocabulary law, plan U11: ($hit.name) re-declares a taxonomy as a collection of string literals via ($hit.kind). Declare the SUM TYPE instead: an enum with a `wire` property and a TOTAL parse — byWire map + degraded constructor, never enumValueOf, which throws on an unknown wire. The fleet's compiled example: dev.lattenero.brain.bus.CorrectionKind. Map: ~/Projects/kotlin-kb/notes/canon-map.md, section sum-product-types."
        exit 2
    }
    exit 0
}
