#!/opt/homebrew/bin/nu
# ram-clean.nu — the RAM relief routine, DEEPENED on the owner's 21/11 ask
# for a more intense, pattern-recognizing, maximum-recovery clean.
# Default: PLAN ONLY (measures, names every candidate, frees nothing).
# --clean executes, one decision per line, stdout AND the run log:
#   0. the top-10 memory citizens — the pattern surface, shown every run
#   1. idle Task-Island zcode-cli processes — cpu < 1%, never my own
#      ancestry and never my session's own helper descendants
#   2. ollama pattern: the brain's embedder (nomic-embed) STAYS, every
#      other loaded model is stopped (stop != delete; they reload on demand)
#   3. AppleSpell killed (macOS growth bug; respawns small on demand)
#   4. idle gradle daemons killed (respawn on the next build; a BUILDING
#      daemon breathes above the idle threshold and is never touched)
#   5. the Logi Options+ family: reported with RSS totals and the web
#      receipts — only its crash reporter is auto-killed; replacing the
#      daemon is the owner's decision (measured ~1.0 GB across processes)
# Every run appends to ~/Library/Logs/ram-clean.log.

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

# The type aliases (the owner's 22/11 law): every shape reads once and the
# signatures spell the name. The nullable family is oneof<string, nothing> —
# a bare null literal against a plain `string` field fails the parse
# (measured 22/11), `nothing` is the null arm that works.
type PsRow = record<pid: int, ppid: int, cpu: float, name: string>
type CpuRow = record<pid: int, cpu: float>
type RssRow = record<rssMb: int, pid: int, cpu: float, name: string>
type FamilyRule = record<pattern: string, family: oneof<string, nothing>>
type FamilySum = record<family: string, rssMb: int, n: int>
type LeakRow = record<family: string, nowMb: int, runDelta: int, bootDelta: int>
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

# zcode-cli candidates: the binary, outside the protect set, idle cpu.
def islands [prot: list<int>]: nothing -> list<CpuRow> {
    ^ps -axo pid=,ppid=,pcpu=,args=
    | lines
    | where {|l| $l =~ '\bzcode-cli\b' }
    | each {|l| pid-cpu $l }
    | where {|r| (not ($r.pid in $prot)) and ($r.cpu < $IDLE_CPU) }
}

# "total = 4096.00M used = 2434.00M free = ..." → the used MB as int.
def swap-used-mb []: nothing -> int {
    let line: string = (^sysctl -n vm.swapusage | str trim)
    let used: string = ($line | split row "used = " | get 1 | split row "M" | get 0 | str trim)
    ($used | into int)
}

def main [
    --clean
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
    emit $"== ram-clean ($stamp) — clean=($clean) =="

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

    # 1. Task-Island zcode-cli processes.
    let isles: list<CpuRow> = (islands $prot)
    emit $"islands: ($isles | length) idle zcode-cli candidates — pids ($isles | get pid | str join ', ')"
    if $clean and (($isles | length) > 0) {
        kill ...($isles | get pid)
        emit $"killed islands: ($isles | get pid | str join ', ')"
    }

    # 2. ollama pattern: the brain's embedder stays, the rest reload on demand.
    let ops: record = (do { ollama ps } | complete)
    let loaded: list<string> = ($ops.stdout | lines | skip 1
        | where {|l| ($l | str trim) != "" }
        | each {|l| $l | str trim | split row -r '\s+' | get 0 })
    let droppable: list<string> = ($loaded | where {|m| not ($m =~ $KEEP_OLLAMA) })
    emit $"ollama loaded: ($loaded | str join ', ') — keep ($KEEP_OLLAMA), drop: ($droppable | str join ', ')"
    if $clean and (($droppable | length) > 0) {
        for m in $droppable {
            let stop: record = (do { ollama stop $m } | complete)
            emit $"ollama stop ($m): exit ($stop.exit_code)"
        }
    }

    # 3. AppleSpell growth bug.
    let spell: list<int> = ($ps | where name == "AppleSpell" | get pid)
    emit $"AppleSpell: ($spell | str join ', ')"
    if $clean and (($spell | length) > 0) {
        kill ...$spell
        emit "AppleSpell killed — it respawns small on demand"
    }

    # 4. idle gradle daemons (an ACTIVE build breathes above the threshold).
    let gradles: list<CpuRow> = (^ps -axo pid=,pcpu=,args=
        | lines
        | where {|l| $l =~ 'GradleDaemon' }
        | each {|l| pid-cpu $l }
        | where {|r| $r.cpu < $IDLE_CPU })
    emit $"idle gradle daemons: ($gradles | length) — pids ($gradles | get pid | str join ', ')"
    if $clean and (($gradles | length) > 0) {
        kill ...($gradles | get pid)
        emit $"killed gradle daemons: ($gradles | get pid | str join ', ')"
    }

    # 5. LoginItems — the macOS host of the login-item daemons (the Logi
    #    services live INSIDE it). Measured 21/11: 1163 MB at 13:15 → 1549 MB
    #    at 19:11 with 100% cpu — THE felt leak. A restart respawns it clean.
    let loginItems: list<int> = ($ps | where name == "LoginItems" | get pid)
    let liRss: int = (rss-snap | where name == "LoginItems" | get -o 0 | default {rssMb: 0} | get -o rssMb | default 0)
    emit $"LoginItems — the login-item host where the Logi services live: ($liRss) MB"
    if $clean and (($loginItems | length) > 0) {
        kill ...$loginItems
        emit "LoginItems restarted — it respawns clean and the login-item daemons come back with it"
    }

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
        let crashpads: list<int> = ($logi | where name == "logi_crashpad_handler" | get pid)
        if $clean and (($crashpads | length) > 0) {
            kill ...$crashpads
            emit "logi_crashpad_handler killed — it respawns when a crash needs reporting"
        }
    }

    if $clean {
        sleep 2sec
        let freeAfter: int = (free-pct)
        let swapAfter: string = (swap-line)
        emit $"after: free ($freeAfter)% · swap ($swapAfter)"
        emit $"freed: ($freeAfter - $freeBefore) points of free percentage"
    } else {
        emit "plan only — re-run with --clean to execute"
    }
}
