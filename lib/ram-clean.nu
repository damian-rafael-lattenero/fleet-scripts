# lib/ram-clean.nu — the pure core of ram-clean.nu: the ps/memory_pressure/
# swap/ollama parsers, the family table, the ledger arithmetic (snapshot,
# prune, trend, leak), the protect set and the island partition, and the
# post-kill receipt lines. The script keeps every kill, read and write.
use /Users/lattenero/Scripts/nushell-fp/mods/types.nu *
use ./json-lines.nu *

export type PsRow = record<pid: int, ppid: int, cpu: float, name: string>
export type CpuRow = record<pid: int, cpu: float>
# An args-bearing process row — the feed the island scan matches candidates
# on and walks descendants over (one ps feed for both jobs).
export type ArgsRow = record<pid: int, ppid: int, cpu: float, args: string>
# The island scan's verdict: killable islands (whole subtree idle), and
# the ones HELD BACK because a descendant breathes — the breather named.
export type IslandScan = record<killable: list<CpuRow>, held: list<record<pid: int, breatherPid: int, breatherCpu: float>>>
export type RssRow = record<rssMb: int, pid: int, cpu: float, name: string>
export type FamilyRule = record<pattern: string, family: oneof<string, nothing>>
export type FamilySum = record<family: string, rssMb: int, n: int>
export type LeakRow = record<family: string, nowMb: int, runDelta: int, bootDelta: int>
# One family's trajectory across the trend window: first/last/Δ in the
# window, plus the persistence count — how many consecutive-step runs it
# only went UP (climbers sit near the run count, noise hovers half).
export type TrendRow = record<family: string, firstMb: int, lastMb: int, deltaMb: int, upRuns: int, seenRuns: int>
export type Snapshot = record<stamp: string, boot: int, free: int, swapUsedMb: int, procs: list<FamilySum>>
# A prior-run lookup as the nushell-fp Option shape (union aliases don't
# parse, measured — the kind lives in the tag row).
export type Prior = record<tag: string, value: any>

# cpu percent under which a process counts as idle. A live turn or an
# active build breathes well above this; abandoned things sit at 0.
export const IDLE_CPU: float = 1.0

# "System-wide memory free percentage: 64%" → 64. A shape change of the
# macOS output is a LOUD error, never a wrong number.
export def free-pct-of [text: string]: nothing -> int {
    let hits: list<string> = ($text | lines | where {|l| $l =~ "memory free percentage"})
    if ($hits | is-empty) {
        error make {msg: "memory_pressure output changed — no 'memory free percentage' line; the parse boundary broke"}
    }
    let line: string = ($hits | last)
    ($line | split row ":" | get 1 | str trim | str replace "%" "" | into int)
}

# One ps line's pid + %cpu (the build-daemon scan's parse).
export def pid-cpu [line: string]: nothing -> CpuRow {
    let r: record = ($line | parse -r '^\s*(?<pid>\d+)\s+(?<cpu>[\d.]+)' | get 0)
    {pid: ($r.pid | into int), cpu: ($r.cpu | into float)}
}

# The full ps snapshot as records (the builtin ps lacks pcpu and comm).
export def ps-rows [text: string]: nothing -> list<PsRow> {
    $text
    | lines
    | where {|l| ($l | str trim) != "" }
    | parse -r '^\s*(?<pid>\d+)\s+(?<ppid>\d+)\s+(?<cpu>[\d.]+)\s+(?<comm>.+)$'
    | each {|r|
        {pid: ($r.pid | into int), ppid: ($r.ppid | into int), cpu: ($r.cpu | into float), name: ($r.comm | path basename)}
    }
}

# RSS rows: ps rss is KB; the owner reads MB. The comm tail is GREEDY —
# ps comm is a PATH and macOS app paths carry spaces (the old positional
# split truncated 27 of 421 names, measured 24/11); `parse -r` is greedy.
export def rss-rows [text: string]: nothing -> list<RssRow> {
    $text
    | lines
    | where {|l| ($l | str trim) != "" }
    | parse -r '^\s*(?<rss>\d+)\s+(?<pid>\d+)\s+(?<cpu>[\d.]+)\s+(?<comm>.+)$'
    | each {|r|
        {rssMb: (($r.rss | into int) / 1024 | math round), pid: ($r.pid | into int), cpu: ($r.cpu | into float), name: ($r.comm | path basename)}
    }
}

