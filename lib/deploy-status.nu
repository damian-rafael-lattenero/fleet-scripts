# lib/deploy-status.nu — the pure core of deploy-status.nu: the three state
# classifiers as predicate tables (probe state, cpu verdict, end marker) plus
# the pid and last-line projections. The script keeps the launchctl/ps/tail
# effects.
use /Users/lattenero/Scripts/nushell-fp/mods/fmt.nu *

# not loaded wins, then RUNNING, then the honest idle catch-all.
export def state-of [probe_ok: bool, running: bool]: nothing -> string {
    let rows: list<record<when: bool, state: string>> = [
        {when: (not $probe_ok), state: "not loaded"}
        {when: $running, state: "RUNNING"}
        {when: true, state: "idle"}
    ]
    $rows | where when | first | get state
}

# The launchd print's pid line; 0 when absent.
export def pid-of [stdout: string]: nothing -> int {
    let rows: list<string> = ($stdout | lines | where {|l| ($l | str trim) =~ '^pid = \d+' })
    if ($rows | is-empty) { 0 } else { ($rows | get 0 | str trim | str replace -r 'pid = ' '' | into int) }
}

# Two cpu samples: a breathing job is alive, ~0% twice is the STUCK suspect
# (the 23:56 fork deploy's death shape).
export def cpu-verdict [c1: float, c2: float]: nothing -> string {
    if (($c1 + $c2) > 5.0) {
        $"RUNNING alive cpu ($c1)/($c2)%"
    } else {
        $"STUCK SUSPECT cpu ($c1)/($c2)%"
    }
}

# ✗ convicts first, then done, then the honest unknown — row order is the law.
export def marker-of [tail: list<string>]: nothing -> string {
    let rows: list<record<when: bool, marker: string>> = [
        {when: ($tail | any {|l| $l =~ '✗|BUILD FAILED'}), marker: "last run FAILED"}
        {when: ($tail | any {|l| $l =~ '\bdone\b'}), marker: "last run done"}
        {when: true, marker: "running or unknown end"}
    ]
    $rows | where when | first | get marker
}

# The LAST line of the current run, hard-wrapped so a stack-trace token never
# blows the table width.
export def last-line [tail: list<string>]: nothing -> string {
    if ($tail | is-empty) { "no log" } else { hard-wrap ($tail | last) 35 }
}
