#!/opt/homebrew/bin/nu
# fleet-errors.nu — one-shot ERROR triage across the whole fleet's logs.
# READ-ONLY, the sibling of fleet-healthcheck: the battery says WHAT is
# down; this says WHAT the fleet has been complaining about and how fresh
# it is. Exit 1 when at least one error is fresher than --since.
# Honest limit: a silent stop (a log that just quits writing) has no error
# line to find — that is deploy liveness territory, not log triage.

# The type aliases (the owner's 22/11 law): the shapes read once, the
# signatures spell the name. LogScan rides lib/fleet-errors.nu (tested).
type LogTarget = record<name: string, path: string>

const LOGS: list<LogTarget> = [
    {name: "bot out", path: "/Users/lattenero/.zcode/bot-kotlin/logs/launchd.out.log"}
    {name: "bot err", path: "/Users/lattenero/.zcode/bot-kotlin/logs/launchd.err.log"}
    {name: "bot daemon", path: "/Users/lattenero/.zcode/bot-kotlin/logs/daemon.jsonl"}
    {name: "healer", path: "/Users/lattenero/.zcode/bot-kotlin/logs/healer.log"}
    {name: "beacon", path: "/Users/lattenero/.zcode/bot-kotlin/logs/beacon.log"}
    {name: "deploy brain", path: "/Users/lattenero/.zcode/bot-kotlin/logs/deploy-brain.log"}
    {name: "deploy daemon", path: "/Users/lattenero/.zcode/bot-kotlin/logs/deploy-daemon.log"}
    {name: "deploy fork", path: "/Users/lattenero/.zcode/bot-kotlin/logs/deploy-fork.log"}
    {name: "deploy whatsapp", path: "/Users/lattenero/.zcode/bot-kotlin/logs/deploy-whatsapp.log"}
    {name: "brain", path: "/Users/lattenero/Library/Logs/agent-brain.log"}
    {name: "brain sentinel", path: "/Users/lattenero/Library/Logs/brain-sentinel.log"}
    {name: "auth sentinel", path: "/Users/lattenero/Library/Logs/auth-sentinel.log"}
    {name: "colima watchdog", path: "/Users/lattenero/Library/Logs/colima-watchdog.log"}
    {name: "stack-up", path: "/Users/lattenero/Library/Logs/stack-up.log"}
]

# Every run appends here — the receipt survives the terminal that ran it.
const LOG_FILE: string = "/Users/lattenero/Library/Logs/fleet-errors.log"

# Nested script nu does NOT load config.nu — the owner's thin theme rides
# the script itself (measured 21/11).
$env.config.table.mode = "thin"

use /Users/lattenero/Projects/nushell-fp/mods/log.nu *
use /Users/lattenero/Projects/nushell-fp/mods/fmt.nu *
use lib/log-scan.nu *
use lib/fleet-errors.nu *

# One voice for stdout AND the run log (the fleet family contract) — the
# shared mod does the work.
def emit [line: string]: nothing -> nothing {
    emit-to $LOG_FILE $line
}

def scan-log [entry: LogTarget, tailN: int, cutoff: datetime]: nothing -> LogScan {
    let out: record = (do { ^tail -n $tailN $entry.path } | complete)
    if $out.exit_code != 0 {
        return {log: $entry.name, errors: 0, fresh: 0, last: "no file / unreadable"}
    }
    let all: list<string> = ($out.stdout | ansi strip | lines)
    # deploy logs carry older runs in the same file: only the CURRENT run
    # speaks (lib/log-scan.nu) — an older run's ✗ must not be presented as
    # the last error (measured 21/11: deploy-brain showed a stale ✗ after a
    # clean run).
    let lines: list<string> = (if ($entry.name | str starts-with "deploy") {
        current-run $all '==>|^\[deploy\]'
    } else {
        $all
    })
    # the error predicate, the stamp parse and the freshness rule ride
    # lib/fleet-errors.nu (tested); one `now` per log keeps the window honest.
    scan-lines $entry.name $lines $cutoff (date now)
}

def main [
    --since: duration = 60min  # the freshness window (fresh errors → exit 1)
    --tail: int = 400          # lines scanned per log
]: nothing -> nothing {
    let cutoff: datetime = ((date now) - $since)
    let rows: list<LogScan> = ($LOGS | each {|e| scan-log $e $tail $cutoff })
    let withErrs: list<LogScan> = ($rows | where {|r| $r.errors > 0})
    emit $"== fleet errors — last ($tail) lines per log, fresh = within ($since) =="
    if ($withErrs | is-empty) {
        emit "no errors found in any fleet log"
        exit 0
    }
    emit ($withErrs | select log errors fresh last | sort-by -r fresh errors | table -w 85)
    let freshN: int = ($rows | get fresh | math sum)
    emit $"fresh errors in the window: ($freshN)"
    if $freshN > 0 { exit 1 }
}
