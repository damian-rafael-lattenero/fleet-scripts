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
# cpu percent under which a process counts as idle. A live turn or an
# active build breathes well above this; abandoned things sit at 0.
const IDLE_CPU: float = 1.0
# Swap left after a clean above which the honest line speaks: pages of
# SURVIVING processes decompress only on touch — the floor is reboot-only.
const SWAP_STALE_MB: int = 2048

# The type aliases (the owner's 22/11 law): every shape reads once and the
# signatures spell the name. The nullable family is oneof<string, nothing> —
# a bare null literal against a plain `string` field fails the parse
# (measured 22/11), `nothing` is the null arm that works.
type PsRow = record<pid: int, ppid: int, cpu: float, name: string>
type CpuRow = record<pid: int, cpu: float>
# An args-bearing process row — the feed the island scan matches candidates
# on and walks descendants over (one ps feed for both jobs).
type ArgsRow = record<pid: int, ppid: int, cpu: float, args: string>
# The island scan's verdict: killable islands (whole subtree idle), and
# the ones HELD BACK because a descendant breathes — the breather named,
# the why as a receipt.
type IslandScan = record<killable: list<CpuRow>, held: list<record<pid: int, breatherPid: int, breatherCpu: float>>>
type RssRow = record<rssMb: int, pid: int, cpu: float, name: string>
type FamilyRule = record<pattern: string, family: oneof<string, nothing>>
type FamilySum = record<family: string, rssMb: int, n: int>
type LeakRow = record<family: string, nowMb: int, runDelta: int, bootDelta: int>
# One family's trajectory across the trend window: first/last/Δ in the
# window, plus the persistence count — how many consecutive-step runs it
# only went UP (climbers sit near the run count, noise hovers half).
type TrendRow = record<family: string, firstMb: int, lastMb: int, deltaMb: int, upRuns: int, seenRuns: int>
type Snapshot = record<stamp: string, boot: int, free: int, swapUsedMb: int, procs: list<FamilySum>>
# A prior-run lookup from the ledger as the nushell-fp Option shape (union
# aliases don't parse, measured — the kind lives in the tag row):
# {tag: "some", value: Snapshot} | {tag: "none", value: null}.
type Prior = record<tag: string, value: any>

use /Users/lattenero/Projects/nushell-fp/mods/log.nu *
use /Users/lattenero/Projects/nushell-fp/mods/types.nu *

# One voice for stdout AND the run log — the shared mod does the work.
def emit [line: string]: nothing -> nothing {
    emit-to $LOG_FILE $line
}

# "System-wide memory free percentage: 64%" → 64. A shape change of the
# macOS output is a LOUD error, never a wrong number.
def free-pct []: nothing -> int {
    let hits: list<string> = (memory_pressure | lines | where {|l| $l =~ "memory free percentage"})
    if ($hits | is-empty) {
        error make {msg: "memory_pressure output changed — no 'memory free percentage' line; the parse boundary broke"}
    }
    let line: string = ($hits | last)
    ($line | split row ":" | get 1 | str trim | str replace "%" "" | into int)
}

def swap-line []: nothing -> string {
    ^sysctl -n vm.swapusage | str trim
}

def pid-cpu [line: string]: nothing -> CpuRow {
    let t: string = ($line | str trim)
    let parts: list<string> = ($t | split row -r '\s+')
    {pid: ($parts | get 0 | into int), cpu: ($parts | get 1 | into float)}
}

# An args-bearing ps line (pid ppid cpu + the full command) as one row.
def args-row [line: string]: nothing -> ArgsRow {
    let parts: list<string> = (($line | str trim) | split row -r '\s+')
    {
        pid: ($parts | get 0 | into int)
        ppid: ($parts | get 1 | into int)
        cpu: ($parts | get 2 | into float)
        args: ($parts | skip 3 | str join ' ')
    }
}

# The full ps snapshot as records (the builtin ps lacks pcpu and comm).
def snap []: nothing -> list<PsRow> {
    ^ps -axo pid=,ppid=,pcpu=,comm=
    | lines
    | where {|l| ($l | str trim) != "" }
    | each {|l|
        let t: string = ($l | str trim)
        let parts: list<string> = ($t | split row -r '\s+')
        {pid: ($parts | get 0 | into int), ppid: ($parts | get 1 | into int), cpu: ($parts | get 2 | into float), name: ($parts | get 3 | path basename)}
    }
}

