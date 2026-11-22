#!/opt/homebrew/bin/nu
# wt.nu — the isolation law at typing speed: one word creates the worktree.
#
#   wt                      lists every worktree across the fleet repos
#   wt <slug>               creates ~/Projects/.worktrees/<repo>-<slug> on
#                           branch agent/<slug>, based on the repo's main
#                           branch (master or main, probed in that order)
#   wt <slug> --repo name   targets a repo you are NOT inside (else the git
#                           repo of the current directory)
#
# The convention is the isolation law's own (agent-worktrees-isolation):
# .worktrees/ holds every checkout, agent/<slug> names every branch, and
# `wt-done <slug>` is the audit-then-clean mirror (merged + clean or it
# refuses). Read-only when listing; the only mutation is the worktree add.

# Every direct ~/Projects/* git repo (the day.nu enumeration law) plus the
# ~/Scripts hub itself.
def fleet-repos []: nothing -> list<string> {
    ls /Users/lattenero/Projects
    | where type == dir
    | get name
    | where {|d| ($d + "/.git") | path exists }
    | append "/Users/lattenero/Scripts"
}

# The repo's main line: master, else main, else "" (worktree-sweep's law).
def main-branch [repo: string]: nothing -> string {
    for b in ["master" "main"] {
        if ((do { ^git -C $repo rev-parse --verify $b } | complete).exit_code == 0) { return $b }
    }
    ""
}

def list-all []: nothing -> nothing {
    for repo in (fleet-repos) {
        let out: record = (do { ^git -C $repo worktree list --porcelain } | complete)
        if $out.exit_code != 0 { continue }
        let rows: list<string> = ($out.stdout
            | str trim
            | split row "\n\n"
            | skip 1
            | each {|block|
                let lines: list<string> = ($block | lines)
                let path: string = ($lines | where {|l| $l =~ '^worktree ' } | get -o 0 | default "" | str replace 'worktree ' '')
                let branch: string = (($lines | where {|l| $l =~ '^branch ' } | get -o 0 | default "") | str replace 'branch refs/heads/' '')
                $"  ($branch) ← ($path)"
            })
        if not ($rows | is-empty) {
            print $"($repo | path basename):"
            $rows | each {|r| print $r }
        }
    }
}

def create [slug: string, repo_dir: string]: nothing -> nothing {
    let name: string = ($repo_dir | path basename)
    let path: string = ("/Users/lattenero/Projects/.worktrees" | path join $"($name)-($slug)")
    if ($path | path exists) {
        print $"worktree already exists: ($path) — cd there and work"
        return
    }
    let base: string = (main-branch $repo_dir)
    if ($base | is-empty) { print $"✗ ($repo_dir) has no master/main to base on"; exit 1 }
    let ref: string = $"agent/($slug)"
    let existing: bool = ((do { ^git -C $repo_dir rev-parse --verify $ref } | complete).exit_code == 0)
    let args: list<string> = (if $existing {
        ["worktree" "add" $path $ref]
    } else {
        ["worktree" "add" "-b" $ref $path $base]
    })
    let out: record = (do { ^git -C $repo_dir ...$args } | complete)
    if $out.exit_code != 0 {
        print -e $"✗ worktree add failed: ($out.stderr | str trim | str substring 0..200)"
        exit 1
    }
    print $"✓ ($path) on agent/($slug) (base ($base)) — cd there and work"
}

def main [
    slug?: string      # create the worktree for this slug
    --repo: string     # repo NAME under ~/Projects (default: cwd's repo)
]: nothing -> nothing {
    if ($slug | default "" | is-empty) {
        list-all
        return
    }
    let repo_dir: string = (if ($repo | default "" | is-empty) {
        let top: record = (do { ^git rev-parse --show-toplevel } | complete)
        if $top.exit_code != 0 {
            print -e "✗ not inside a git repo — pass --repo <name>"
            exit 1
        }
        ($top.stdout | str trim)
    } else {
        # the hub lives at ~/Scripts, the rest at ~/Projects/<name>
        let by_projects: string = ("/Users/lattenero/Projects" | path join $repo)
        let dir: string = (if ($by_projects | path exists) { $by_projects } else { "/Users/lattenero/Scripts" })
        if not ($dir | path exists) { print -e $"✗ no such repo: ($by_projects)"; exit 1 }
        $dir
    })
    create $slug $repo_dir
}
