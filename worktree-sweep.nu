#!/opt/homebrew/bin/nu
# worktree-sweep.nu — the audit-then-clean sweep of 17/11 and 18/11,
# scripted. READ-ONLY by default: it names every stale candidate and why.
# --clean removes only what passes the built-in gate — merged into the
# repo's main branch AND a clean working tree — via the git-native commands
# (worktree remove + branch -d), which refuse anything else by construction.
# --clean --remote also deletes the MERGED remote branches (bare branch
# names: the origin/ prefix form fails — measured 15/11).
# Every decision is emitted; the run appends to
# ~/Library/Logs/worktree-sweep.log. Scope: direct ~/Projects/* repos
# (the nested notes repos are intentionally out of this sweep).

const LOG_FILE: string = "/Users/lattenero/Library/Logs/worktree-sweep.log"

# Nested script nu does NOT load config.nu — the owner's thin theme rides
# the script itself (measured 21/11).
$env.config.table.mode = "thin"
const PROTECTED: list<string> = [master main damian develop]

# The type aliases (the owner's 22/11 law): the shapes read once, the
# signatures spell the name.
type SweepRow = record<repo: string, item: string, action: string, why: string>
type WtEntry = record<path: string, branch: string>
type VerdictRule = record<action: string, why: string, when: closure>

use /Users/lattenero/Projects/nushell-fp/mods/log.nu *

# One voice for stdout AND the run log — the shared mod does the work.
def emit [line: string]: nothing -> nothing {
    emit-to $LOG_FILE $line
}

def repos []: nothing -> list<string> {
    ls /Users/lattenero/Projects
    | where type == dir
    | get name
    | where {|d| ($d + "/.git") | path exists }
}

def main-branch [repo: string]: nothing -> string {
    for b in ["master" "main"] {
        if ((do { ^git -C $repo rev-parse --verify $b } | complete).exit_code == 0) { return $b }
    }
    ""
}

# merged local branch names, current marker stripped, protected excluded.
def merged-locals [repo: string, mb: string]: nothing -> list<string> {
    let out: record = (do { ^git -C $repo branch --merged $mb } | complete)
    if $out.exit_code != 0 { return [] }
    # git colors its output even piped on this machine — the ANSI escapes
    # made "master" invisible to PROTECTED and -d would have offered it
    # (measured 21/11); ansi strip first, always.
    $out.stdout
    | ansi strip
    | lines
    | each {|l| $l | str trim | str replace -r '^\*\s*' '' }
    | where {|b| not ($b in $PROTECTED) }
}

def branch-in-worktrees [repo: string]: nothing -> list<string> {
    let out: record = (do { ^git -C $repo worktree list --porcelain } | complete)
    if $out.exit_code != 0 { return [] }
    $out.stdout
    | split row "\n\n"
    | each {|b| $b | lines | where {|l| $l =~ '^branch ' } | get -o 0 }
    | compact
    | each {|l| $l | str replace 'branch refs/heads/' '' }
}

def audit [repo: string]: nothing -> list<SweepRow> {
    let mb: string = (main-branch $repo)
    if $mb == "" { return [{repo: ($repo | path basename), item: "-", action: "skip", why: "no master/main branch"}] }
    let wtOut: record = (do { ^git -C $repo worktree list --porcelain } | complete)
    if $wtOut.exit_code != 0 { return [{repo: ($repo | path basename), item: "-", action: "skip", why: "git worktree list failed"}] }
    let inWts: list<string> = (branch-in-worktrees $repo)
    let merged: list<string> = (merged-locals $repo $mb)
    # worktrees beyond the main one: candidate when the branch is merged
    # and the tree is clean (git refuses the rest even at --clean time).
    let wts: list<WtEntry> = ($wtOut.stdout
        | str trim
        | split row "\n\n"
        | skip 1
        | each {|b|
            let lines: list<string> = ($b | lines)
            {path: ($lines | where {|l| $l =~ '^worktree ' } | get 0 | str replace 'worktree ' ''),
             branch: (($lines | where {|l| $l =~ '^branch ' } | get -o 0 | default "") | str replace 'branch refs/heads/' '')}
        })
    let wtRows: list<SweepRow> = ($wts | each {|w|
        let dirty: bool = (((do { ^git -C $w.path status --porcelain } | complete).stdout | str trim) != "")
        # the sweep-verdict classifier as a predicate table (the mode-table
        # law): dirty convicts first, then not-merged, then the catch-all.
        let rules: list<VerdictRule> = [
            {action: "KEEP", why: "dirty working tree", when: {|d: bool| $d}}
            {action: "KEEP", why: $"not merged into ($mb)", when: {|d: bool| not ($w.branch in $merged)}}
            {action: "CLEAN-able", why: "merged + clean", when: {|d: bool| true}}
        ]
        let hit: VerdictRule = ($rules | where {|r| do $r.when $dirty } | first)
        {repo: ($repo | path basename), item: $"($w.branch) at ($w.path)", action: $hit.action, why: $hit.why}
    })
    # merged local branches not checked out anywhere and not the main line.
    let brRows: list<SweepRow> = ($merged
        | where {|b| not ($b in $inWts) }
        | each {|b| {repo: ($repo | path basename), item: $b, action: "BRANCH-able", why: $"merged into ($mb), no worktree"} })
    $wtRows ++ $brRows
}

def main [--clean, --remote]: nothing -> nothing {
    let stamp: string = (date now | format date "%Y-%m-%d %H:%M:%S")
    emit $"== worktree-sweep ($stamp) — clean=($clean) remote=($remote) =="
    let repos: list<string> = (repos)
    emit $"fleet repos: ($repos | length)"
    let rows: list<SweepRow> = ($repos | each {|r| audit $r } | flatten)
    let cleanable: list<SweepRow> = ($rows | where {|r| $r.action =~ 'able' })
    emit ($rows | where {|r| $r.action != "KEEP" } | table -w 85)
    let keeps: int = ($rows | where action == KEEP | length)
    emit $"keeps — not merged or dirty: ($keeps)"
    if ($cleanable | is-empty) {
        emit "nothing to sweep"
        exit 0
    }
    if not $clean {
        emit $"($cleanable | length) candidates — re-run with --clean to execute"
        exit 0
    }
    let uid: string = (^id -u | str trim)
    for r in $cleanable {
        if ($r.action =~ 'CLEAN') {
            let path: string = ($r.item | split row " at " | get 1)
            let wrem: record = (do { ^git worktree remove $path } | complete)
            emit $"worktree remove ($path): exit ($wrem.exit_code)"
            let br: string = ($r.item | split row " at " | get 0)
            let bd: record = (do { ^git -C /Users/lattenero/Projects/($r.repo) branch -d $br } | complete)
            emit $"branch -d ($br): exit ($bd.exit_code)"
        } else {
            let br: string = $r.item
            let bd: record = (do { ^git -C /Users/lattenero/Projects/($r.repo) branch -d $br } | complete)
            emit $"branch -d ($br): exit ($bd.exit_code)"
            if $remote {
                let name: string = ($br | str replace "origin/" "")
                let pd: record = (do { ^git -C /Users/lattenero/Projects/($r.repo) push origin --delete $name } | complete)
                emit $"push origin --delete ($name): exit ($pd.exit_code)"
            }
        }
    }
    emit "sweep complete"
}