# RSS-aware snapshot: ps rss is KB; the owner reads MB.
def rss-snap []: nothing -> list<RssRow> {
    ^ps -axo rss=,pid=,pcpu=,comm=
    | lines
    | where {|l| ($l | str trim) != "" }
    | each {|l|
        let parts: list<string> = (($l | str trim) | split row -r '\s+')
        {rssMb: (($parts | get 0 | into int) / 1024 | math round), pid: ($parts | get 1 | into int), cpu: ($parts | get 2 | into float), name: ($parts | get 3 | path basename)}
    }
}

# Family grouping: an Electron app is 20+ helper processes; the leaks show
# per FAMILY, not per pid. The mapping is DATA — a priority-ordered
# predicate table (the anti-patterns law: chains die, precedence lives in
# row order). The login row sits FIRST so macOS system processes
# (LoginItems, loginwindow, logind) pass through ungrouped before the logi
# row can claim them — rust regex has no lookahead, row precedence does the
# job. family: null = pass through with the raw name.
def family-table []: nothing -> list<FamilyRule> {
    [
        {pattern: '^login', family: null}
        {pattern: '^zcode', family: "zcode-family"}
        {pattern: '^logi', family: "logi-family"}
        {pattern: '^google', family: "chrome-family"}
        {pattern: 'llama-server', family: "ollama-runners"}
        {pattern: '', family: null}
    ]
}

def family-of [name: string]: nothing -> string {
    let low: string = ($name | str lowercase)
    let hit: FamilyRule = (family-table | where {|row| $low =~ $row.pattern } | first)
    ($hit.family | default $name)
}

# The families aggregated (sum RSS + process count), the biggest first.
def families []: nothing -> list<FamilySum> {
    rss-snap
    | insert family {|r| family-of $r.name }
    | group-by family
    | items {|k, v| {family: $k, rssMb: ($v | get rssMb | math sum), n: ($v | length)} }
    | sort-by -r rssMb
}

# Write this run's snapshot to the JSONL ledger — ONE whole-file write that
# also prunes: only the last LEDGER_BOOTS boots survive, so the boot
# baseline is never evicted and the file never grows unbounded. The family
# rows arrive as input: the SAME feed the leak diff reads, one ps truth.
def snapshot-write [rows: list<Snapshot>, fams: list<FamilySum>, boot: int, free: int, swapUsedMb: int]: nothing -> Snapshot {
    let rec: Snapshot = {
        stamp: (date now | format date "%Y-%m-%d %H:%M:%S")
        boot: $boot
        free: $free
        swapUsedMb: $swapUsedMb
        procs: $fams
    }
    let boots: list<int> = ($rows | get boot | uniq | last $LEDGER_BOOTS)
    let kept: list<Snapshot> = ($rows | where {|r| $r.boot in $boots } | append $rec)
    (($kept | each {|r| $r | to json -r } | str join (char nl)) + (char nl)) | save --force --raw $SNAP_FILE
    $rec
}

# The ledger parsed ONCE at the boundary — every run reads the file a
# single time; corrupt lines drop, the body never re-reads the disk.
def ledger-rows []: nothing -> list<Snapshot> {
    if not ($SNAP_FILE | path exists) { return [] }
    open --raw $SNAP_FILE
    | lines
    | where {|l| ($l | str trim) != "" }
    | each {|l| try { $l | from json } catch { null } }
    | compact
}

# The last snapshot in the ledger — none when this is the first run.
def last-snapshot [rows: list<Snapshot>]: nothing -> Prior {
    if ($rows | is-empty) { none } else { some ($rows | last) }
}

# The first snapshot of the CURRENT boot — the since-boot growth baseline.
def boot-snapshot [rows: list<Snapshot>, boot: int]: nothing -> Prior {
    let sameBoot: list<Snapshot> = ($rows | where boot == $boot)
    if ($sameBoot | is-empty) { none } else { some ($sameBoot | first) }
}

# The per-family RSS lookup of one snapshot — 0 when the family is absent
# (killed by the previous clean, or born after it).
def fam-rss [snap: Snapshot, family: string]: nothing -> int {
    let hit: list<FamilySum> = ($snap.procs | where {|p| $p.family == $family })
    if ($hit | is-empty) { 0 } else { $hit | first | get rssMb }
}

