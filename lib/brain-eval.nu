# lib/brain-eval.nu — the pure core of brain-eval.nu: the evidence
# projection per surface, the score string, the failed-case row and the
# grading (recall@k, case-insensitive, xfail flips the verdict). The script
# keeps the curl/CLI calls and the log voice.
export type EvalCase = record<kind: string, q: string, expect: string, xfail: bool>
export type CaseResult = record<q: string, surface: string, ok: bool, xfail: bool, score: string, top: string>

# corpus rows answer titles, memory rows answer content; a missing list is
# an empty one (a zero-hit surface is an honest FAIL row, never a crash).
export def case-evidence [kind: string, parsed: any]: nothing -> list<string> {
    if $kind == "corpus" {
        $parsed | get -o hits | default [] | each {|h| $h.title }
    } else {
        $parsed | get -o memories | default [] | each {|m| $m.content }
    }
}

# The score string: corpus top hit rounded to 3 decimals, memory "-"; a
# zero-hit corpus is "-" too.
export def case-score [kind: string, parsed: any]: nothing -> string {
    if $kind != "corpus" { return "-" }
    let hits: list<any> = ($parsed | get -o hits | default [])
    if ($hits | is-empty) { "-" } else { ($hits | first | get score? | default 0 | math round --precision 3 | into string) }
}

# The transport-failure row: an unreachable surface is a FAIL, not a crash.
export def failed-case [c: EvalCase]: nothing -> CaseResult {
    {q: $c.q, surface: $c.kind, ok: false, xfail: false, score: "-", top: "FAILED"}
}

# recall@k: the expectation may sit in ANY returned row, case-insensitively
# (Nushell vs nushell — measured own bug). xfail rows pass when they fail.
export def grade-case [c: EvalCase, evidence: list<string>, score: string]: nothing -> CaseResult {
    let expect_lower: string = ($c.expect | str lowercase)
    let ok: bool = ($evidence | any {|e| ($e | str lowercase) =~ $expect_lower })
    let verdict: bool = (if $c.xfail { not $ok } else { $ok })
    let top: string = (if ($evidence | is-empty) { "no hits" } else { ($evidence | first | str substring 0..59) })
    {q: $c.q, surface: $c.kind, ok: $verdict, xfail: $c.xfail, score: $score, top: $top}
}
