#!/opt/homebrew/bin/nu
# day.nu — the fleet day brief, ONE read-only shot: commits across the
# fleet repos, memories the brain learned, deploys run, fresh errors —
# everything the last N hours produced, one command from any terminal.
# Composes the family verbatim (deploy-status and fleet-errors speak their
# own sections; day adds the two sections only it owns: commits, memories).
# Every line goes to stdout AND ~/Library/Logs/day.log.

const LOG_FILE: string = "/Users/lattenero/Library/Logs/day.log"
const BRAIN: string = "/Users/lattenero/Projects/agent-brain/core/build/install/agent-brain/bin/agent-brain"
const SCRIPTS: string = "/Users/lattenero/Scripts"

$env.config.table.mode = "thin"

use /Users/lattenero/Projects/nushell-fp/mods/log.nu *

# One voice for stdout AND the run log — the shared mod does the work.
def emit [line: string]: nothing -> nothing {
    emit-to $LOG_FILE $line
}

def fleet-repos []: nothing -> list<string> {
    # same enumeration law as worktree-sweep: direct ~/Projects/* git repos,
    # plus the ~/Scripts hub itself — it carries fleet commits too.
    ls /Users/lattenero/Projects
    | where type == dir
    | get name
    | where {|d| ($d + "/.git") | path exists }
    | append $SCRIPTS
}

def commits-section [hours: int]: nothing -> nothing {
    let since: string = $"($hours) hours ago"
    emit $'== commits — last ($hours)h =='
    let rows: list<record> = (fleet-repos | each {|repo|
        let out: record = (do { git -C $repo log --since $since --oneline } | complete)
        if $out.exit_code != 0 { [] } else {
            let lines: list<string> = ($out.stdout | lines | where {|l| ($l | str trim) != "" })
            if ($lines | is-empty) { [] } else {
                {repo: ($repo | path basename), n: ($lines | length), last: ($lines | first | str substring 0..59)}
            }
        }
    } | flatten)
    if ($rows | is-empty) {
        emit "no commits in the window — the fleet is quiet"
    } else {
        emit ($rows | sort-by -r n | table)
        let total: int = ($rows | get n | math sum)
        emit $"total: ($total) commits across ($rows | length) repos"
    }
}

def memories-section [hours: int]: nothing -> nothing {
    emit $'== memories learned — last ($hours)h =='
    let cutoff: datetime = ((date now) - ($hours * 1hr))
    let out: record = (do { ^$BRAIN memory recent --k 40 } | complete)
    if $out.exit_code != 0 {
        emit "brain degraded: memory recent unavailable"
        return
    }
    let all: list<record> = ($out.stdout | from json
        | where {|m| ((try { $m.createdAt | into datetime } catch { null }) | default (0 | into datetime)) > $cutoff })
    let rows: list<record> = ($all | each {|m| {kind: $m.kind, learned: ($m.content | str substring 0..89)} }
        # newest first, and a BRIEF — cap the display, count everything.
        | first 10)
    if ($rows | is-empty) {
        emit "the brain learned nothing new in the window"
    } else {
        emit ($rows | table)
        emit $"total: ($all | length) memories in the window — showing the latest ($rows | length)"
    }
}

def main [--hours: int = 24  # the look-back window for every section
]: nothing -> nothing {
    let stamp: string = (date now | format date "%Y-%m-%d %H:%M")
    emit $"== fleet day brief — ($stamp), window ($hours)h =="

    commits-section $hours
    memories-section $hours

    emit "== deploys =="
    let ds: record = (do { nu $"($SCRIPTS)/deploy-status.nu" } | complete)
    emit ($ds.stdout | str trim -r)

    emit $'== fresh errors — window ($hours)h =='
    let since: string = $"($hours)hr"
    let fe: record = (do { nu $"($SCRIPTS)/fleet-errors.nu" --since $since } | complete)
    emit ($fe.stdout | str trim -r)
    emit $'fleet-errors exit: ($fe.exit_code) — 1 means fresh errors, 0 means quiet'
}