# The trend window as family trajectories (the pure core of --trend): the
# series of rssMb across the window's snapshots, absent-from-a-snapshot
# reads 0 (the fam-rss convention), sorted by Δ — the climbers first, the
# big fallers (a clean that worked) visible at the bottom.
def trend-rows [snaps: list<Snapshot>]: nothing -> list<TrendRow> {
    let fams: list<string> = ($snaps | get procs | flatten | get family | uniq)
    $fams
    | each {|f|
        let series: list<int> = ($snaps | each {|s| fam-rss $s $f })
        {
            family: $f
            firstMb: ($series | first)
            lastMb: ($series | last)
            deltaMb: (($series | last) - ($series | first))
            upRuns: ($series | window 2 | where {|w| ($w | get 1) > ($w | get 0) } | length)
            seenRuns: ($series | where {|v| $v > 0 } | length)
        }
    }
    | sort-by -r deltaMb
    | first 12
}

# The leak detector: growth since the last run AND since the boot, per
# family, flagged at the thresholds. The baselines arrive as Prior Options
# and eliminate ONCE at the top — below the guard every value is a
# Snapshot, never a mid-pipeline null probe.
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
    let rows: list<LeakRow> = ($now
        | each {|f|
            let before: int = (fam-rss $prevSnap $f.family)
            let atBoot: int = ($bootSnap | option-match {|s| fam-rss $s $f.family } {|| 0 })
            {
                family: $f.family
                nowMb: $f.rssMb
                runDelta: ($f.rssMb - $before)
                bootDelta: ($f.rssMb - $atBoot)
            }
        }
        | where {|r| ($r.runDelta >= $leakRunMb) or ($r.bootDelta >= $leakBootMb) }
        | sort-by -r bootDelta)
    emit $'== leak suspects — runΔ ≥ ($leakRunMb) MB · bootΔ ≥ ($leakBootMb) MB =='
    if ($rows | is-empty) {
        emit "no family grew at the leak thresholds — memory is stable"
    } else {
        emit ($rows | table)
        emit $"swap used: ($swapUsedMb) MB — runΔ ($swapUsedMb - $prevSwap) MB · since boot +($swapUsedMb - $bootSwap) MB"
    }
}

# My ancestor chain + ALL its descendants (my session's own MCP helpers).
# Siblings of my ancestors (other Task Islands) are deliberately NOT here.
def protect-set [ps: list<PsRow>]: nothing -> list<int> {
    mut chain: list<int> = [$nu.pid]
    mut cur: int = $nu.pid
    for _ in 1..15 {
        let row: list<PsRow> = ($ps | where pid == $cur)
        if ($row | is-empty) { break }
        let parent: int = ($row | get 0.ppid)
        if $parent <= 1 { break }
        $chain = ($chain | append $parent)
        $cur = $parent
    }
    mut prot: list<int> = $chain
    for _ in 1..4 {
        let base: list<int> = $prot
        let kids: list<int> = ($ps | where ppid in $base | get pid)
        let fresh: list<int> = ($kids | where {|k| not ($k in $base) })
        if ($fresh | is-empty) { break }
        $prot = ($prot | append $fresh)
    }
    $prot
}

# The descendants of one pid — the same fixpoint expansion protect-set
# runs over MY subtree, pointed at a CANDIDATE: everything below it.
def descendants [rows: list<ArgsRow>, root: int]: nothing -> list<int> {
    mut sub: list<int> = [$root]
    for _ in 1..6 {
        let base: list<int> = $sub
        let kids: list<int> = ($rows | where ppid in $base | get pid)
        let fresh: list<int> = ($kids | where {|k| not ($k in $base) })
        if ($fresh | is-empty) { break }
        $sub = ($sub | append $fresh)
    }
    $sub
}

