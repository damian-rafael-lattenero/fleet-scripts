# test_worktree.nu — the pure-core proofs for lib/worktree.nu: the main-line
# pick, the path convention, the add-args decision, the porcelain parse and
# the merged-list marker strip. It also covers the two thin CLIs over it.
# covers: /Users/lattenero/Scripts/scripts/wt.nu
# covers: /Users/lattenero/Scripts/scripts/wt-done.nu
use std/assert
use ../../lib/worktree.nu *

# 1. the main-line pick: master wins, then main, else "".
assert equal (pick-branch true true) "master"
assert equal (pick-branch false true) "main"
assert equal (pick-branch true false) "master"
assert equal (pick-branch false false) ""

# 2. the path convention.
assert equal (worktree-path "zcode-bot-kotlin" "fix-quota") "/Users/lattenero/Projects/.worktrees/zcode-bot-kotlin-fix-quota"

# 3. the add-args decision: existing branch is reused, new one bases on main.
assert equal (add-args "/wt" "agent/x" "master" true) ["worktree" "add" "/wt" "agent/x"]
assert equal (add-args "/wt" "agent/x" "master" false) ["worktree" "add" "-b" "agent/x" "/wt" "master"]

# 4. the porcelain parse: the main checkout is skipped, the linked block
#    answers path+branch, a detached HEAD block answers branch "".
let porcelain: string = "worktree /Users/x/main
HEAD abc123
branch refs/heads/master

worktree /Users/x/wt
HEAD def456
branch refs/heads/agent/foo

worktree /Users/x/detached
HEAD 999aaa
detached
"
let all: list<PorcelainBlock> = (porcelain-blocks $porcelain)
assert equal ($all | length) 3
assert equal $all.0.path "/Users/x/main"
assert equal $all.0.branch "master"
assert equal $all.1.branch "agent/foo"
assert equal $all.2.branch ""
let linked: list<PorcelainBlock> = (linked-blocks $porcelain)
assert equal ($linked | length) 2
assert equal ($linked | first | get branch) "agent/foo"

# 5. empty output answers an empty list (the post-cleanup normal state).
assert equal (porcelain-blocks "") []
assert equal (porcelain-blocks "  \n ") []

# 6. the merged-list markers: * current, + checked out in a worktree.
assert equal (strip-branch-markers "* master") "master"
assert equal (strip-branch-markers "+ agent/foo") "agent/foo"
assert equal (strip-branch-markers "  main") "main"
assert equal (strip-branch-markers "*+ agent/x") "agent/x"
assert equal (strip-branch-markers "agent/plain") "agent/plain"

# 7. the live-git proof: a real `worktree list --porcelain` from a temp repo
#    parses to the same shape (the fixture cannot drift from git's format).
let tmp: path = ($"($env.TMPDIR? | default /tmp)/wt-(random uuid)")
mkdir $tmp
^git -C $tmp init -q -b master
^git -C $tmp -c user.email=t@t -c user.name=T commit --allow-empty -qm init
^git -C $tmp worktree add -q -b agent/drill $"($tmp)-drill"
let live: list<PorcelainBlock> = (linked-blocks ((do { ^git -C $tmp worktree list --porcelain } | complete).stdout))
assert equal ($live | length) 1
assert equal ($live | first | get branch) "agent/drill"
assert equal (($live | first | get path) | path basename) ($"($tmp)-drill" | path basename)   # /private symlink on macOS
^git -C $tmp worktree remove --force $"($tmp)-drill"
^rm -rf $tmp

print "test_worktree ok"
