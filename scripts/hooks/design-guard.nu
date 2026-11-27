#!/opt/homebrew/bin/nu
# design-guard.nu — THE DENOTATIONAL LADDER, served at the design moment.
#
# The giant linter's two existing halves fire at WRITE time (rag-guard
# retrieval + anti-pattern-lint mechanics); the semantic decisions — curry
# vs functor vs applicative vs ADT — happen BEFORE, when the design is
# born. This hook is that third half (owner's order, 22/11: make it shine
# — the ecosystem must tell the LLM to build with denotational structure).
#
# The two design moments it watches:
#   · PreToolUse(Write) where the file DOES NOT EXIST — a new module is
#     being born; the Ladder rides as additionalContext before the first
#     line lands.
#   · UserPromptSubmit carrying design intent (a new script/module/command
#     asked, a refactor designed) — the Ladder joins the prompt's context.
#
# The method is Conal Elliott's denotational design (LambdaJam 2015, "from
# meanings to programs"): form first, choose the denotation, specify by
# equations, check the homomorphism — a failing law is a DESIGN SIGNAL.
# The answers map onto OUR stdlib (nushell-fp, kap, fp-kb), so the Ladder
# names the piece instead of the theory.

# THE LADDER (static, ~350 tokens, zero external calls — prompt-laws' own
# economy). Single-quoted: parens are literal text here, never subexprs.
const LADDER: string = '🪜 DENOTATIONAL LADDER — design this, do not code it yet. (0) FORM FIRST: name the values and operations before any implementation; if the form is hard to say, the design is wrong. (1) THE MEANING: what does each type DENOTE, stripped of implementation? Say it in one sentence — that sentence becomes the file header ADR line. (2) THE EIGHT QUESTIONS — every answer is an existing stdlib piece, compose it, new code is the LAST resort: · can it fail → Result as VALUE (nushell-fp attempt/ok/err; Kotlin CE channel) — never thrown across logic, never null-probed · many shapes of one thing → ADT: tagged record + type alias (Opt/Res; Kotlin sealed) · dispatch on data → PRIORITY TABLE: predicate rows, payload closures AS THUNKS — rows pick the branch, only the winner pays · independent pieces → applicative parallelism (traverse-jobs / build-record-jobs; kap .with) · combining n things → monoid: define empty+combine, fold-map does the rest · expensive or conditional work → defer it (closures are thunks, lazy.nu; guards before builds; filter EARLY in pipelines) · effects → the EDGES only (complete records at the boundary, emit-to for the voice) — the core stays pure · external data → parse-don-t-validate: parse ONCE into tagged records; traverse-validated collects ALL errors. (3) THE HOMOMORPHISM CHECK: the meaning of the whole must follow from the meanings of the parts — a failing law is a DESIGN SIGNAL: redesign the denotation, never patch the code. (4) Then, and only then, code — minimal, typed, tested.'

# The new-file extensions worth a Ladder (the fleet's source surfaces).
const SOURCE_EXT: list<string> = [".nu" ".kt" ".kts" ".ts" ".tsx" ".mjs" ".js" ".py" ".hs"]

# The LIVE CANON (U9): at a Haskell design moment the Ladder is joined by the
# Canon's own hits for the concept — rag-guard's job-budget mechanism, 5 s
# deadline, fail-open (a slow brain delays no design). The words come from
# the file's name: EitherAndErrors.hs queries "either errors law canon".
const CANON_BIN: string = '/Users/lattenero/Projects/agent-brain/core/build/install/agent-brain/bin/agent-brain'
const CANON_BUDGET: duration = 5sec

def canon-hits [stem: string]: nothing -> string {
    let words: string = ($stem | str replace -a -r '(?<=[a-z])(?=[A-Z])' ' ' | str lowercase)
    let tag: int = (random int 1..100000)
    let id: int = (job spawn --description 'design-guard canon query' {
        ^$CANON_BIN query $"($words) law canon" --k 3 | complete | job send 0 --tag $tag
    })
    let run: record = (try { job recv --tag $tag --timeout $CANON_BUDGET } catch {
        job kill $id
        { exit_code: 124, stdout: '', stderr: 'deadline exceeded' }
    })
    let parsed: any = (try { $run.stdout | from json } catch { {} })
    let hits: list<record> = ($parsed | get -o hits | default [])
    let titles: list<string> = ($hits | each {|h| $"· ($h.title) — ($h.uri)" })
    if ($titles | is-empty) { '' } else {
        $"CANON NOW — top hits for this concept:
($titles | str join "\n")"
    }
}