# The PURE core of the island scan: given the process rows and the protect
# set, split the idle zcode-cli islands into killable and held. An idle
# island of ANOTHER session parked on a live build is itself idle while
# its gradle child breathes — killing the parent would orphan that turn.
# An island dies only when nothing below it breathes either.
def island-partition [rows: list<ArgsRow>, prot: list<int>]: nothing -> IslandScan {
    let idle: list<ArgsRow> = ($rows
        | where {|r| ($r.args =~ '\bzcode-cli\b') and (not ($r.pid in $prot)) and ($r.cpu < $IDLE_CPU) })
    let held: list<record<pid: int, breatherPid: int, breatherCpu: float>> = ($idle
        | each {|c|
            let sub: list<int> = (descendants $rows $c.pid)
            let hot: list<ArgsRow> = ($rows
                | where {|r| ($r.pid in $sub) and ($r.pid != $c.pid) and ($r.cpu >= $IDLE_CPU) }
                | sort-by -r cpu)
            if ($hot | is-empty) { null } else { {pid: $c.pid, breatherPid: ($hot | get 0.pid), breatherCpu: ($hot | get 0.cpu)} }
        }
        | compact)
    let heldPids: list<int> = ($held | get pid)
    {
        killable: ($idle | where {|c| not ($c.pid in $heldPids) } | each {|c| {pid: $c.pid, cpu: $c.cpu} })
        held: $held
    }
}

# The impure edge of the island scan: one ps feed with args, parsed once.
def islands [prot: list<int>]: nothing -> IslandScan {
    let rows: list<ArgsRow> = (^ps -axo pid=,ppid=,pcpu=,args=
        | lines
        | where {|l| ($l | str trim) != "" }
        | each {|l| args-row $l })
    island-partition $rows $prot
}