# Family grouping: an Electron app is 20+ helper processes; the leaks show
# per FAMILY, not per pid. The mapping is DATA — a priority-ordered
# predicate table. The login row sits FIRST so macOS system processes
# (LoginItems, loginwindow, logind) pass through ungrouped before the logi
# row can claim them — rust regex has no lookahead, row precedence does the
# job. family: null = pass through with the raw name.
export def family-table []: nothing -> list<FamilyRule> {
    [
        {pattern: '^login', family: null}
        {pattern: '^zcode', family: "zcode-family"}
        {pattern: '^logi', family: "logi-family"}
        {pattern: '^google', family: "chrome-family"}
        # VS Code's main binary is `Code` and its helpers are `Code Helper…`.
        # Anchored so `codesign…` never matches.
        {pattern: '^code helper|^code$', family: "vscode-family"}
        {pattern: 'llama-server', family: "ollama-runners"}
        {pattern: '', family: null}
    ]
}

export def family-of [name: string]: nothing -> string {
    let low: string = ($name | str lowercase)
    let hit: FamilyRule = (family-table | where {|row| $low =~ $row.pattern } | first)
    ($hit.family | default $name)
}

# The families aggregated (sum RSS + process count), the biggest first.
export def families [rows: list<RssRow>]: nothing -> list<FamilySum> {
    $rows
    | insert family {|r| family-of $r.name }
    | group-by family
    | items {|k, v| {family: $k, rssMb: ($v | get rssMb | math sum), n: ($v | length)} }
    | sort-by -r rssMb
}

# The RSS total of one process name in a scan — 0 when absent (`math sum`
# refuses empty input, measured 24/11).
export def rss-of [rows: list<RssRow>, name: string]: nothing -> int {
    let hits: list<RssRow> = ($rows | where name == $name)
    $hits | reduce -f 0 {|r, acc| $acc + $r.rssMb}
}

# The logi family's process rows — the family TABLE decides membership, not
# a second copy of the `^logi`/`^login` rule.
export def logi-rows [rows: list<RssRow>]: nothing -> table {
    $rows
    | insert family {|r| family-of $r.name }
    | where family == "logi-family"
    | select name pid rssMb cpu
}

# This run's snapshot record (the write itself is the script's edge).
export def snapshot-record [fams: list<FamilySum>, boot: int, free: int, swap_used_mb: int, stamp: string]: nothing -> Snapshot {
    {stamp: $stamp, boot: $boot, free: $free, swapUsedMb: $swap_used_mb, procs: $fams}
}

# The ledger with this run appended and only the last keep_boots boots
# surviving — the boot baseline is never evicted, the file never grows.
export def pruned-ledger [rows: list<Snapshot>, rec: Snapshot, keep_boots: int]: nothing -> list<Snapshot> {
    let boots: list<int> = ($rows | get boot | uniq | last $keep_boots)
    $rows | where {|r| $r.boot in $boots } | append $rec
}

# The ledger parsed once at the boundary; corrupt lines drop (the shared
# record-lines piece — 0.117's from json is LENIENT, and a half-written
# snapshot line must never poison the ledger as a string row).
export def ledger-parse [text: string]: nothing -> list<Snapshot> {
    record-lines $text
}

# The last snapshot in the ledger — none when this is the first run.
export def last-snapshot [rows: list<Snapshot>]: nothing -> Prior {
    if ($rows | is-empty) { (none) } else { some ($rows | last) }
}

# The first snapshot of the CURRENT boot — the since-boot growth baseline.
export def boot-snapshot [rows: list<Snapshot>, boot: int]: nothing -> Prior {
    let sameBoot: list<Snapshot> = ($rows | where boot == $boot)
    if ($sameBoot | is-empty) { (none) } else { some ($sameBoot | first) }
}

# The per-family RSS lookup of one snapshot — 0 when absent (killed by the
# previous clean, or born after it).
export def fam-rss [snap: Snapshot, family: string]: nothing -> int {
    let hit: list<FamilySum> = ($snap.procs | where {|p| $p.family == $family })
    if ($hit | is-empty) { 0 } else { $hit | first | get rssMb }
}

