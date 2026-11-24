#!/opt/homebrew/bin/nu
# ram-clean.nu — the RAM relief routine, DEEPENED on the owner's 21/11 ask
# for a more intense, pattern-recognizing, maximum-recovery clean.
# Default: PLAN ONLY (measures, names every candidate, frees nothing).
# --clean executes, one decision per line, stdout AND the run log:
#   0. the top-10 memory citizens — the pattern surface, shown every run
#   1. idle Task-Island zcode-cli processes — cpu < 1%, never my own
#      ancestry, never my session's own helper descendants, and never an
#      island whose subtree still breathes (a parked session of ANOTHER
#      window waiting on a live build is itself idle while its child works)
#   2. ollama pattern: the brain's embedder (nomic-embed) STAYS, every
#      other loaded model is stopped (stop != delete; they reload on demand)
#   3. AppleSpell killed (macOS growth bug; respawns small on demand)
#   4. idle build daemons killed — Gradle AND Kotlin compile daemons
#      (both respawn on the next build; a BUILDING daemon breathes above
#      the idle threshold and is never touched; the kotlin ones are the
#      build-day accumulators behind the metaspace OOM)
#   5. the Logi Options+ family: reported with RSS totals and the web
#      receipts — only its crash reporter is auto-killed; replacing the
#      daemon is the owner's decision (measured ~1.0 GB across processes)
#   6. receipts pass (after --clean): every kill re-verified against a
#      fresh ps — dead / SURVIVED / respawned-on-demand, LoginItems'
#      respawn measured against its pre-kill size, ollama re-listed
# Every run appends to ~/Library/Logs/ram-clean.log.
# --trend is a READ-ONLY mode: the ledger's history as a time series (per
# family first→last, Δ, and upRuns — how many runs it only went UP), no
# snapshot written, exits before any plan or clean work.

const LOG_FILE: string = "/Users/lattenero/Library/Logs/ram-clean.log"
# The leak ledger: one JSONL snapshot per run (families + free + swap), so
# the NEXT run can compute the growth — a leak is memory that CREATES ITSELF
# between runs and never comes back. Pruned on every write to the last
# LEDGER_BOOTS boots — the file never grows unbounded.
const SNAP_FILE: string = "/Users/lattenero/Library/Logs/ram-snapshots.jsonl"
# How many boots the ledger keeps; older boots leave on the next write.
const LEDGER_BOOTS: int = 10
# The brain's embedder — the ONLY ollama model that stays loaded.
const KEEP_OLLAMA: string = "nomic-embed"
# ollama by ABSOLUTE path: this script runs under callers whose PATH is
# launchd-narrow (the bot daemon's throat spawns it; measured 23:18 the
# bare `ollama` died the drill right after the island kills — it resolves
# only in interactive shells where config.nu widens PATH).
const OLLAMA: string = "/opt/homebrew/bin/ollama"
# Swap left after a clean above which the honest line speaks: pages of
# SURVIVING processes decompress only on touch — the floor is reboot-only.
const SWAP_STALE_MB: int = 2048

# Every shape, the parsers, the family table, the ledger arithmetic and the
# receipt lines ride lib/ram-clean.nu (tested: tests/test_ram_clean.nu);
# IDLE_CPU (the idle threshold) rides it too. The script keeps every kill,
# read and write — the effects at the edge.
use /Users/lattenero/Scripts/nushell-fp/mods/log.nu *
use /Users/lattenero/Scripts/nushell-fp/mods/types.nu *
use ../lib/ram-clean.nu *
use ../lib/json-lines.nu *

# One voice for stdout AND the run log — the shared mod does the work.
def emit [line: string]: nothing -> nothing {
    emit-to $LOG_FILE $line
}

# memory_pressure's free percentage — the parse is the lib's (loud on a
# shape change); the call is the edge.
def free-pct []: nothing -> int {
    free-pct-of (memory_pressure | into string)
}

