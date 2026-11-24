# lib/zcode-deploy-all.nu — the pure core of zcode-deploy-all.nu: the POSIX
# quote, the per-leg bash body, the scheduling plan as data (pnpm solo tracks
# + one chained gradle track, with the totality guard) and the status-file
# parse. The script keeps the mkdir/rm/bash effects.
export type DeployLeg = record<name: string, label: string, script: string, args: list<string>, kind: string>
export type DeployWave = list<DeployLeg>
export type LegVerdict = record<leg: string, ok: bool, code: int, secs: int, log: string, tail: list<string>>
export type LegVerdicts = list<LegVerdict>

# POSIX single-quote so a path/arg can never split or interpolate in the sh.
export def sh-quote [s: string]: nothing -> string {
    "'" + ($s | str replace -a "'" "'\\''") + "'"
}

# One bash group per leg: the leg's stream goes to its log (raw) AND to this
# script's stdout (prefixed). `< /dev/null` is the SIGTTIN cure: a subshell is
# a background process group on the session TTY, and gradle's terminal probe
# (Jansi ioctl) would freeze the leg "Stopped" on a read (measured 15/11).
# NO trailing `&` — the caller owns the scheduling.
export def leg-body [leg: DeployLeg, logdir: path, nu_bin: string, log_file: string]: nothing -> string {
    let log: string = (($logdir | path join $"($leg.name).log") | into string)
    let status: string = (($logdir | path join $"($leg.name).status") | into string)
    let prefix: string = $"[($leg.name)] "
    let awk: string = '{printf "%s%s\n", p, $0; fflush()}'
    let args: string = ($leg.args | each {|a| sh-quote $a} | str join ' ')
    let parts: list<string> = [
        '('
        't0=$(date +%s);'
        (sh-quote $nu_bin)
        (sh-quote $leg.script)
        $args
        '> >('
        'tee -a' (sh-quote $log)
        '|'
        'awk' '-v' (sh-quote $"p=($prefix)") (sh-quote $awk)
        '|'
        'tee -a' (sh-quote $log_file)
        ')'
        '2>&1'
        '< /dev/null;'
        'code=$?; t1=$(date +%s);'
        'printf "%s %s\n" "$code" "$((t1-t0))" >' (sh-quote $status)
        ')'
    ]
    $parts | str join ' '
}

# The scheduling policy as data: the pnpm legs run each in their own
# background group; the gradle legs CHAIN inside ONE background group (the
# journal lock serialized them anyway — the chain removes the contention and
# the saturation timeouts without giving up the fork's parallelism).
export def wave-body [legs: DeployWave, logdir: path, nu_bin: string, log_file: string]: nothing -> string {
    # Totality: `kind` is data, so a typo'd kind would fall through both
    # tracks and the leg would never run — the plan says 4, the wave runs 3.
    let unknown: list<string> = ($legs | where {|l| $l.kind not-in ["pnpm" "gradle"]} | get name)
    if not ($unknown | is-empty) {
        error make {msg: $"unknown leg kind — not scheduled by any track: ($unknown | str join ', ')"}
    }
    let solo: list<string> = ($legs | where kind == "pnpm" | each {|leg| (leg-body $leg $logdir $nu_bin $log_file) + ' &' })
    let gradle: list<string> = ($legs | where kind == "gradle" | each {|leg| leg-body $leg $logdir $nu_bin $log_file })
    let parts: list<string> = ($solo
        | append (if ($gradle | is-empty) { [] } else { ['(' ] ++ $gradle ++ [') &'] }))
    $parts | flatten | str join (char nl)
}

# The status file's own format (code + secs): a named parse; anything
# malformed answers the never-finished sentinel (code -1, secs 0).
export def status-parse [text: string]: nothing -> record<code: int, secs: int> {
    let hit: list<record> = ($text | parse -r '^\s*(?<code>-?\d+)\s+(?<secs>\d+)\s*$')
    if ($hit | is-empty) { return {code: -1, secs: 0} }
    {code: ($hit.0.code | into int), secs: ($hit.0.secs | into int)}
}
