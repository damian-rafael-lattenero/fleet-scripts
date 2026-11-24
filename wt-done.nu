#!/opt/homebrew/bin/nu
# wt-done.nu — the mirror of wt: ONE worktree's audit-then-clean. The gate
# is worktree-sweep's own law: merged into the repo's main line AND a clean
# tree, or it refuses and says why — never a force, never a guess. Targets
# ONLY ~/Projects/.worktrees/* (a main checkout is never a wt-done target).
# target: the slug, or any fragment of the worktree path.

const WORKTREES: string = "/Users/lattenero/Projects/.worktrees"

use lib/worktree.nu *

# The repo's main line: master, else main, else "" (worktree-sweep's law).
def main-branch [repo: string]: nothing -> string {
    let has_master: bool = ((do { ^git -C $repo rev-parse --verify master } | complete).exit_code == 0)
    let has_main: bool = ((do { ^git -C $repo rev-parse --verify main } | complete).exit_code == 0)
    pick-branch $has_master $has_main
}

def main [
    target: string
]: nothing -> nothing {
    # the bare-glob law: zero matches kill the script — the empty .worktrees
    # dir is the NORMAL post-cleanup state, guard it
    let candidates: list<string> = (try {
        glob $"($WORKTREES)/*" | where {|p| ($p | path basename) =~ $target }
    } catch { [] })
    if ($candidates | is-empty) {
        print $"no worktree matches '($target)' — wt lists them"
        exit 1
    }
    if (($candidates | length) > 1) {
        print $"ambiguous — '($target)' matches:"
        $candidates | each {|c| print $"  ($c)" }
        exit 1
    }
    let path: string = ($candidates | first)
    let wtOut: record = (do { ^git -C $path worktree list --porcelain } | complete)
    if $wtOut.exit_code != 0 { print -e $"✗ not a git worktree: ($path)"; exit 1 }
    let branch: string = (linked-blocks $wtOut.stdout | get -o 0 | default {branch: ""} | get branch)
    # the MAIN repo, not the worktree: show-toplevel from inside a worktree
    # answers the worktree itself — the common dir's parent is the real one
    let common: string = (do { ^git -C $path rev-parse --git-common-dir } | complete | get stdout | str trim)
    let repo: string = ($common | path dirname)
    let main: string = (main-branch $repo)

    print $"== wt-done ($path | path basename) — branch ($branch), repo ($repo | path basename) =="

    # gate 1: the tree must be CLEAN (uncommitted work is the owner's call)
    let dirty: string = ((do { ^git -C $path status --porcelain } | complete).stdout | str trim)
    if not ($dirty | is-empty) {
        print $"✗ dirty working tree — commit or stash first:"
        $dirty | lines | each {|l| print $"  ($l)" }
        exit 1
    }
    # gate 2: the branch must be MERGED into the repo's main line
    # (the `+` prefix marks a branch checked out in a worktree — strip it
    # together with the `*` current-branch marker, or the gate refuses a
    # merged branch forever)
    let merged: list<string> = ((do { ^git -C $repo branch --merged $main } | complete).stdout | ansi strip | lines
        | each {|l| strip-branch-markers $l }
        | where {|l| $l | is-not-empty })
    if not ($branch in $merged) {
        print $"✗ ($branch) is not merged into ($main) — merge it first; wt-done refuses forever"
        exit 1
    }

    let rm: record = (do { ^git -C $repo worktree remove $path } | complete)
    if $rm.exit_code != 0 {
        print -e $"✗ worktree remove failed: ($rm.stderr | str trim)"
        exit 1
    }
    let bd: record = (do { ^git -C $repo branch -d $branch } | complete)
    if $bd.exit_code != 0 {
        print -e $"⚠ branch -d ($branch) failed: ($bd.stderr | str trim)"
        exit 1
    }
    print $"✓ worktree removed, branch ($branch) deleted — done is done"
}