def swap-line []: nothing -> string {
    ^sysctl -n vm.swapusage | str trim
}

# The full ps snapshot as records (the builtin ps lacks pcpu and comm).
def snap []: nothing -> list<PsRow> {
    ps-rows (^ps -axo pid=,ppid=,pcpu=,comm= | into string)
}

# RSS snapshot in MB (ps rss is KB): the greedy parse is the lib's, tested
# against paths with spaces (measured 24/11: 27 names truncated once).
def rss-snap []: nothing -> list<RssRow> {
    rss-rows (^ps -axo rss=,pid=,pcpu=,comm= | into string)
}

# Write this run's snapshot to the JSONL ledger — ONE whole-file write that
# also prunes (lib pruned-ledger: only the last LEDGER_BOOTS boots survive).
def snapshot-write [rows: list<Snapshot>, fams: list<FamilySum>, boot: int, free: int, swapUsedMb: int]: nothing -> Snapshot {
    let rec: Snapshot = (snapshot-record $fams $boot $free $swapUsedMb (date now | format date "%Y-%m-%d %H:%M:%S"))
    let kept: list<Snapshot> = (pruned-ledger $rows $rec $LEDGER_BOOTS)
    (($kept | each {|r| $r | to json -r } | str join (char nl)) + (char nl)) | save --force --raw $SNAP_FILE
    $rec
}

# The ledger parsed ONCE at the boundary — every run reads the file a
# single time; the record filter is the shared lib's (a half-written line
# must never poison the ledger as a string row).
def ledger-rows []: nothing -> list<Snapshot> {
    if not ($SNAP_FILE | path exists) { return [] }
    ledger-parse (open --raw $SNAP_FILE)
}

# The leak detector's VOICE: the baselines arrive as Prior Options and
# eliminate ONCE at the top (lib leak-rows does the arithmetic) — below the
# guard every value is a Snapshot, never a mid-pipeline null probe.
def leak-report [
    now: list<FamilySum>, prev: Prior, bootSnap: Prior,
    leakRunMb: int, leakBootMb: int, swapUsedMb: int,
]: nothing -> nothing {
    if $prev.tag == "none" {
        emit "leak ledger: baseline captured — run again later and the growth per family appears here"
        emit $"swap used now: ($swapUsedMb) MB"
        return
    }
    let prevSnap: Snapshot = $prev.value
    let prevSwap: int = ($prevSnap.swapUsedMb? | default 0)
    let bootSwap: int = ($bootSnap | option-match {|s| $s.swapUsedMb? | default 0 } {|| $swapUsedMb })
    let rows: list<LeakRow> = (leak-rows $now $prev $bootSnap $leakRunMb $leakBootMb)
    emit $'== leak suspects — runΔ ≥ ($leakRunMb) MB · bootΔ ≥ ($leakBootMb) MB =='
    if ($rows | is-empty) {
        emit "no family grew at the leak thresholds — memory is stable"
    } else {
        emit ($rows | table)
        emit $"swap used: ($swapUsedMb) MB — runΔ ($swapUsedMb - $prevSwap) MB · since boot +($swapUsedMb - $bootSwap) MB"
    }
}

# My ancestor chain + ALL its descendants is lib protect-set (tested); the
# local root is the interpreter's pid, passed at the edge.

# The island scan's impure edge: one ps feed with args, parsed once, then
# the PURE partition (protect set + idle/breather verdicts) from the lib.
def islands [prot: list<int>]: nothing -> IslandScan {
    let rows: list<ArgsRow> = (^ps -axo pid=,ppid=,pcpu=,args= | into string
        | lines
        | where {|l| ($l | str trim) != "" }
        | parse -r '^\s*(?<pid>\d+)\s+(?<ppid>\d+)\s+(?<cpu>[\d.]+)\s+(?<args>.+)$'
        | each {|r|
            {pid: ($r.pid | into int), ppid: ($r.ppid | into int), cpu: ($r.cpu | into float), args: ($r.args | str trim)}
        })
    island-partition $rows $prot
}

