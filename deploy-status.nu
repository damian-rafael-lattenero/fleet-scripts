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
type StateRow = record<state: string, when: closure>
type MarkerRow = record<marker: string, when: closure>

# Nested script nu does NOT load config.nu — the owner's thin theme rides
# the script itself (measured 21/11).
$env.config.table.mode = "thin"
const JOBS: list<DeployJob> = [
    {job: "brain", label: "com.zcode.brain-deploy", log: "/Users/lattenero/.zcode/bot-kotlin/logs/deploy-brain.log"}
    {job: "bot", label: "com.zcode.bot-deploy", log: "/Users/lattenero/.zcode/bot-kotlin/logs/deploy-daemon.log"}
    {job: "whatsapp", label: "com.zcode.wd-deploy", log: "/Users/lattenero/.zcode/bot-kotlin/logs/deploy-whatsapp.log"}
    {job: "fork", label: "com.zcode.deploy-fork", log: "/Users/lattenero/.zcode/bot-kotlin/logs/deploy-fork.log"}
]

use /Users/lattenero/Projects/nushell-fp/mods/log.nu *
use /Users/lattenero/Projects/nushell-fp/mods/fmt.nu *

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
    let running: bool = (($probe.exit_code == 0) and ($probe.stdout | lines | any {|l| $l =~ "state = running"}))
    # the 3-way state classifier as a predicate table — precedence lives in
    # row order, the catch-all row LAST (the mode-table law; the branch
    # chain dies).
    let stateRows: list<StateRow> = [
        {state: "not loaded", when: {|p: record| $p.exit_code != 0}}
        {state: "RUNNING", when: {|p| $running}}
        {state: "idle", when: {|p| true}}
    ]
    mut state: string = ($stateRows | where {|r| do $r.when $probe } | first | get state)
    mut pid: int = 0
    if $running {
        let pidRows: list<string> = ($probe.stdout | lines | where {|l| ($l | str trim) =~ '^pid = \d+' })
        if ($pidRows | is-not-empty) {
            $pid = ($pidRows | get 0 | str trim | str replace -r 'pid = ' '' | into int)
            let c1: float = (cpu-of $pid)
            sleep 2sec
            let c2: float = (cpu-of $pid)
            let breathe: bool = (($c1 + $c2) > 5.0)
            $state = (if $breathe { $"RUNNING alive cpu ($c1)/($c2)%" } else { $"STUCK SUSPECT cpu ($c1)/($c2)%" })
        }
    }
    let full: list<string> = (log-tail $j.log 60)
    # only the CURRENT run speaks: everything after the last build start —
    # an older run's ✗ must not convict a newer success (measured brain).
    let starts: list<int> = ($full | enumerate | where {|it| $it.item =~ '==>' } | get index)
    let tail: list<string> = (if ($starts | is-empty) { $full } else { $full | skip ($starts | last) })
    # Hard-wrap unbreakable tokens (the HikariPool class line lives here
    # too) — the shared mod does the chunking.
    let last: string = (if ($tail | is-empty) { "no log" } else { hard-wrap ($tail | last) 35 })
    # the end-marker classifier as a predicate table — ✗ convicts first,
    # then done, then the honest unknown (precedence in row order).
    let markerRows: list<MarkerRow> = [
        {marker: "last run FAILED", when: {|ls: list<string>| $ls | any {|l| $l =~ '✗|BUILD FAILED' }}}
        {marker: "last run done", when: {|ls: list<string>| $ls | any {|l| $l =~ '\bdone\b' }}}
        {marker: "running or unknown end", when: {|ls| true}}
    ]
    let marker: string = ($markerRows | where {|r| do $r.when $tail } | first | get marker)
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
