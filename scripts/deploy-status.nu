#!/opt/homebrew/bin/nu
# deploy-status.nu — liveness of the fleet's deploy jobs. READ-ONLY.
# The law measured on 21/11: a log's mtime proves NOTHING during a build's
# silent phases; %CPU of the job's pid (two samples) is the only progress
# proof, and a job loaded+running at ~0% cpu is a STUCK suspect — exactly
# how the 23:56 fork deploy died with neither error line nor notification.
# Also reports how each job's LAST run ended: done / failed / unknown.
# Every line goes to stdout AND ~/Library/Logs/deploy-status.log.

const LOG_FILE: string = "/Users/lattenero/Library/Logs/deploy-status.log"

# The type aliases (the owner's 22/11 law): the shapes read once, the
# signatures spell the name.
type DeployJob = record<job: string, label: string, log: string>
type JobStatus = record<job: string, state: string, pid: int, written: string, marker: string, last: string>

# Nested script nu does NOT load config.nu — the owner's thin theme rides
# the script itself (measured 21/11).
$env.config.table.mode = "thin"
const JOBS: list<DeployJob> = [
    {job: "brain", label: "com.zcode.brain-deploy", log: "/Users/lattenero/.zcode/bot-kotlin/logs/deploy-brain.log"}
    {job: "bot", label: "com.zcode.bot-deploy", log: "/Users/lattenero/.zcode/bot-kotlin/logs/deploy-daemon.log"}
    {job: "whatsapp", label: "com.zcode.wd-deploy", log: "/Users/lattenero/.zcode/bot-kotlin/logs/deploy-whatsapp.log"}
    {job: "fork", label: "com.zcode.deploy-fork", log: "/Users/lattenero/.zcode/bot-kotlin/logs/deploy-fork.log"}
]

use /Users/lattenero/Scripts/nushell-fp/mods/log.nu *
use /Users/lattenero/Scripts/nushell-fp/mods/fmt.nu *
use ../lib/log-scan.nu *
use ../lib/deploy-status.nu *

# One voice for stdout AND the run log — the shared mod does the work.
def emit [line: string]: nothing -> nothing {
    emit-to $LOG_FILE $line
}

def cpu-of [pid: int]: nothing -> float {
    let out: record = (do { ^ps -p $pid -o %cpu= } | complete)
    if $out.exit_code != 0 { 0.0 } else { ($out.stdout | str trim | into float) }
}

def log-tail [log: string, n: int]: nothing -> list<string> {
    let out: record = (do { ^tail -n $n $log } | complete)
    if $out.exit_code != 0 { [] } else { $out.stdout | lines | where {|l| ($l | str trim) != "" } }
}

def scan [uid: string, j: DeployJob]: nothing -> JobStatus {
    let probe: record = (do { ^launchctl print $"gui/($uid)/($j.label)" } | complete)
    let probe_ok: bool = ($probe.exit_code == 0)
    let running: bool = ($probe_ok and ($probe.stdout | lines | any {|l| $l =~ "state = running"}))
    # the 3-way classifiers ride lib/deploy-status.nu (predicate tables,
    # tested); the script keeps the launchctl/ps/tail effects.
    mut state: string = (state-of $probe_ok $running)
    mut pid: int = 0
    if $running {
        $pid = (pid-of $probe.stdout)
        if $pid > 0 {
            let c1: float = (cpu-of $pid)
            sleep 2sec
            let c2: float = (cpu-of $pid)
            $state = (cpu-verdict $c1 $c2)
        }
    }
    let full: list<string> = (log-tail $j.log 60)
    # only the CURRENT run speaks: everything after the last build start —
    # an older run's ✗ must not convict a newer success (measured brain).
    let tail: list<string> = (current-run $full '==>')
    let last: string = (last-line $tail)
    let marker: string = (marker-of $tail)
    if ($j.log | path exists) {
        let age: duration = ((date now) - (ls $j.log | get 0.modified))
        {job: $j.job, state: $state, pid: $pid, written: $"($age) ago", marker: $marker, last: $last}
    } else {
        {job: $j.job, state: $state, pid: $pid, written: "no log file", marker: $marker, last: $last}
    }
}

def main []: nothing -> nothing {
    let uid: string = (^id -u | str trim)
    let stamp: string = (date now | format date "%Y-%m-%d %H:%M:%S")
    emit $"== deploy-status ($stamp) =="
    let rows: list<JobStatus> = ($JOBS | each {|j| scan $uid $j })
    emit ($rows | select job state pid written marker | table -w 85)
    for r in $rows {
        emit $"($r.job) last line: ($r.last | str substring 0..69)"
    }
    let stuck: int = ($rows | where {|r| $r.state =~ 'STUCK' } | length)
    emit $"stuck suspects: ($stuck)"
    if $stuck > 0 { exit 1 }
}
