#!/Users/lattenero/.local/bin/nu-nightly
# deploy-all.nu — THE one command: a PARALLEL WAVE of the four legs
# (fork build+swap, brain, bot, whatsapp), and EVERY line of every leg
# speaks LIVE, prefixed with its leg. The sequential version cost the SUM
# (~25 min; the fork alone is 15-20); the wave costs the MAX.
#
# Why parallel is safe (the couplings are transient BY DESIGN):
#   - artifacts: NONE — 4 repos, 4 builds, 4 LaunchAgents (the THREE gradle
#     builds use separate per-project daemons and contend briefly on the
#     machine-wide journal lock — measured 17/11; the fork build is
#     pnpm/turbo)
#   - runtime: the fork swap reopens the app while the bots reconnect on
#     their own (bot-healer + socket retry); a mid-restart brain makes
#     memory-recall degrade honestly (2s deadline, silence on down) — it
#     never breaks a deploy
#   - KNOWN TRADE (measured 23:12 wave): 3 gradle builds + pnpm at once
#     pushed load to 28 and the bot's 45s verification failed once — the
#     wave is faster but saturation-timeout prone; the staggered-gradle
#     variant is the proposed fix if the timeouts repeat
#
# LIVE OUTPUT (measured 17/11 — owner's ask): a nushell `job` runs with its
# stdout handle swapped, so anything a job prints is INVISIBLE until the job
# returns; capturing with `complete` makes it worse (nothing at all until the
# wave ends). So the wave is one /bin/bash whose four subshells each `tee`
# their leg into its log and pipe the same stream through `awk` with a
# `[leg] ` prefix — the bash's stdout IS this script's stdout, so the lines
# arrive as they happen, from Ghostty or from the phone. Still NO polling and
# NO sleeps: the shell's own `wait` is the only rendezvous, and each leg
# leaves its exit code + seconds in $LOGDIR/<leg>.status.
#
# The canonical scripts live in their repos; this file only ORCHESTRATES
# (zero duplicated logic); the wave accumulates EVERY failure before speaking.
#   1/4 fork:     ~/Projects/ZCode/scripts/build-install.nu --quit
#   2/4 brain:    ~/Projects/agent-brain/scripts/deploy-brain.nu
#   3/4 bot:      ~/Projects/zcode-bot-kotlin/scripts/deploy-daemon.nu
#   4/4 whatsapp: ~/Projects/whatsdigest-kt/scripts/deploy-daemon.nu
#
# Golden rule: ONE deploy per change — every extra run is another build and
# another restart. The fork leg's --quit closes ZCode: run this from Ghostty
# (or the phone), never from inside the app's own session.
# Final verification: /status from the phone (channel UP), /brain from the
# fork, the brain's 7-layer health-check.
#
# Usage:
#   fleet deploy-all --dry-run    # the wave plan; no leg runs (verification)
#   fleet deploy-all              # the real wave (owner's call, from Ghostty)

const NU: string = "/Users/lattenero/.local/bin/nu-nightly"
const LOGDIR: string = "/tmp/deploy-all"
const LOG_FILE: string = "/Users/lattenero/Library/Logs/deploy-all.log"
use /Users/lattenero/Scripts/nushell-fp/mods/log.nu *

# One voice for stdout AND the run log — the wave's own receipt must survive
# the terminal that launched it (the fleet family's contract).
def emit [line: string]: nothing -> nothing {
    emit-to $LOG_FILE $line
}

# The shapes, the quote, the leg body, the wave plan and the status parse
# ride lib/deploy-all.nu (tested). The union alias ("pnpm" | "gradle")
# does NOT parse yet (measured) — the LEGS rows carry the kind discipline.
use ../lib/deploy-all.nu *
# kind = the RESOURCE the leg competes for (the scheduling policy is data,
# not flow — measured 23/11: 3 gradle builds + pnpm at once pushed load to
# 28 and the bot's 45s verification failed once). The pnpm track runs
# alone; the gradle track CHAINS its legs inside one subshell — the journal
# lock serialized them anyway, so the chain matches reality without the
# contention.
const LEGS: list<DeployLeg> = [
    {name: "fork",     label: "Fork ZCode (build → --quit swap → reopen)", script: "/Users/lattenero/Projects/ZCode/scripts/build-install.nu", args: ["--quit"], kind: "pnpm"}
    {name: "brain",    label: "Agent-brain (installDist → restart → /ready)", script: "/Users/lattenero/Projects/agent-brain/scripts/deploy-brain.nu", args: [], kind: "gradle"}
    {name: "bot",      label: "Bot Kotlin ZCode mirror (build → install → relaunch)", script: "/Users/lattenero/Projects/zcode-bot-kotlin/scripts/deploy-daemon.nu", args: [], kind: "gradle"}
    {name: "whatsapp", label: "Bot Kotlin WhatsApp (build → install → relaunch)", script: "/Users/lattenero/Projects/whatsdigest-kt/scripts/deploy-daemon.nu", args: [], kind: "gradle"}
]

