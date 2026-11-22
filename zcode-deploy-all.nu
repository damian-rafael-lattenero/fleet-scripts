#!/Users/lattenero/.local/bin/nu-nightly
# zcode-deploy-all.nu — THE one command: a PARALLEL WAVE of the four legs
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
#   zcode-deploy-all --dry-run    # the wave plan; no leg runs (verification)
#   zcode-deploy-all              # the real wave (owner's call, from Ghostty)

const NU: string = "/Users/lattenero/.local/bin/nu-nightly"
const LOGDIR: string = "/tmp/deploy-all"
# kind = the RESOURCE the leg competes for (the scheduling policy is data,
# not flow — measured 23/11: 3 gradle builds + pnpm at once pushed load to
# 28 and the bot's 45s verification failed once). The pnpm track runs
# alone; the gradle track CHAINS its legs inside one subshell — the journal
# lock serialized them anyway, so the chain matches reality without the
# contention.
const LEGS: list<record<name: string, label: string, script: string, args: list<string>, kind: string>> = [
    {name: "fork",     label: "Fork ZCode (build → --quit swap → reopen)", script: "/Users/lattenero/Projects/ZCode/scripts/build-install.nu", args: ["--quit"], kind: "pnpm"}
    {name: "brain",    label: "Agent-brain (installDist → restart → /ready)", script: "/Users/lattenero/Projects/agent-brain/scripts/deploy-brain.nu", args: [], kind: "gradle"}
    {name: "bot",      label: "Bot Kotlin ZCode mirror (build → install → relaunch)", script: "/Users/lattenero/Projects/zcode-bot-kotlin/scripts/deploy-daemon.nu", args: [], kind: "gradle"}
    {name: "whatsapp", label: "Bot Kotlin WhatsApp (build → install → relaunch)", script: "/Users/lattenero/Projects/whatsdigest-kt/scripts/deploy-daemon.nu", args: [], kind: "gradle"}
]

# POSIX single-quote so a path/arg can never split or interpolate in the sh.
def sh-quote [s: string]: nothing -> string {
    "'" + ($s | str replace -a "'" "'\\''") + "'"
}

# One bash line per leg: the leg's stream goes to its log (raw) AND to this
# script's stdout (prefixed). `< /dev/null` is the SIGTTIN cure: a subshell is
# a background process group on the session TTY, and gradle's terminal probe
# (Jansi ioctl) would freeze the leg "Stopped" on a read (measured 15/11).
def leg-line [leg: record<name: string, label: string, script: string, args: list<string>>, logdir: path, nu_bin: string]: nothing -> string {
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
        ')'
        '2>&1'
        '< /dev/null;'
        'code=$?; t1=$(date +%s);'
        'printf "%s %s\n" "$code" "$((t1-t0))" >' (sh-quote $status)
        ') &'
    ]
    $parts | str join ' '
}

# The wave. Prints every leg live; returns one verdict per leg in plan order.
export def wave [legs: list<record<name: string, label: string, script: string, args: list<string>, kind: string>>, logdir: path, nu_bin: string]: nothing -> list<record<leg: string, ok: bool, code: int, secs: int, log: string, tail: list<string>>> {
    mkdir $logdir
    let stale: list<string> = ($legs | each {|leg| [
        (($logdir | path join $"($leg.name).status") | into string)
        (($logdir | path join $"($leg.name).log") | into string)
    ] } | flatten)
    ^/bin/rm -f ...$stale
    let body: string = (wave-body $legs $logdir $nu_bin)
    # `wait` is the rendezvous (no polling): it returns when every track is
    # done. `exit 0` keeps nu from raising on the last job's status — the
    # verdicts are the status files, not this shell's exit code.
    ^/bin/bash -c ($body + (char nl) + 'wait' + (char nl) + 'exit 0' + (char nl))
    $legs | each {|leg|
        let log: string = (($logdir | path join $"($leg.name).log") | into string)
        let status: string = (($logdir | path join $"($leg.name).status") | into string)
        let verdict: list<string> = (if ($status | path exists) { (open --raw $status | str trim | split row ' ') } else { [] })
        let code: int = (if ($verdict | is-empty) { -1 } else { $verdict.0 | into int })
        let secs: int = (if ($verdict | length) > 1 { $verdict.1 | into int } else { 0 })
        let tail: list<string> = (if ($log | path exists) { (open --raw $log | lines | last 10) } else { [] })
        {leg: $leg.name, ok: ($code == 0), code: $code, secs: $secs, log: $log, tail: $tail}
    }
}

def main [--dry-run]: nothing -> nothing {
    if $dry_run {
        print $"🧪 (ansi cyan)dry-run — the wave plan, nothing runs(ansi reset):"
        for leg in $LEGS {
            let args: string = ($leg.args | str join ' ')
            print $"  ($leg.kind | fill -a left -w 7)($leg.name | fill -a left -w 9)($leg.label)"
            print $"            ($NU) ($leg.script) ($args)"
        }
        print $"  tracks: pnpm runs ALONE — gradle chains inside one track, the journal lock serializes them"
        return
    }
    print $"🚀 (ansi cyan)the parallel wave — 4 legs, live output(ansi reset) \(fork + brain + bot + whatsapp; the cost is the MAX, not the sum\)"
    print $"   logs: ($LOGDIR)/<leg>.log — every line below is prefixed with its leg"
    let t0: datetime = (date now)
    let wave: list<record<leg: string, ok: bool, code: int, secs: int, log: string, tail: list<string>>> = (wave $LEGS $LOGDIR $NU)
    let total: string = ((date now) - $t0 | into string)
    print $"── wave finished in ($total) ──"
    let failed: list<record> = ($wave | where {|w| not $w.ok})
    for w in $wave {
        let verdict: string = (if $w.ok { "✅" } else { $"❌ exit ($w.code)" })
        print $"($verdict) ($w.leg | fill -a left -w 9)($w.secs)s — log: ($w.log)"
        if not $w.ok { $w.tail | each {|l| print $"    ($l)"} }
    }
    if not ($failed | is-empty) {
        error make {msg: $"🛑 the wave ended with ($failed | length) failed leg\(s\): ($failed | get leg | str join ', ') — logs in ($LOGDIR)"}
    }
    print "📄 Verify: /status (phone, channel UP), /brain (fork), the brain's health-check. ONE deploy per change."
}
