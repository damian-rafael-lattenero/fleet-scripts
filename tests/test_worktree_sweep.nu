# test_worktree_sweep.nu — the pure-core proofs for lib/worktree-sweep.nu:
# both verdict tables (row order is the law), the age gate and the
# "branch at path" item parse.
use std/assert
use ../lib/worktree-sweep.nu *

# 1. the worktree verdict: dirty convicts first, then not-merged, then clean.
assert equal (wt-verdict true true "master") {action: "KEEP", why: "dirty working tree"}
assert equal (wt-verdict true false "master") {action: "KEEP", why: "dirty working tree"}
assert equal (wt-verdict false false "damian") {action: "KEEP", why: "not merged into damian"}
assert equal (wt-verdict false true "master") {action: "CLEAN-able", why: "merged + clean"}

# 2. the orphan verdict: real worktree, then origin, then the age gate.
assert equal (orphan-verdict false true 99 1).action "KEEP"
assert equal (orphan-verdict false false 99 1).action "KEEP"
assert equal (orphan-verdict true true 99 1).action "KEEP"
assert equal (orphan-verdict true false 99 1) {action: "ORPHAN-able", why: "clone fixture, no origin — past the age gate"}
assert equal (orphan-verdict true false 1 1).action "ORPHAN-able"    # the gate is >=
assert equal (orphan-verdict true false 0 1).action "KEEP"
assert equal (orphan-verdict true false 0 1).why "clone fixture fresh — below the age gate, a live test may own it"

# 3. the age gate: floor hours, zero for a fresh mtime.
let now: datetime = ("2026-11-24 12:00:00" | into datetime)
assert equal (age-h ("2026-11-24 10:30:00" | into datetime) $now) 1
assert equal (age-h ("2026-11-24 11:59:59" | into datetime) $now) 0
assert equal (age-h ("2026-11-23 12:00:00" | into datetime) $now) 24

# 4. the item parse: branch before, path after the ` at `.
assert equal (item-parts "agent/fix at /Users/lattenero/Projects/.worktrees/repo-fix") {branch: "agent/fix", path: "/Users/lattenero/Projects/.worktrees/repo-fix"}
assert equal (item-parts "plain") {branch: "plain", path: ""}
assert equal (item-parts "") {branch: "", path: ""}

print "test_worktree_sweep ok"