# The status file as a typed verdict — the format is OURS, so one named
# parse (lib/status-parse); a missing or malformed file means the leg never
# finished (code -1, the same sentinel the caller already speaks).
def read-status [path: string]: nothing -> record<code: int, secs: int> {
    if not ($path | path exists) { return {code: -1, secs: 0} }
    status-parse (open --raw $path)
}

# The wave. Prints every leg live; returns one verdict per leg in plan order.
export def wave [legs: DeployWave, logdir: path, nu_bin: string]: nothing -> list<LegVerdict> {
    mkdir $logdir
    let stale: list<string> = ($legs | each {|leg| [
        (($logdir | path join $"($leg.name).status") | into string)
        (($logdir | path join $"($leg.name).log") | into string)
    ] } | flatten)
    ^/bin/rm -f ...$stale
    let body: string = (wave-body $legs $logdir $nu_bin $LOG_FILE)
    # `wait` is the rendezvous (no polling): it returns when every track is
    # done. `exit 0` keeps nu from raising on the last job's status — the
    # verdicts are the status files, not this shell's exit code.
    ^/bin/bash -c ($body + (char nl) + 'wait' + (char nl) + 'exit 0' + (char nl))
    $legs | each {|leg|
        let log: string = (($logdir | path join $"($leg.name).log") | into string)
        let v: record<code: int, secs: int> = (read-status (($logdir | path join $"($leg.name).status") | into string))
        let tail: list<string> = (if ($log | path exists) { (open --raw $log | lines | last 10) } else { [] })
        {leg: $leg.name, ok: ($v.code == 0), code: $v.code, secs: $v.secs, log: $log, tail: $tail}
    }
}

def main [--dry-run]: nothing -> nothing {
    if $dry_run {
        emit $"🧪 dry-run — the wave plan, nothing runs:"
        for leg in $LEGS {
            let args: string = ($leg.args | str join ' ')
            emit $"  ($leg.kind | fill -a left -w 7)($leg.name | fill -a left -w 9)($leg.label)"
            emit $"            ($NU) ($leg.script) ($args)"
        }
        emit $"  tracks: pnpm runs ALONE — gradle chains inside one track, the journal lock serializes them"
        return
    }
    emit $"🚀 the parallel wave — 4 legs, live output \(fork + brain + bot + whatsapp; the cost is the MAX, not the sum\)"
    emit $"   logs: ($LOGDIR)/<leg>.log — every line below is prefixed with its leg; the run log is ($LOG_FILE)"
    let t0: datetime = (date now)
    let wave: LegVerdicts = (wave $LEGS $LOGDIR $NU)
    let total: string = ((date now) - $t0 | into string)
    emit $"── wave finished in ($total) ──"
    let failed: list<LegVerdict> = ($wave | where {|w| not $w.ok})
    for w in $wave {
        let verdict: string = (if $w.ok { "✅" } else { $"❌ exit ($w.code)" })
        emit $"($verdict) ($w.leg | fill -a left -w 9)($w.secs)s — log: ($w.log)"
        if not $w.ok { $w.tail | each {|l| emit $"    ($l)"} }
    }
    if not ($failed | is-empty) {
        error make {msg: $"🛑 the wave ended with ($failed | length) failed leg\(s\): ($failed | get leg | str join ', ') — logs in ($LOGDIR)"}
    }
    emit "📄 Verify: /status (phone, channel UP), /brain (fork), the brain's health-check. ONE deploy per change."
}