# THE design-intent classifier, PURE (testable without a prompt): the
# creation of a new artifact or an architecture/refactor ask. Bug fixes,
# status questions and plain conversations do NOT fire — the Ladder is
# served at design moments, not everywhere.
def design-intent? [prompt: string]: nothing -> bool {
    let p: string = ($prompt | str lowercase)
    let asks: list<string> = [
        'nuev[oa] (script|módulo|module|comando|command|librería|lib|helper|daemon|skill)'
        '(cre|hac)[eéaá]+(te|me)? ?(un|una|el|la)? ?(script|módulo|module|comando|command|librería|lib|helper|daemon)'
        '(write|create|build) (me )?(a |an )?(new )?(script|module|command|library|helper|daemon)'
        'refactor'
        'redise'
        'redesign'
        'arquitect'
        'architect'
        'denotacion'
        'denotational'
        'diseñ'
        'design'
    ]
    ($asks | any {|a| $p =~ $a })
}

def serve [event: string, canon: string = '']: nothing -> nothing {
    let body: string = (if ($canon | is-empty) { $LADDER } else { $LADDER + "\n\n" + $canon })
    { hookSpecificOutput: { hookEventName: $event, additionalContext: $body } } | to json -r | print
}

def selftest []: nothing -> nothing {
    let cases: list<record<name: string, got: bool, want: bool>> = [
        {name: "new-script-es", got: (design-intent? "haceme un nuevo script que limpie ram"), want: true}
        {name: "create-module-es", got: (design-intent? "creá un módulo de parsing"), want: true}
        {name: "refactor", got: (design-intent? "refactoré el dispatcher"), want: true}
        {name: "design-en", got: (design-intent? "design the new ingestion module"), want: true}
        {name: "redesign", got: (design-intent? "rediseñá la ingesta"), want: true}
        {name: "bugfix-NOT-design", got: (design-intent? "arreglá el bug del scroll"), want: false}
        {name: "status-NOT_design", got: (design-intent? "cómo va el deploy?"), want: false}
        {name: "chat-NOT_design", got: (design-intent? "me encanta como quedó"), want: false}
    ]
    let fails: list<record> = ($cases | where {|c| $c.got != $c.want })
    for f in $fails { print $"FAIL ($f.name)" }
    print $"design-guard selftest: ($cases | length) cases, ($fails | length) failures"
    if ($fails | is-not-empty) { exit 1 }
}

def main []: string -> nothing {
    let payload: record = ($in | from json)
    if ($payload | get -o selftest | default false) { selftest; return }
    let event: string = ($payload | get -o hook_event_name | default '')
    if $event == 'UserPromptSubmit' {
        let prompt: string = ($payload | get -o prompt | default '')
        if (design-intent? $prompt) { serve 'UserPromptSubmit' }
        exit 0
    }
    if $event == 'PreToolUse' {
        let tool: string = ($payload | get -o tool_name | default '')
        if $tool != 'Write' { exit 0 }
        let input: record = ($payload | get -o tool_input | default {})
        let path: string = ($input | get -o file_path | default '')
        let isSource: bool = ($SOURCE_EXT | any {|e| $path | str ends-with $e })
        # THE NEW-FILE MOMENT: the design fires when the module is BEING
        # BORN — an existing file's edit is write-time, the other halves'
        # territory
        if $isSource and (not ($path | path exists)) {
            # U9: for a HASKELL module being born, the Canon speaks live —
            # its top hits for the concept join the Ladder (5 s budget,
            # fail-open: a slow brain delays no design). The other languages
            # keep the static Ladder alone.
            let canon: string = (if ($path | str ends-with '.hs') {
                canon-hits ($path | path parse | get stem)
            } else { '' })
            serve 'PreToolUse' $canon
        }
        exit 0
    }
    exit 0
}