# "total = 4096.00M used = 2434.00M free = ..." → the used MB as int.
def swap-used-mb []: nothing -> int {
    let line: string = (^sysctl -n vm.swapusage | str trim)
    let used: string = ($line | split row "used = " | get 1 | split row "M" | get 0 | str trim)
    ($used | into int)
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
    let prot: list<int> = (protect-set $ps)
    let freeBefore: int = (free-pct)
    let swapBefore: string = (swap-line)
    let boot: int = (^sysctl -n kern.boottime | parse -r 'sec = (?<sec>\d+)' | get 0.sec | into int)
    let swapUsed: int = (swap-used-mb)
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
    let fams: list<FamilySum> = (families | first 60)
    snapshot-write $ledger $fams $boot $freeBefore $swapUsed
    leak-report $fams $prev $bootSnap $leak_run_mb $leak_boot_mb $swapUsed

    # 0. the pattern surface: who holds the memory right now.
    emit $"before: free ($freeBefore)% · swap ($swapBefore)"
    emit "== top 10 memory citizens (MB) =="
    emit (rss-snap | sort-by -r rssMb | first 10 | select name pid rssMb cpu | table)

    # 1. Task-Island zcode-cli processes — descendant-aware: an island dies
    #    only when nothing below it breathes either.
    let scan: IslandScan = (islands $prot)
    emit $"islands: ($scan.killable | length) idle zcode-cli candidates — pids ($scan.killable | get pid | str join ', ')"
    for h in $scan.held {
        emit $"island held: ($h.pid) — descendant ($h.breatherPid) breathes at ($h.breatherCpu)% — not killed"
    }
    let isleKills: list<int> = (if $clean and (($scan.killable | length) > 0) {
        kill ...($scan.killable | get pid)
        emit $"killed islands: ($scan.killable | get pid | str join ', ')"
        $scan.killable | get pid
    } else { [] })

    # 2. ollama pattern: the brain's embedder stays, the rest reload on demand.
    let ops: record = (do { ollama ps } | complete)
    let loaded: list<string> = ($ops.stdout | lines | skip 1
        | where {|l| ($l | str trim) != "" }
        | each {|l| $l | str trim | split row -r '\s+' | get 0 })
    let droppable: list<string> = ($loaded | where {|m| not ($m =~ $KEEP_OLLAMA) })
    emit $"ollama loaded: ($loaded | str join ', ') — keep ($KEEP_OLLAMA), drop: ($droppable | str join ', ')"
    let droppedModels: list<string> = (if $clean and (($droppable | length) > 0) {
        for m in $droppable {
            let stop: record = (do { ollama stop $m } | complete)
            emit $"ollama stop ($m): exit ($stop.exit_code)"
        }
        $droppable
    } else { [] })

    # 3. AppleSpell growth bug.
    let spell: list<int> = ($ps | where name == "AppleSpell" | get pid)
    emit $"AppleSpell: ($spell | str join ', ')"
    let spellKills: list<int> = (if $clean and (($spell | length) > 0) {
        kill ...$spell
        emit "AppleSpell killed — it respawns small on demand"
        $spell
    } else { [] })

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
    let buildKills: list<int> = (if $clean and (($builds | length) > 0) {
        kill ...($builds | get pid)
        emit $"killed build daemons: ($builds | get pid | str join ', ')"
        $builds | get pid
    } else { [] })

    # 5. LoginItems — the macOS host of the login-item daemons (the Logi
    #    services live INSIDE it). Measured 21/11: 1163 MB at 13:15 → 1549 MB
    #    at 19:11 with 100% cpu — THE felt leak. A restart respawns it clean.
    let loginItems: list<int> = ($ps | where name == "LoginItems" | get pid)
    let liRss: int = (rss-snap | where name == "LoginItems" | get -o 0 | default {rssMb: 0} | get -o rssMb | default 0)
    emit $"LoginItems — the login-item host where the Logi services live: ($liRss) MB"
    let loginKills: list<int> = (if $clean and (($loginItems | length) > 0) {
        kill ...$loginItems
        emit "LoginItems restarted — it respawns clean and the login-item daemons come back with it"
        $loginItems
    } else { [] })

    # 6. the Logi Options+ family — report + only the crash reporter dies.
    # macOS system processes (LoginItems, loginwindow, logind, login) also
    # start with "logi" — measured false positives 21/11 that inflated the
    # family total by >1 GB; exclude them explicitly.
    let logi: table = (rss-snap | where {|r|
        let low: string = ($r.name | str lowercase)
        ($low =~ '^logi') and (not ($low =~ '^login'))
    } | select name pid rssMb cpu)
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
    let crashpadKills: list<int> = (if $clean and (($crashpads | length) > 0) {
        kill ...$crashpads
        emit "logi_crashpad_handler killed — it respawns when a crash needs reporting"
        $crashpads
    } else { [] })

    if $clean {
        sleep 2sec
        # The receipts pass: every kill re-verified against a fresh
        # external-ps snapshot (the builtin ps's pid column lies — the
        # process-liveness law; snap is the measured truth) — dead is a
        # receipt, SURVIVED is named, respawned-by-design is the new
        # state (LoginItems must come back SMALL).
        let ps2: list<PsRow> = (snap)
        let deadCheck: closure = {|label: string, pids: list<int>|
            if ($pids | is-empty) { "" } else {
                let alive: list<int> = ($ps2 | where pid in $pids | get pid)
                if ($alive | is-empty) {
                    $"($label): ($pids | length) killed → verified dead"
                } else {
                    $"($label): SURVIVED — still alive: ($alive | str join ', ')"
                }
            }
        }
        for line in [(do $deadCheck "islands" $isleKills) (do $deadCheck "build daemons" $buildKills)] {
            if ($line != "") { emit $line }
        }
        let respawnCheck: closure = {|label: string, pids: list<int>, name: string|
            if ($pids | is-empty) { "" } else {
                let nowPids: list<int> = ($ps2 | where name == $name | get pid)
                if ($nowPids | is-empty) {
                    $"($label): killed → gone — respawns on demand"
                } else {
                    $"($label): killed → already respawned — pids ($nowPids | str join ', ')"
                }
            }
        }
        for line in [(do $respawnCheck "AppleSpell" $spellKills "AppleSpell") (do $respawnCheck "logi crashpad" $crashpadKills "logi_crashpad_handler")] {
            if ($line != "") { emit $line }
        }
        if not ($loginKills | is-empty) {
            let liRss2: int = (rss-snap | where name == "LoginItems" | get -o 0 | default {rssMb: 0} | get -o rssMb | default 0)
            if ($liRss2 == 0) {
                emit "LoginItems: killed → not yet respawned after 2s — launchd brings it back"
            } else {
                emit $"LoginItems: killed → respawned at ($liRss2) MB — was ($liRss) MB"
            }
        }
        if not ($droppedModels | is-empty) {
            let ops2: record = (do { ollama ps } | complete)
            let loaded2: list<string> = ($ops2.stdout | lines | skip 1
                | where {|l| ($l | str trim) != "" }
                | each {|l| $l | str trim | split row -r '\s+' | get 0 })
            let stillLoaded: list<string> = ($loaded2 | where {|m| $m in $droppedModels })
            if ($stillLoaded | is-empty) {
                emit $"ollama: ($droppedModels | str join ', ') → verified unloaded"
            } else {
                emit $"ollama: still loaded after stop: ($stillLoaded | str join ', ')"
            }
        }
        let freeAfter: int = (free-pct)
        let swapAfter: string = (swap-line)
        let swapUsedAfter: int = (swap-used-mb)
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
