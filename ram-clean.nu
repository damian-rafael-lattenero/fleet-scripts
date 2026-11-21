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
# between runs and never comes back.
const SNAP_FILE: string = "/Users/lattenero/Library/Logs/ram-snapshots.jsonl"
# The brain's embedder — the ONLY ollama model that stays loaded.
const KEEP_OLLAMA: string = "nomic-embed"
# cpu percent under which a process counts as idle. A live turn or an
# active build breathes well above this; abandoned things sit at 0.
const IDLE_CPU: float = 1.0

use /Users/lattenero/Projects/nushell-fp/mods/log.nu *

# One voice for stdout AND the run log — the shared mod does the work.
def emit [line: string]: nothing -> nothing {
    emit-to $LOG_FILE $line
}

# "System-wide memory free percentage: 64%" → 64.
def free-pct []: nothing -> int {
    let line: string = (memory_pressure | lines | where {|l| $l =~ "memory free percentage"} | last)
    ($line | split row ":" | get 1 | str trim | str replace "%" "" | into int)
}

def swap-line []: nothing -> string {
    ^sysctl -n vm.swapusage | str trim
}

def pid-cpu [line: string]: nothing -> record {
    let t: string = ($line | str trim)
    let parts: list<string> = ($t | split row -r '\s+')
    {pid: ($parts | get 0 | into int), cpu: ($parts | get 1 | into float)}
}

# The full ps snapshot as records (the builtin ps lacks pcpu and comm).
def snap []: nothing -> table {
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
def rss-snap []: nothing -> table {
    ^ps -axo rss=,pid=,pcpu=,comm=
    | lines
    | where {|l| ($l | str trim) != "" }
    | each {|l|
        let parts: list<string> = (($l | str trim) | split row -r '\s+')
        {rssMb: (($parts | get 0 | into int) / 1024 | math round), pid: ($parts | get 1 | into int), cpu: ($parts | get 2 | into float), name: ($parts | get 3 | path basename)}
    }
}

# Family grouping: an Electron app is 20+ helper processes; the leaks show
# per FAMILY, not per pid.
def family-of [name: string]: nothing -> string {
    let low: string = ($name | str lowercase)
    if ($low =~ '^zcode') {
        "zcode-family"
    } else if (($low =~ '^logi') and (not ($low =~ '^login'))) {
        "logi-family"
    } else if ($low =~ '^google') {
        "chrome-family"
    } else if ($low =~ 'llama-server') {
        "ollama-runners"
    } else {
        $name
    }
}

# The families aggregated (sum RSS + process count), the biggest first.
def families []: nothing -> table {
    rss-snap
    | insert family {|r| family-of $r.name }
    | group-by family
    | items {|k, v| {family: $k, rssMb: ($v | get rssMb | math sum), n: ($v | length)} }
    | sort-by -r rssMb
}

# Append this run's snapshot to the JSONL ledger and return it.
def snapshot-write [boot: int, free: int, swapUsedMb: int]: nothing -> record {
    let fams: table = (families | first 60)
    let rec: record = {
        stamp: (date now | format date "%Y-%m-%d %H:%M:%S")
        boot: $boot
        free: $free
        swapUsedMb: $swapUsedMb
        procs: ($fams | each {|f| {family: $f.family, rssMb: $f.rssMb, n: $f.n} })
    }
    (($rec | to json -r) + (char nl)) | save --append --raw $SNAP_FILE
    $rec
}

# The last snapshot in the ledger — null when this is the first run.
def last-snapshot []: nothing -> any {
    if not ($SNAP_FILE | path exists) { return null }
    let lines: list<string> = (open --raw $SNAP_FILE | lines | where {|l| ($l | str trim) != "" })
    if ($lines | is-empty) { return null }
    try { $lines | last | from json } catch { null }
}

# The first snapshot of the CURRENT boot — the since-boot growth baseline.
def boot-snapshot [boot: int]: nothing -> any {
    if not ($SNAP_FILE | path exists) { return null }
    let lines: list<string> = (open --raw $SNAP_FILE | lines | where {|l| ($l | str trim) != "" })
    let rows: list<record> = ($lines | each {|l| try { $l | from json } catch { null } } | compact)
    let sameBoot: list<record> = ($rows | where boot == $boot)
    if ($sameBoot | is-empty) { null } else { $sameBoot | first }
}

# The per-family RSS lookup of one snapshot — 0 when the family is absent
# (killed by the previous clean, or born after it).
def fam-rss [snap: record, family: string]: nothing -> int {
    let hit: list<record> = ($snap.procs | where {|p| $p.family == $family })
    if ($hit | is-empty) { 0 } else { $hit | first | get rssMb }
}

# The leak detector: growth since the last run AND since the boot, per
# family, flagged at the thresholds. A null snapshot = first run = baseline.
def leak-report [
    now: table, prev: any, bootSnap: any,
    leakRunMb: int, leakBootMb: int, swapUsedMb: int,
]: nothing -> nothing {
    let prevSwap: int = (if $prev != null { $prev.swapUsedMb? | default 0 } else { $swapUsedMb })
    let bootSwap: int = (if $bootSnap != null { $bootSnap.swapUsedMb? | default 0 } else { $swapUsedMb })
    if $prev == null {
        emit "leak ledger: baseline captured — run again later and the growth per family appears here"
        emit $"swap used now: ($swapUsedMb) MB"
        return
    }
    let rows: list<record> = ($now
        | each {|f|
            let before: int = (if $prev != null { fam-rss $prev $f.family } else { 0 })
            let atBoot: int = (if $bootSnap != null { fam-rss $bootSnap $f.family } else { 0 })
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
def protect-set [ps: table]: nothing -> list<int> {
    mut chain: list<int> = [$nu.pid]
    mut cur: int = $nu.pid
    for _ in 1..15 {
        let row: list<record> = ($ps | where pid == $cur)
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
def islands [ps: table, prot: list<int>]: nothing -> table {
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
    let ps: table = (snap)
    let prot: list<int> = (protect-set $ps)
    let freeBefore: int = (free-pct)
    let swapBefore: string = (swap-line)
    let boot: int = (^sysctl -n kern.boottime | parse -r 'sec = (?<sec>\d+)' | get 0.sec | into int)
    let swapUsed: int = (swap-used-mb)
    emit $"== ram-clean ($stamp) — clean=($clean) =="

    # -1. the leak ledger: snapshot now, diff against the last run and the boot.
    let prev: any = (last-snapshot)
    let bootSnap: any = (boot-snapshot $boot)
    let snap: record = (snapshot-write $boot $freeBefore $swapUsed)
    leak-report (families) $prev $bootSnap $leak_run_mb $leak_boot_mb $swapUsed

    # 0. the pattern surface: who holds the memory right now.
    emit $"before: free ($freeBefore)% · swap ($swapBefore)"
    emit "== top 10 memory citizens (MB) =="
    emit (rss-snap | sort-by -r rssMb | first 10 | select name pid rssMb cpu | table)

    # 1. Task-Island zcode-cli processes.
    let isles: table = (islands $ps $prot)
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
    let gradles: table = (^ps -axo pid=,pcpu=,args=
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
