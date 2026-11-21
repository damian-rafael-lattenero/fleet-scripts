#!/opt/homebrew/bin/nu
# brain.nu — the brain at terminal speed: the ergonomics layer over the
# agent-brain CLI (which already does the heavy lifting — REUSE over
# rebuild). One command from any terminal, in place of the full binary path
# and raw JSON:
#   brain "question"            RAG over the corpus with citations
#   brain "question" --iterate  agentic multi-hop (decompose + fuse; a chat call)
#   brain "question" --k 10     more hits
#   brain --search "text"       search the brain's OWN memories
#   brain --recent              the latest memories
#   brain --save "text" --kind fact   write a memory (fact|decision|preference|summary)
# Every run appends to ~/Library/Logs/brain.log.

const LOG_FILE: string = "/Users/lattenero/Library/Logs/brain.log"
const BRAIN: string = "/Users/lattenero/Projects/agent-brain/core/build/install/agent-brain/bin/agent-brain"
const KINDS: list<string> = [fact decision preference summary]

$env.config.table.mode = "thin"

def emit [line: string]: nothing -> nothing {
    print $line
    $"($line)\n" | save --append --raw $LOG_FILE
}

def rag-section [q: string, k: int, iterate: bool]: nothing -> nothing {
    emit $"== rag — ($q) =="
    # argv list must be ALL strings — a bare int in the literal makes it
    # list<oneof<string,int>> and the spread dies at parse (measured 21/11).
    let cmd: list<string> = ([query $q --k $"($k)"] ++ (if $iterate { ["--iterate"] } else { [] }))
    let out: record = (do { ^$BRAIN ...$cmd } | complete)
    if $out.exit_code != 0 {
        emit $"query failed — ($out.stderr | str substring 0..119)"
        return
    }
    let hits: list<record> = ($out.stdout | from json | get hits)
    if ($hits | is-empty) {
        emit "no hits"
        return
    }
    emit ($hits | each {|h|
        {score: ($h.score? | default 0 | math round --precision 3), title: $h.title, what: ($h.content | str replace -a "\n" " " | str substring 0..69)}
    } | table)
    emit $"($hits | length) hits · top source: ($hits | first | get uri)"
}

def search-section [text: string, k: int]: nothing -> nothing {
    emit $"== memory search — ($text) =="
    let out: record = (do { ^$BRAIN memory search $text --k $k } | complete)
    if $out.exit_code != 0 {
        emit $"search failed — ($out.stderr | str substring 0..119)"
        return
    }
    let rows: list<record> = ($out.stdout | from json | get memories
        | each {|m| {id: $m.id, kind: $m.kind, memory: ($m.content | str substring 0..79)} })
    if ($rows | is-empty) {
        emit "no memories match"
    } else {
        emit ($rows | table)
    }
}

def recent-section [k: int]: nothing -> nothing {
    emit $"== recent memories — last ($k) =="
    let out: record = (do { ^$BRAIN memory recent --k $k } | complete)
    if $out.exit_code != 0 {
        emit "brain degraded: recent unavailable"
        return
    }
    let rows: list<record> = ($out.stdout | from json
        | each {|m| {id: $m.id, kind: $m.kind, memory: ($m.content | str substring 0..79)} })
    emit ($rows | table)
}

def save-section [kind: string, text: string]: nothing -> nothing {
    if (not ($kind in $KINDS)) {
        emit $"invalid kind '($kind)' — valid: ($KINDS | str join ', ')"
        return
    }
    let out: record = (do { ^$BRAIN memory save $kind $text } | complete)
    if $out.exit_code == 0 {
        emit $"memory saved: ($out.stdout | str trim | str substring 0..119)"
    } else {
        emit $"save failed — ($out.stderr | str substring 0..119)"
    }
}

# The mode table: priority-ordered predicates — the FIRST row whose
# predicate holds wins. The precedence lives in the ROW ORDER, not in
# nested branches; adding a mode = adding a row. Zero if/else in the flow.
def mode-table []: nothing -> list<record> {
    [
        {mode: "search", when: {|f| $f.search != null}}
        {mode: "save", when: {|f| $f.save != null}}
        {mode: "recent", when: {|f| $f.recent}}
        {mode: "rag", when: {|f| $f.question != null}}
        {mode: "usage", when: {|f| true}}
    ]
}

# parse-don't-validate: flags classified ONCE into one uniform payload —
# text is the mode's primary input (question ?? search ?? save).
def pick-mode [f: record]: nothing -> record {
    let winner: record = (mode-table | where {|row| do $row.when $f } | first)
    {
        mode: $winner.mode
        text: ($f.question? | default ($f.search? | default $f.save?))
        kind: $f.kind
        iterate: $f.iterate
    }
}

# The dispatch table: mode → closure over the mode record. Data, not flow —
# the same shape as the owner's `commands` map in config.nu.
def dispatch-table [k: int]: nothing -> record {
    {
        rag: {|c| rag-section $c.text $k $c.iterate}
        search: {|c| search-section $c.text $k}
        save: {|c| save-section $c.kind $c.text}
        recent: {|c| recent-section $k}
        usage: {|c| emit 'usage: brain "question" | brain "q" --iterate | --search "text" | --save "text" --kind fact | --recent'}
    }
}

def main [
    question?: string  # RAG query with citations (the default mode)
    --k: int = 5       # hits/rows to return
    --iterate          # agentic multi-hop: decompose + fuse (spends a chat call)
    --search: string   # search the brain's OWN memories
    --save: string     # save a memory (pair with --kind)
    --kind: string = "fact"  # memory kind: fact|decision|preference|summary
    --recent           # the latest memories
]: nothing -> nothing {
    let flags: record = {question: $question, search: $search, save: $save, kind: $kind, recent: $recent, iterate: $iterate}
    let cmd: record = (pick-mode $flags)
    let table: record = (dispatch-table $k)
    do ($table | get $cmd.mode) $cmd
}