# The trend window as family trajectories: absent-from-a-snapshot reads 0,
# sorted by Δ (climbers first, the fallers of a working clean at the
# bottom), capped at 12.
export def trend-rows [snaps: list<Snapshot>]: nothing -> list<TrendRow> {
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

# The leak suspects: per family, growth since the LAST run and since the
# BOOT, flagged at the thresholds. prev must be a some (the caller guards
# the baseline case) — below the guard every value is a Snapshot.
export def leak-rows [now: list<FamilySum>, prev: Prior, boot_snap: Prior, leak_run_mb: int, leak_boot_mb: int]: nothing -> list<LeakRow> {
    let prevSnap: Snapshot = $prev.value
    $now
    | each {|f|
        let before: int = (fam-rss $prevSnap $f.family)
        let atBoot: int = ($boot_snap | option-match {|s| fam-rss $s $f.family } {|| 0 })
        {
            family: $f.family
            nowMb: $f.rssMb
            runDelta: ($f.rssMb - $before)
            bootDelta: ($f.rssMb - $atBoot)
        }
    }
    | where {|r| ($r.runDelta >= $leak_run_mb) or ($r.bootDelta >= $leak_boot_mb) }
    | sort-by -r bootDelta
}

# My ancestor chain + ALL its descendants (my session's own MCP helpers).
# The root is an ARGUMENT (the interpreter's pid at the edge) so the set is
# a pure function of the process table.
export def protect-set [ps: list<PsRow>, root: int]: nothing -> list<int> {
    mut chain: list<int> = [$root]
    mut cur: int = $root
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

# The descendants of one pid — the same fixpoint expansion protect-set runs
# over MY subtree, pointed at a CANDIDATE: everything below it.
export def descendants [rows: list<ArgsRow>, root: int]: nothing -> list<int> {
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

# The PURE core of the island scan: split the idle zcode-cli islands into
# killable and held. An idle island parked on a live build is itself idle
# while its gradle child breathes — killing the parent would orphan that
# turn. An island dies only when nothing below it breathes either.
export def island-partition [rows: list<ArgsRow>, prot: list<int>]: nothing -> IslandScan {
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

# "total = 4096.00M used = 2434.00M free = ..." → the used MB as int.
export def swap-used-mb [line: string]: nothing -> int {
    let used: string = ($line | split row "used = " | get 1 | split row "M" | get 0 | str trim)
    ($used | into int)
}

# `ollama ps`'s model list: header skipped, first column per row.
export def loaded-models [stdout: string]: nothing -> list<string> {
    $stdout | lines | skip 1
    | where {|l| ($l | str trim) != "" }
    | each {|l| $l | str trim | split row -r '\s+' | get 0 }
}

# The brain's embedder stays, every other loaded model reloads on demand.
export def droppable-models [loaded: list<string>, keep: string]: nothing -> list<string> {
    $loaded | where {|m| not ($m =~ $keep) }
}

# The receipt for a kill whose process must be GONE: dead or SURVIVED.
export def receipt-dead [label: string, pids: list<int>, ps2: list<PsRow>]: nothing -> string {
    if ($pids | is-empty) { return "" }
    let alive: list<int> = ($ps2 | where pid in $pids | get pid)
    if ($alive | is-empty) {
        $"($label): ($pids | length) killed → verified dead"
    } else {
        $"($label): SURVIVED — still alive: ($alive | str join ', ')"
    }
}

# The receipt for a kill whose process respawns BY DESIGN: gone (comes back
# on demand) or already back.
export def receipt-respawn [label: string, pids: list<int>, name: string, ps2: list<PsRow>]: nothing -> string {
    if ($pids | is-empty) { return "" }
    let nowPids: list<int> = ($ps2 | where name == $name | get pid)
    if ($nowPids | is-empty) {
        $"($label): killed → gone — respawns on demand"
    } else {
        $"($label): killed → already respawned — pids ($nowPids | str join ', ')"
    }
}

# LoginItems must come back SMALL: the receipt names both sizes.
export def login-receipt [before: int, after: int]: nothing -> string {
    if $after == 0 {
        "LoginItems: killed → not yet respawned after 2s — launchd brings it back"
    } else {
        $"LoginItems: killed → respawned at ($after) MB — was ($before) MB"
    }
}

# A failed signal is two facts: gone already (harmless) or refused (a
# root-owned process — ESRCH/EPERM read the same to nu).
export def signal-outcomes [failed: list<int>, still: list<int>]: nothing -> record<gone: list<int>, refused: list<int>> {
    {gone: ($failed | where {|p| not ($p in $still)}), refused: $still}
}
