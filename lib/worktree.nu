# lib/worktree.nu — the pure core shared by wt.nu and wt-done.nu: the
# main-line pick (master, else main), the porcelain parse, the worktree path
# and the add-args decision. The scripts keep the effects (git calls, fs).
export type PorcelainBlock = record<path: string, branch: string>

# The repo's main line: the FIRST candidate that exists, else "" (the
# fleet's order lives in the caller's list — the sweep adds damian).
export def pick-branch-of [candidates: list<string>, present: list<string>]: nothing -> string {
    $candidates | where {|c| $c in $present } | get -o 0 | default ""
}

# wt's two-candidate form: master wins, then main, else "".
export def pick-branch [has_master: bool, has_main: bool]: nothing -> string {
    let rows: list<record<branch: string, has: bool>> = [
        {branch: "master", has: $has_master}
        {branch: "main", has: $has_main}
    ]
    pick-branch-of ["master" "main"] ($rows | where has | get branch)
}

# The convention: ~/Projects/.worktrees/<repo>-<slug>.
export def worktree-path [repo_name: string, slug: string]: nothing -> string {
    "/Users/lattenero/Projects/.worktrees" | path join $"($repo_name)-($slug)"
}

# `git worktree add` args: reuse the branch when it already exists, else
# create it on the repo's main line.
export def add-args [path: string, ref: string, base: string, existing: bool]: nothing -> list<string> {
    if $existing {
        ["worktree" "add" $path $ref]
    } else {
        ["worktree" "add" "-b" $ref $path $base]
    }
}

# Parse `git worktree list --porcelain` into path/branch blocks (a detached
# HEAD block has no `branch` line and answers "").
export def porcelain-blocks [stdout: string]: nothing -> list<PorcelainBlock> {
    let text: string = ($stdout | str trim)
    if ($text | is-empty) { return [] }
    $text | split row "\n\n" | each {|block|
        let lines: list<string> = ($block | lines)
        {
            path: ($lines | where {|l| $l =~ '^worktree ' } | get -o 0 | default "" | str replace 'worktree ' '')
            branch: ($lines | where {|l| $l =~ '^branch ' } | get -o 0 | default "" | str replace 'branch refs/heads/' '')
        }
    }
}

# The linked worktrees only: git lists the main checkout first, skip it.
export def linked-blocks [stdout: string]: nothing -> list<PorcelainBlock> {
    porcelain-blocks $stdout | skip 1
}

# `git branch --merged` marks the current branch with `*` and a branch checked
# out in a worktree with `+` — strip both or the merged gate refuses forever.
export def strip-branch-markers [line: string]: nothing -> string {
    $line | str trim | str replace -r '^[\*\+\s]+' ''
}