# "total = 4096.00M used = 2434.00M free = ..." → the used MB (lib parse;
# the line arrives from the caller: ONE sysctl per phase, measured 24/11).

# THE execute shape, once: when the run is a --clean and there is anything
# to kill, signal the pids BEST-EFFORT and speak the receipt. It replaced
# five verbatim copies of `if $clean and (...) { kill ...; emit ...; $pids }
# else { [] }` — the sixth copy would have had to remember the guard on its
# own. Per-pid `attempt`, because pids are a SNAPSHOT: a process can exit
# between the scan and the kill, and `kill` raises "process didn't terminate
# successfully" on a stale pid — one dead crashpad used to abort the whole
# run before the receipts pass (measured 24/11, exit 1, no stderr). An
# already-gone pid is a named outcome, never a failure.
def kill-when [clean: bool, label: string, pids: list<int>]: nothing -> list<int> {
    if (not $clean) or ($pids | is-empty) { return [] }
    let tries: list<record<pid: int, ok: bool>> = ($pids | each {|p|
        {pid: $p, ok: ((attempt {|| kill $p }).tag == "ok")}
    })
    let signalled: list<int> = ($tries | where ok | get pid)
    let failed: list<int> = ($tries | where {|t| not $t.ok} | get pid)
    if not ($signalled | is-empty) {
        emit $"killed ($label): ($signalled | str join ', ')"
    }
    # A failed signal is TWO different facts — nu's kill error carries no
    # errno, so ask ps: absent = already gone (harmless), present = the
    # signal was refused (a root-owned process, measured 24/11: a Logi
    # crashpad runs as root and ESRCH/EPERM read the same to nu).
    if not ($failed | is-empty) {
        let probe: record = (^ps -p ($failed | str join ',') -o pid= | complete)
        let still: list<int> = ($probe.stdout | lines | where {|l| ($l | str trim) != "" } | each {|l| $l | str trim | into int })
        let gone: list<int> = ($failed | where {|p| not ($p in $still)})
        if not ($gone | is-empty) {
            emit $"($label): already gone — no signal needed: ($gone | str join ', ')"
        }
        if not ($still | is-empty) {
            emit $"($label): signal refused — still alive: ($still | str join ', ')"
        }
    }
    $pids
}

