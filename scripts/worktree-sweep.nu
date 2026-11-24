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
# (the nested notes repos are intentionally out of this sweep), PLUS the
# orphan-fixture section: test-sown git CLONES in ~/Projects/.worktrees
# (their .git is a DIRECTORY — a real worktree carries a .git FILE — with
# no origin; nothing registers them, so the repo audit is blind by
# design). --clean removes only those older than ORPHAN_MIN_AGE — a fresh
# fixture may belong to a live test run.

const LOG_FILE: string = "/Users/lattenero/Library/Logs/worktree-sweep.log"
# The agent worktree folder — where the orphan-fixture section hunts the
# test-sown git clones the repo audit can never see.
const WT_DIR: string = "/Users/lattenero/Projects/.worktrees"
# An orphan clone younger than this stays: a fixture seconds-to-minutes
# old may belong to a test run STILL alive; anything older is leftover.
const ORPHAN_MIN_AGE: duration = 1hr

# Nested script nu does NOT load config.nu — the owner's thin theme rides
# the script itself (measured 21/11).
$env.config.table.mode = "thin"
const PROTECTED: list<string> = [master main damian develop]

# The sweep shapes ride lib/worktree-sweep.nu (tested); the porcelain parse
# rides lib/worktree.nu.
use /Users/lattenero/Scripts/nushell-fp/mods/log.nu *
use ../lib/worktree.nu *
use ../lib/worktree-sweep.nu *

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
    # damian rides AFTER the defaults: the fork's main line IS damian
    # (the T3 owner-side observation — ZCode always read as "skip" because
    # only master/main were probed; PROTECTED already knew the name). The
    # choice itself lives in lib/worktree.nu (pick-branch-of, tested).
    let candidates: list<string> = ["master" "main" "damian"]
    let present: list<string> = ($candidates | where {|b|
        ((do { ^git -C $repo rev-parse --verify $b } | complete).exit_code == 0)
    })
    pick-branch-of $candidates $present
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
    porcelain-blocks $out.stdout | get branch | where {|b| $b | is-not-empty }
}

def audit [repo: string]: nothing -> list<SweepRow> {
    let mb: string = (main-branch $repo)
    if $mb == "" { return [{repo: ($repo | path basename), item: "-", action: "skip", why: "no master/main branch"}] }
    let wtOut: record = (do { ^git -C $repo worktree list --porcelain } | complete)
    if $wtOut.exit_code != 0 { return [{repo: ($repo | path basename), item: "-", action: "skip", why: "git worktree list failed"}] }
    let inWts: list<string> = (branch-in-worktrees $repo)
    let merged: list<string> = (merged-locals $repo $mb)
    # worktrees beyond the main one (lib/worktree.nu's linked-blocks):
    # candidate when the branch is merged and the tree is clean (git refuses
    # the rest even at --clean time). The verdict table rides the lib.
    let wts: list<PorcelainBlock> = (linked-blocks $wtOut.stdout)
    let wtRows: list<SweepRow> = ($wts | each {|w|
        let dirty: bool = (((do { ^git -C $w.path status --porcelain } | complete).stdout | str trim) != "")
        let v: record<action: string, why: string> = (wt-verdict $dirty ($w.branch in $merged) $mb)
        {repo: ($repo | path basename), item: $"($w.branch) at ($w.path)", action: $v.action, why: $v.why}
    })
    # merged local branches not checked out anywhere and not the main line.
    let brRows: list<SweepRow> = ($merged
        | where {|b| not ($b in $inWts) }
        | each {|b| {repo: ($repo | path basename), item: $b, action: "BRANCH-able", why: $"merged into ($mb), no worktree"} })
    $wtRows ++ $brRows
}

# Orphan fixtures in the agent worktree folder: test-sown git CLONES — the
# .git inside is a DIRECTORY (a real worktree carries a .git FILE pointing
# at its owning repo) and no origin claims them. Nothing registers them in
# any repo's worktree list, so the audit above is blind to them by design.
# Verdict as a predicate table (the mode-table law): real-worktree first,
# then origin-owned clone, then the age gate over the fixture class.
def orphan-audit []: nothing -> list<SweepRow> {
    if not ($WT_DIR | path exists) { return [] }
    ls $WT_DIR
    | where type == dir
    | each {|d|
        let dotgit: string = ($d.name + "/.git")
        let isClone: bool = (($dotgit | path exists) and (($dotgit | path type) == "dir"))
        let originLive: bool = ((do { ^git -C $d.name remote get-url origin } | complete).exit_code == 0)
        let ageH: int = (age-h $d.modified (date now))
        let v: record<action: string, why: string> = (orphan-verdict $isClone $originLive $ageH ($ORPHAN_MIN_AGE / 1hr | into int))
        {repo: "orphan", item: $d.name, action: $v.action, why: $"($v.why) — age ($ageH)h"}
    }
}

# One executor per action kind — the mode-table law again: rows pick the
# branch, only the winner runs (no else-if chain). The ORPHAN row carries
# the full path in item; the gate already vetted its age at audit time.
def sweep-exec [r: SweepRow, remote: bool]: nothing -> nothing {
    let branches: list<record<when: closure, run: closure>> = [
        {when: {|rr: SweepRow| $rr.action =~ 'ORPHAN'}
         run: {|| rm -rf $r.item; emit $"orphan fixture removed: ($r.item)" }}
        {when: {|rr: SweepRow| $rr.action =~ 'CLEAN'}
         run: {|| let parts: record<branch: string, path: string> = (item-parts $r.item)
                 let wrem: record = (do { ^git worktree remove $parts.path } | complete)
                 emit $"worktree remove ($parts.path): exit ($wrem.exit_code)"
                 let bd: record = (do { ^git -C /Users/lattenero/Projects/($r.repo) branch -d $parts.branch } | complete)
                 emit $"branch -d ($parts.branch): exit ($bd.exit_code)" }}
        {when: {|rr: SweepRow| true}
         run: {|| let bd: record = (do { ^git -C /Users/lattenero/Projects/($r.repo) branch -d $r.item } | complete)
                 emit $"branch -d ($r.item): exit ($bd.exit_code)"
                 if $remote {
                     let name: string = ($r.item | str replace "origin/" "")
                     let pd: record = (do { ^git -C /Users/lattenero/Projects/($r.repo) push origin --delete $name } | complete)
                     emit $"push origin --delete ($name): exit ($pd.exit_code)"
                 } }}
    ]
    ($branches | where {|row| do $row.when $r } | first | get run | do $in)
}

def main [--clean, --remote]: nothing -> nothing {
    let stamp: string = (date now | format date "%Y-%m-%d %H:%M:%S")
    emit $"== worktree-sweep ($stamp) — clean=($clean) remote=($remote) =="
    let repos: list<string> = (repos)
    emit $"fleet repos: ($repos | length)"
    let rows: list<SweepRow> = (($repos | each {|r| audit $r } | flatten) ++ (orphan-audit))
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
    for r in $cleanable {
        sweep-exec $r $remote
    }
    emit "sweep complete"
}
