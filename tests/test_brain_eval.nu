# test_brain_eval.nu — the pure-core proofs for lib/brain-eval.nu: the
# evidence projection per surface, the score string, the failed row and the
# grading laws (case-insensitive recall@k, xfail flips, empty is honest).
use std/assert
use ../lib/brain-eval.nu *

def case [kind: string, q: string, expect: string, xfail: bool]: nothing -> EvalCase {
    {kind: $kind, q: $q, expect: $expect, xfail: $xfail}
}

# 1. the evidence projection: corpus answers titles, memory answers content,
#    a missing list is empty (never a crash).
assert equal (case-evidence "corpus" {hits: [{title: "a"} {title: "b"}]}) ["a" "b"]
assert equal (case-evidence "memory" {memories: [{content: "m1"}]}) ["m1"]
assert equal (case-evidence "corpus" {}) []
assert equal (case-evidence "memory" {}) []

# 2. the score string: corpus top hit rounded, memory "-", empty corpus "-".
assert equal (case-score "corpus" {hits: [{score: 0.56864}]}) "0.569"
assert equal (case-score "corpus" {hits: [{title: "no score"}]}) "0"
assert equal (case-score "corpus" {}) "-"
assert equal (case-score "memory" {memories: [{score: 9.9}]}) "-"

# 3. the failed row: unreachable surface convicts as a plain FAIL.
let failed: CaseResult = (failed-case (case "corpus" "q" "e" false))
assert equal $failed.ok false
assert equal $failed.xfail false
assert equal $failed.score "-"
assert equal $failed.top "FAILED"

# 4. the grading law: any-row match, case-insensitive; top cut at 60.
let long: string = "Nushell " + ("x" | fill -w 80 | str substring 0..79)
let pass: CaseResult = (grade-case (case "corpus" "q" "nushell" false) [$long] "0.5")
assert equal $pass.ok true
assert equal ($pass.top | str length) 60
assert equal (grade-case (case "corpus" "q" "needle" false) ["hay" "NEEDLE here"] "0.5").ok true
assert equal (grade-case (case "corpus" "q" "needle" false) ["hay"] "0.5").ok false

# 5. xfail flips the verdict both ways.
assert equal (grade-case (case "memory" "q" "nushell" true) ["hay"] "-").ok true
assert equal (grade-case (case "memory" "q" "nushell" true) ["nushell"] "-").ok false

# 6. the empty surface: honest FAIL row with the "no hits" top.
let empty: CaseResult = (grade-case (case "corpus" "q" "anything" false) [] "-")
assert equal $empty.ok false
assert equal $empty.top "no hits"

print "test_brain_eval ok"
