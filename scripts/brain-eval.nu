#!/opt/homebrew/bin/nu
# brain-eval.nu — the question battery for the terminal brain: many
# questions, both surfaces (corpus rag + memory search), each with the
# EXPECTED evidence, one judged report. The regression suite for the
# owner's 21/11 order: "generate many questions, fix every error, make
# the rag/brain questions and answers make sense".
# Corpus cases expect a title/uri containing `expect`; memory cases expect
# the top memory content to contain `expect`. Exit 1 on any FAIL.
# Every run appends to ~/Library/Logs/brain-eval.log.

const LOG_FILE: string = "/Users/lattenero/Library/Logs/brain-eval.log"
const BRAIN: string = "/Users/lattenero/Projects/agent-brain/core/build/install/agent-brain/bin/agent-brain"
const RAG_URL: string = "http://127.0.0.1:8765/rag/query"

# The shapes, the grading laws and the projections ride lib/brain-eval.nu
# (tested). Every case row carries xfail EXPLICITLY — a record literal
# MISSING the key does not satisfy a oneof<..., nothing> field (measured
# 22/11); explicit data beats optional keys.
use ../lib/brain-eval.nu *

use /Users/lattenero/Scripts/nushell-fp/mods/log.nu *

# One voice for stdout AND the run log — the shared mod does the work
# (the hand-rolled print+save copy leaves the family contract).
def emit [line: string]: nothing -> nothing {
    emit-to $LOG_FILE $line
}

# {kind: "corpus"|"memory", q: "...", expect: "substring that must appear in the top result"}
const CASES: list<EvalCase> = [
    {kind: "corpus", q: "how does the nushell job mailbox timeout work", expect: "job", xfail: false}
    {kind: "corpus", q: "what is the anti-patterns law", expect: "anti-patterns-law", xfail: false}
    {kind: "corpus", q: "nushell typed main signature law", expect: "typing-law", xfail: false}
    {kind: "corpus", q: "how does ram-clean protect my own session ancestry", expect: "ram-clean", xfail: false}
    {kind: "corpus", q: "kap process restart schedule retry", expect: "kap", xfail: false}
    {kind: "corpus", q: "what does the opaque types law say", expect: "no-opaque-types", xfail: false}
    {kind: "memory", q: "which tool shined yesterday nushell fleet", expect: "nushell", xfail: false}
    {kind: "memory", q: "fork deploy card scroll horizontal", expect: "scroll", xfail: false}
]

# corpus: POST /rag/query (bilingual); memory: CLI memory search.
def run-case [c: EvalCase]: nothing -> CaseResult {
    let out: record = (if $c.kind == "corpus" {
        do { ^curl -s -X POST -H 'Content-Type: application/json' -d ({query: $c.q, k: 3} | to json) $RAG_URL } | complete
    } else {
        do { ^$BRAIN memory search $c.q --k 3 } | complete
    })
    if $out.exit_code != 0 { return (failed-case $c) }
    let parsed: any = ($out.stdout | from json)
    # recall@k, the score string and the top cut ride the lib (tested): a
    # zero-hit surface is an honest FAIL row, never a crash.
    let evidence: list<string> = (case-evidence $c.kind $parsed)
    grade-case $c $evidence (case-score $c.kind $parsed)
}

def main []: nothing -> nothing {
    let stamp: string = (date now | format date "%Y-%m-%d %H:%M")
    emit $"== brain-eval ($stamp) — ($CASES | length) questions =="
    let rows: list<CaseResult> = ($CASES | each {|c| run-case $c })
    emit ($rows | select q surface ok xfail score top | table -w 85)
    let passN: int = ($rows | where ok | length)
    let failN: int = (($rows | length) - $passN)
    emit $"PASS ($passN) · FAIL ($failN)"
    if $failN > 0 {
        emit "== the failures =="
        emit ($rows | where {|r| not $r.ok } | select q surface top | table -w 85)
        exit 1
    }
}
