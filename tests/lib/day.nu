# test_day.nu — the pure-core proofs for lib/day.nu: the quiet-repo brief,
# the memory window (garbage timestamps never count as fresh) and the capped
# memory brief.
use std/assert
use ../../lib/day.nu *

# 1. the repo brief: quiet → [], otherwise count + first line cut at 60.
assert equal (repo-briefs "/Users/lattenero/Projects/foo" []) []
assert equal (repo-briefs "/Users/lattenero/Projects/foo" ["  " ""]) []
let long_line: string = "abc1234 a commit subject that is definitely longer than sixty characters in total"
let rows: list<RepoBrief> = (repo-briefs "/Users/lattenero/Projects/foo" [$long_line "" "def5678 second"])
assert equal ($rows | length) 1
assert equal $rows.0.repo "foo"
assert equal $rows.0.n 2
assert equal ($rows.0.last | str length) 60

# 2. the memory window: parseable and inside counts; older, missing and
#    garbage createdAt never count (epoch fallback, not "now").
let cutoff: datetime = ("2026-11-23T00:00:00Z" | into datetime)
let mems: list<any> = [
    {kind: "fact", createdAt: "2026-11-24T10:00:00Z", content: "fresh one"}
    {kind: "fact", createdAt: "2026-11-20T10:00:00Z", content: "old one"}
    {kind: "fact", content: "no stamp"}
    {kind: "fact", createdAt: "not-a-date", content: "garbage stamp"}
]
let window: list<any> = (in-window $mems $cutoff)
assert equal ($window | length) 1
assert equal $window.0.content "fresh one"

# 3. the brief: content cut at 90 chars, at most 10 rows, order kept.
let many: list<any> = (1..12 | each {|i| {kind: "summary", content: ($i | into string)}})
assert equal (memory-briefs $many | length) 10
assert equal ((memory-briefs $many).0.learned) "1"
let longm: string = "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789"
assert equal (memory-briefs [{kind: "fact", content: $longm}]).0.learned ($longm | str substring 0..89)

print "test_day ok"
