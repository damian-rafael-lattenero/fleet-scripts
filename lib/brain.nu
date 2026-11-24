# lib/brain.nu — the pure core of brain.nu: the flag→mode classification
# (a priority table, never a branch chain), the cover set of memory kinds,
# and the two render projections (hits, memories). The script keeps the
# effects (curl, the CLI, the log voice).
export type ModeRow = record<mode: string, when: closure>
export type Flags = record<question: oneof<string, nothing>, search: oneof<string, nothing>, save: oneof<string, nothing>, kind: string, recent: bool, iterate: bool>
export type ModeCmd = record<mode: string, text: oneof<string, nothing>, kind: string, iterate: bool>
export type HitRow = record<score: float, title: string, what: string>
export type MemoryRow = record<id: int, kind: string, memory: string>

export const KINDS: list<string> = [fact decision preference summary]

# The mode table: priority-ordered predicates — the FIRST row whose predicate
# holds wins. The precedence lives in the ROW ORDER, not in nested branches;
# adding a mode = adding a row (search > save > recent > rag > usage).
export def mode-table []: nothing -> list<ModeRow> {
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
export def pick-mode [f: Flags]: nothing -> ModeCmd {
    let winner: ModeRow = (mode-table | where {|row| do $row.when $f } | first)
    {
        mode: $winner.mode
        text: ($f.question? | default ($f.search? | default $f.save?))
        kind: $f.kind
        iterate: $f.iterate
    }
}

# The RAG hit projection: score rounded to 3 decimals (missing → 0.0),
# newlines flattened, content cut at 70 chars.
export def hit-rows [hits: list<any>]: nothing -> list<HitRow> {
    $hits | each {|h|
        {
            score: ($h.score? | default 0.0 | math round --precision 3)
            title: ($h.title? | default "")
            what: ($h.content? | default "" | str replace -a "\n" " " | str substring 0..69)
        }
    }
}

# The memory projection: content cut at 80 chars, id/kind passthrough.
export def memory-rows [memories: list<any>]: nothing -> list<MemoryRow> {
    $memories | each {|m| {id: $m.id, kind: $m.kind, memory: ($m.content | str substring 0..79)} }
}
