# test_brain.nu — the pure-core proofs for lib/brain.nu: the mode priority
# table, the flag→payload classification (parse once), the kind cover and the
# two render projections.
use std/assert
use ../../lib/brain.nu *

def flags [question: any, search: any, save: any, kind: string, recent: bool, iterate: bool]: nothing -> Flags {
    {question: $question, search: $search, save: $save, kind: $kind, recent: $recent, iterate: $iterate}
}

# 1. nothing flagged → usage, and text stays null.
let usage: ModeCmd = (pick-mode (flags null null null "fact" false false))
assert equal $usage.mode "usage"
assert equal $usage.text null

# 2. the PRIORITY table: search > save > recent > rag > usage.
assert equal (pick-mode (flags null "q" null "fact" false false)).mode "search"
assert equal (pick-mode (flags null null "m" "fact" true false)).mode "save"
assert equal (pick-mode (flags "question" null "m" "fact" false false)).mode "save"
assert equal (pick-mode (flags "question" null null "fact" true false)).mode "recent"
assert equal (pick-mode (flags "question" null null "fact" false false)).mode "rag"
assert equal (pick-mode (flags null "q" "m" "fact" false false)).mode "search"

# 3. parse-don't-validate: text is the winner's input, kind/iterate pass through.
let search: ModeCmd = (pick-mode (flags null "needle" null "fact" false false))
assert equal $search.text "needle"
let save: ModeCmd = (pick-mode (flags null null "the memory" "decision" false false))
assert equal $save.text "the memory"
assert equal $save.kind "decision"
let rag: ModeCmd = (pick-mode (flags "how does X work" null null "fact" false true))
assert equal $rag.mode "rag"
assert equal $rag.text "how does X work"
assert equal $rag.iterate true
assert equal $rag.kind "fact"
# text is the ?? chain (question ?? search ?? save): with save as the mode a
# non-null question still wins the TEXT slot — the classification and the
# payload are independent answers, by design.
assert equal (pick-mode (flags "q" null "saved" "fact" false false)).text "q"

# 4. the kind cover is exactly the CLI's four kinds.
assert equal $KINDS [fact decision preference summary]
assert equal ("fact" in $KINDS) true
assert equal ("bogus" in $KINDS) false

# 5. the hit projection: score rounded to 3 decimals, missing -> 0.0,
#    newlines flattened, content cut at 70 chars.
let long: string = "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890"
assert equal ($long | str length) 91
let hits: list<HitRow> = (hit-rows [
    {score: 0.56864, title: "t1", content: $"line one\nline two\n($long)"}
    {title: "t2", content: "short"}
])
assert equal $hits.0.score 0.569
assert equal $hits.1.score 0.0
assert str contains $hits.0.what "line one line two"
assert equal ($hits.0.what | str length) 70
assert equal $hits.1.what "short"
assert equal $hits.1.title "t2"

# 6. the memory projection: content cut at 80, id/kind passthrough.
let mems: list<MemoryRow> = (memory-rows [
    {id: 7, kind: "fact", content: $long}
    {id: 8, kind: "decision", content: "tiny"}
])
assert equal $mems.0.id 7
assert equal $mems.0.kind "fact"
assert equal ($mems.0.memory | str length) 80
assert equal $mems.1.memory "tiny"

print "test_brain ok"