def main [
    --clean
    --trend                  # read-only: the ledger's history as a trend view, then exit
    --trend-runs: int = 10   # snapshots in the trend window
    --leak-run-mb: int = 30   # family growth since the LAST run that flags a leak
    --leak-boot-mb: int = 150 # family growth since the BOOT that flags a leak
]: nothing -> nothing {
    let stamp: string = (date now | format date "%Y-%m-%d %H:%M:%S")
    let ps: list<PsRow> = (snap)
    let prot: list<int> = (protect-set $ps $nu.pid)
    let rss: list<RssRow> = (rss-snap)
    let freeBefore: int = (free-pct)
    let swapBefore: string = (swap-line)
    let boot: int = (^sysctl -n kern.boottime | parse -r 'sec = (?<sec>\d+)' | get 0.sec | into int)
    let swapUsed: int = (swap-used-mb $swapBefore)
    emit $"== ram-clean ($stamp) — clean=($clean) trend=($trend) =="

    # -2. --trend: the ledger's history as a time series — READ-ONLY, no
    #     snapshot written, exits before any plan or clean work.
    if $trend {
        let snaps: list<Snapshot> = (ledger-rows | last $trend_runs)
        if ($snaps | length) < 2 {
            emit "trend: not enough ledger rows yet — run ram-clean a few times first"
            return
        }
        let firstS: Snapshot = ($snaps | first)
        let lastS: Snapshot = ($snaps | last)
        emit $"== trend — last ($snaps | length) runs · ($firstS.stamp) → ($lastS.stamp) =="
        emit $"free: ($firstS.free)% → ($lastS.free)% · swap: ($firstS.swapUsedMb) → ($lastS.swapUsedMb) MB — Δ ($lastS.swapUsedMb - $firstS.swapUsedMb) MB"
        emit (trend-rows $snaps | table)
        emit "upRuns = runs where the family grew vs the previous snapshot — climbers sit near the run count, noise hovers around half"
        return
    }

    # -1. the leak ledger: read ONCE, write ONCE (pruned), diff the SAME
    #     family feed — one ps truth for the snapshot and the leak report.
    let ledger: list<Snapshot> = (ledger-rows)
    let prev: Prior = (last-snapshot $ledger)
    let bootSnap: Prior = (boot-snapshot $ledger $boot)
    let fams: list<FamilySum> = (families $rss | first 60)
    snapshot-write $ledger $fams $boot $freeBefore $swapUsed
    leak-report $fams $prev $bootSnap $leak_run_mb $leak_boot_mb $swapUsed

    # 0. the pattern surface: who holds the memory right now.
    emit $"before: free ($freeBefore)% · swap ($swapBefore)"
    emit "== top 10 memory citizens (MB) =="
    emit ($rss | sort-by -r rssMb | first 10 | select name pid rssMb cpu | table)

    # 1. Task-Island zcode-cli processes — descendant-aware: an island dies
    #    only when nothing below it breathes either.
    let scan: IslandScan = (islands $prot)
    emit $"islands: ($scan.killable | length) idle zcode-cli candidates — pids ($scan.killable | get pid | str join ', ')"
    for h in $scan.held {
        emit $"island held: ($h.pid) — descendant ($h.breatherPid) breathes at ($h.breatherCpu)% — not killed"
    }
    let isleKills: list<int> = (kill-when $clean "idle islands" ($scan.killable | get pid))

    # 2. ollama pattern: the brain's embedder stays, the rest reload on demand.
    let ops: record = (do { run-external $OLLAMA ps } | complete)
    let loaded: list<string> = (loaded-models $ops.stdout)
    let droppable: list<string> = (droppable-models $loaded $KEEP_OLLAMA)
    emit $"ollama loaded: ($loaded | str join ', ') — keep ($KEEP_OLLAMA), drop: ($droppable | str join ', ')"
    let droppedModels: list<string> = (if $clean and (($droppable | length) > 0) {
        for m in $droppable {
            let stop: record = (do { run-external $OLLAMA stop $m } | complete)
            emit $"ollama stop ($m): exit ($stop.exit_code)"
        }
        $droppable
    } else { [] })

    # 3. AppleSpell growth bug.
    let spell: list<int> = ($ps | where name == "AppleSpell" | get pid)
    emit $"AppleSpell: ($spell | str join ', ')"
    let spellKills: list<int> = (kill-when $clean "AppleSpell — it respawns small on demand" $spell)

    # 4. idle build daemons — Gradle AND Kotlin compile daemons, matched by
    #    their daemon markers (the java family also holds LIVE infra —
    #    brain/whatsdigest/bot daemons idle between work and are never
    #    touched; markers keep the class safe). Both respawn on the next
    #    build; an ACTIVE build breathes above the threshold.
    let builds: list<CpuRow> = (^ps -axo pid=,pcpu=,args=
        | lines
        | where {|l| $l =~ 'GradleDaemon|KotlinCompileDaemon' }
        | each {|l| pid-cpu $l }
        | where {|r| $r.cpu < $IDLE_CPU })
    emit $"idle build daemons — gradle+kotlin: ($builds | length) — pids ($builds | get pid | str join ', ')"
    let buildKills: list<int> = (kill-when $clean "idle build daemons (gradle+kotlin)" ($builds | get pid))

    # 5. LoginItems — the macOS host of the login-item daemons (the Logi
    #    services live INSIDE it). Measured 21/11: 1163 MB at 13:15 → 1549 MB
    #    at 19:11 with 100% cpu — THE felt leak. A restart respawns it clean.
    let loginItems: list<int> = ($ps | where name == "LoginItems" | get pid)
    let liRss: int = (rss-of $rss "LoginItems")
    emit $"LoginItems — the login-item host where the Logi services live: ($liRss) MB"
    let loginKills: list<int> = (kill-when $clean "LoginItems — it respawns clean and the login-item daemons come back with it" $loginItems)

    # 6. the Logi Options+ family — report + only the crash reporter dies.
    # Membership is the family TABLE's decision (its `^login` row keeps the
    # macOS processes out — the 21/11 false positives that inflated the
    # family by >1 GB live there, once).
    let logi: table = (logi-rows $rss)
    if ($logi | is-empty) {
        emit "logi family: not running"
    } else {
        emit ($logi | sort-by -r rssMb | table)
        emit $"logi family total: ($logi | get rssMb | math sum) MB — the single biggest optional block on this 16 GB Mac"
        emit "hint (web receipts 21/11): the daemon is a ~500 MB Electron app; alternatives = BetterMouse (paid), Mouser (open-source, HID++), LinguaX (native ~10 MB); or downgrade to 1.44.415778 with auto-updates OFF"
    }
    # Only the crash reporter dies — hoisted out of the report branch so
    # the receipts pass below can see what was killed.
    let crashpads: list<int> = ($logi | where name == "logi_crashpad_handler" | get pid)
    let crashpadKills: list<int> = (kill-when $clean "logi_crashpad_handler — it respawns when a crash needs reporting" $crashpads)

    if $clean {
        sleep 2sec
        # The receipts pass: every kill re-verified against a fresh
        # external-ps snapshot (the builtin ps's pid column lies — the
        # process-liveness law; snap is the measured truth) — dead is a
        # receipt, SURVIVED is named, respawned-by-design is the new
        # state (LoginItems must come back SMALL).
        let ps2: list<PsRow> = (snap)
        for line in [(receipt-dead "islands" $isleKills $ps2) (receipt-dead "build daemons" $buildKills $ps2)] {
            if ($line != "") { emit $line }
        }
        for line in [(receipt-respawn "AppleSpell" $spellKills "AppleSpell" $ps2) (receipt-respawn "logi crashpad" $crashpadKills "logi_crashpad_handler" $ps2)] {
            if ($line != "") { emit $line }
        }
        if not ($loginKills | is-empty) {
            let liRss2: int = (rss-of (rss-snap) "LoginItems")
            emit (login-receipt $liRss $liRss2)
        }
        if not ($droppedModels | is-empty) {
            let ops2: record = (do { run-external $OLLAMA ps } | complete)
            let loaded2: list<string> = (loaded-models $ops2.stdout)
            let stillLoaded: list<string> = ($loaded2 | where {|m| $m in $droppedModels })
            if ($stillLoaded | is-empty) {
                emit $"ollama: ($droppedModels | str join ', ') → verified unloaded"
            } else {
                emit $"ollama: still loaded after stop: ($stillLoaded | str join ', ')"
            }
        }
        let freeAfter: int = (free-pct)
        let swapAfter: string = (swap-line)
        let swapUsedAfter: int = (swap-used-mb $swapAfter)
        emit $"after: free ($freeAfter)% · swap ($swapAfter)"
        emit $"freed: ($freeAfter - $freeBefore) points of free percentage · swap Δ ($swapUsedAfter - $swapUsed) MB"
        # The honest swap ceiling: killed processes release their swapped
        # pages (the Δ above), but pages of SURVIVING processes decompress
        # only on touch — the only full swap reset is a reboot (flushing
        # dynamic_pager needs SIP off and risks freezes — not sanctioned).
        if $swapUsedAfter > $SWAP_STALE_MB {
            emit $"swap: ($swapUsedAfter) MB remain — memory is clean, the swap floor is reboot-only"
        }
    } else {
        emit "plan only — re-run with --clean to execute"
    }
}
