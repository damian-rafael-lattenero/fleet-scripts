#!/opt/homebrew/bin/nu
# brain.nu — the brain at terminal speed: the ergonomics layer over the
# agent-brain CLI (which already does the heavy lifting — REUSE over
# rebuild). One command from any terminal, in place of the full binary path
# and error-prone raw JSON:
#   brain "question"            RAG over the corpus with citations
#   brain "question" --iterate  agentic multi-hop (decompose + fuse; a chat call)
#   brain "question" --k 10     more hits
#   brain --search "text"       search the brain's OWN memories
#   brain --recent              the latest memories
#   brain --save "text" --kind fact   write a memory (fact|decision|preference|summary)
#
# THE TWO-SIDED BRAIN (measured 21/11, the missed tool question): the
# default mode retrieves over the INDEXED CORPUS (docs + code — atemporal
# reference: "how does X work"); event and conversation questions live on
# the MEMORY side (--search / --recent). The memories are ENGLISH (the
# 19/11 normalization) — Spanish memory queries embed against language,
# not content; query them in English. And it NEVER synthesizes prose:
# retrieval only — for a spoken answer ask Z or the bot.
# Every run appends to ~/Library/Logs/brain.log.

const LOG_FILE: string = "/Users/lattenero/Library/Logs/brain.log"
const BRAIN: string = "/Users/lattenero/Projects/agent-brain/core/build/install/agent-brain/bin/agent-brain"
const KINDS: list<string> = [fact decision preference summary]

# The type aliases (the owner's 22/11 law): every shape reads once and the
# signatures spell the name. Nullable string flags = oneof<string, nothing>
# (a bare null literal against a plain string field fails the parse).
type ModeRow = record<mode: string, when: closure>
type Flags = record<question: oneof<string, nothing>, search: oneof<string, nothing>, save: oneof<string, nothing>, kind: string, recent: bool, iterate: bool>
type ModeCmd = record<mode: string, text: oneof<string, nothing>, kind: string, iterate: bool>
type Dispatch = record<rag: closure, search: closure, save: closure, recent: closure, usage: closure>
type HitRow = record<score: float, title: string, what: string>
type MemoryRow = record<id: int, kind: string, memory: string>

$env.config.table.mode = "thin"

use /Users/lattenero/Projects/nushell-fp/mods/log.nu *
use /Users/lattenero/Projects/nushell-fp/mods/proc.nu *

# One voice for stdout AND the run log — the shared mod does the work.
def emit [line: string]: nothing -> nothing {
    emit-to $LOG_FILE $line
}

def rag-section [q: string, k: int, iterate: bool]: nothing -> nothing {
    emit $"== rag — ($q) =="
    # The HTTP /rag/query over the CLI `query`: it carries the bilingual
    # ES→EN QueryExpansion leg + RRF fusion the CLI lacks — Spanish corpus
    # questions were score-floor noise through the CLI (measured 21/11).
    let body: string = ({query: $q, k: $k, iterate: $iterate} | to json)
    let out: record = (do { ^curl -s -X POST -H 'Content-Type: application/json' -d $body http://127.0.0.1:8765/rag/query } | complete)
    if $out.exit_code != 0 {
        emit $"query failed — (fold-stderr $out | str substring 0..119)"
        return
    }
    let hits: list<record> = ($out.stdout | from json | get hits)
    if ($hits | is-empty) {
        emit "no hits"
        return
    }
    let rows: list<HitRow> = ($hits | each {|h|
        {score: ($h.score? | default 0 | math round --precision 3), title: $h.title, what: ($h.content | str replace -a "\n" " " | str substring 0..69)}
    })
    emit ($rows | table)
    emit $"($hits | length) hits · top source: ($hits | first | get uri)"
}

def search-section [text: string, k: int]: nothing -> nothing {
    emit $"== memory search — ($text) =="
    let out: record = (do { ^$BRAIN memory search $text --k $k } | complete)
    if $out.exit_code != 0 {
        emit $"search failed — (fold-stderr $out | str substring 0..119)"
        return
    }
    let rows: list<MemoryRow> = ($out.stdout | from json | get memories
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
    let rows: list<MemoryRow> = ($out.stdout | from json
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
        emit $"save failed — (fold-stderr $out | str substring 0..119)"
    }
}

# The mode table: priority-ordered predicates — the FIRST row whose
# predicate holds wins. The precedence lives in the ROW ORDER, not in
# nested branches; adding a mode = adding a row. Zero if/else in the flow.
def mode-table []: nothing -> list<ModeRow> {
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
def pick-mode [f: Flags]: nothing -> ModeCmd {
    let winner: ModeRow = (mode-table | where {|row| do $row.when $f } | first)
    {
        mode: $winner.mode
        text: ($f.question? | default ($f.search? | default $f.save?))
        kind: $f.kind
        iterate: $f.iterate
    }
}

# The dispatch table: mode → closure over the mode record. Data, not flow —
# the same shape as the owner's `commands` map in config.nu.
def dispatch-table [k: int]: nothing -> Dispatch {
    {
        rag: {|c| rag-section $c.text $k $c.iterate}
        search: {|c| search-section $c.text $k}
        save: {|c| save-section $c.kind $c.text}
        recent: {|c| recent-section $k}
        usage: {|c| emit 'corpus reference lookups: brain "how does X work" · event/conversation lookups: brain --search "what happened" (memories are ENGLISH — query in English) · --save t --kind K · --recent'}
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
    let flags: Flags = {question: $question, search: $search, save: $save, kind: $kind, recent: $recent, iterate: $iterate}
    let cmd: ModeCmd = (pick-mode $flags)
    let dispatch: Dispatch = (dispatch-table $k)
    do ($dispatch | get $cmd.mode) $cmd
}
