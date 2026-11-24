# test_ram_clean.nu — the pure-core proofs for lib/ram-clean.nu: every
# parser, the family table, the ledger arithmetic (prune/trend/leak), the
# protect set, the island partition and the receipt lines.
use std/assert
use ../../lib/ram-clean.nu *
use /Users/lattenero/Scripts/nushell-fp/mods/types.nu *   # some/none constructors

# 1. memory_pressure: the percentage parses, the LAST matching line wins,
#    and a changed shape is a loud error (never a wrong number).
assert equal (free-pct-of "System-wide memory free percentage: 64%") 64
assert equal (free-pct-of "noise\nSystem-wide memory free percentage: 40%\nSystem-wide memory free percentage: 71%\n") 71
assert error { free-pct-of "output changed" }

# 2. the ps parsers: padded columns, path comm, greedy tail (spaces in app
#    paths never truncate the name).
let ps_text: string = "  123   1  3.4 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome\n  456   1  0.0 /usr/libexec/loginwindow\n"
let ps: list<PsRow> = (ps-rows $ps_text)
assert equal ($ps | length) 2
assert equal $ps.0 {pid: 123, ppid: 1, cpu: 3.4, name: "Google Chrome"}
assert equal $ps.1.name "loginwindow"
let rss_text: string = "204800  123  3.4 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome\n1024  456  0.0 helper\n"
let rss: list<RssRow> = (rss-rows $rss_text)
assert equal $rss.0 {rssMb: 200, pid: 123, cpu: 3.4, name: "Google Chrome"}
assert equal $rss.1.rssMb 1
assert equal (pid-cpu "  789  12.5 GradleDaemon org.gradle.launcher") {pid: 789, cpu: 12.5}

# 3. the family table: row order is the law (login before logi; anchored
#    vscode; anything else passes through raw).
assert equal (family-of "zcode-cli") "zcode-family"
assert equal (family-of "ZCode") "zcode-family"
assert equal (family-of "logi_options_plus") "logi-family"
assert equal (family-of "LoginItems") "LoginItems"          # the ^login row wins
assert equal (family-of "loginwindow") "loginwindow"
assert equal (family-of "Google Chrome") "chrome-family"
assert equal (family-of "Code") "vscode-family"
assert equal (family-of "Code Helper (Renderer)") "vscode-family"
assert equal (family-of "codesign_allocate") "codesign_allocate"
assert equal (family-of "llama-server") "ollama-runners"
assert equal (family-of "ollama") "ollama"
assert equal (family-of "sourdough") "sourdough"

# 4. the families aggregate: sums + counts, biggest first.
let fam_rows: list<RssRow> = [
    {rssMb: 200, pid: 1, cpu: 0.0, name: "Google Chrome"}
    {rssMb: 100, pid: 2, cpu: 0.0, name: "Google Chrome"}
    {rssMb: 50, pid: 3, cpu: 0.0, name: "zcode-cli"}
]
let fams: list<FamilySum> = (families $fam_rows)
assert equal $fams.0 {family: "chrome-family", rssMb: 300, n: 2}
assert equal $fams.1 {family: "zcode-family", rssMb: 50, n: 1}
assert equal (rss-of $fam_rows "Google Chrome") 300
assert equal (rss-of $fam_rows "absent") 0

# 5. the logi report: the TABLE's membership, LoginItems never inside.
let logi: table = (logi-rows [
    {rssMb: 500, pid: 1, cpu: 0.1, name: "logi_options_plus"}
    {rssMb: 1163, pid: 2, cpu: 100.0, name: "LoginItems"}
    {rssMb: 10, pid: 3, cpu: 0.0, name: "zcode-cli"}
])
assert equal ($logi | get name) ["logi_options_plus"]

# 6. the ledger: record, prune to the last N boots, parse with garbage dropped.
let s1: Snapshot = {stamp: "a", boot: 1, free: 60, swapUsedMb: 100, procs: []}
let s2: Snapshot = {stamp: "b", boot: 2, free: 61, swapUsedMb: 90, procs: []}
let s3: Snapshot = {stamp: "c", boot: 2, free: 62, swapUsedMb: 80, procs: []}
let rec: Snapshot = (snapshot-record [] 3 63 70 "d")
assert equal $rec {stamp: "d", boot: 3, free: 63, swapUsedMb: 70, procs: []}
let pruned: list<Snapshot> = (pruned-ledger [$s1 $s2 $s3] $rec 1)
assert equal ($pruned | get boot) [2 2 3]
assert equal ($pruned | get stamp) ["b" "c" "d"]
# keeping 2 distinct boots keeps both of them plus the new one
assert equal (pruned-ledger [$s1 $s2 $s3] $rec 2 | get boot) [1 2 2 3]
let parsed: list<Snapshot> = (ledger-parse $"($s1 | to json -r)\nnot json\n\n($s2 | to json -r)\n")
assert equal ($parsed | get stamp) ["a" "b"]
assert equal (ledger-parse "") []

# 7. the prior lookups and the per-family RSS of a snapshot.
let led: list<Snapshot> = [$s1 $s2]
assert equal (last-snapshot $led | get tag) "some"
assert equal ((last-snapshot $led).value.stamp) "b"
assert equal (last-snapshot [] | get tag) "none"
let bootsnap: Prior = (boot-snapshot $led 2)
assert equal $bootsnap.value.stamp "b"
assert equal (boot-snapshot $led 9 | get tag) "none"
let withprocs: Snapshot = {stamp: "x", boot: 1, free: 60, swapUsedMb: 0, procs: [{family: "A", rssMb: 42, n: 1}]}
assert equal (fam-rss $withprocs "A") 42
assert equal (fam-rss $withprocs "B") 0

# 8. the trend: series across snapshots (absent reads 0), Δ and upRuns,
#    sorted by Δ desc, cap 12.
let t1: Snapshot = {stamp: "1", boot: 1, free: 60, swapUsedMb: 0, procs: [{family: "A", rssMb: 100, n: 1}, {family: "B", rssMb: 50, n: 1}]}
let t2: Snapshot = {stamp: "2", boot: 1, free: 60, swapUsedMb: 0, procs: [{family: "A", rssMb: 150, n: 1}]}
let t3: Snapshot = {stamp: "3", boot: 1, free: 60, swapUsedMb: 0, procs: [{family: "A", rssMb: 300, n: 1}, {family: "B", rssMb: 40, n: 1}]}
let trend: list<TrendRow> = (trend-rows [$t1 $t2 $t3])
assert equal $trend.0 {family: "A", firstMb: 100, lastMb: 300, deltaMb: 200, upRuns: 2, seenRuns: 3}
assert equal $trend.1 {family: "B", firstMb: 50, lastMb: 40, deltaMb: -10, upRuns: 1, seenRuns: 2}
assert equal (trend-rows []) []

# 9. the leak suspects: runΔ or bootΔ at the thresholds, sorted by bootΔ desc.
let p1: Snapshot = {stamp: "p", boot: 1, free: 60, swapUsedMb: 0, procs: [{family: "A", rssMb: 100, n: 1}, {family: "C", rssMb: 5, n: 1}, {family: "D", rssMb: 200, n: 1}]}
let b1: Snapshot = {stamp: "b", boot: 1, free: 60, swapUsedMb: 0, procs: [{family: "A", rssMb: 50, n: 1}]}
let now: list<FamilySum> = [
    {family: "A", rssMb: 140, n: 1}
    {family: "C", rssMb: 10, n: 1}
    {family: "D", rssMb: 200, n: 1}
]
let leaks: list<LeakRow> = (leak-rows $now (some $p1) (some $b1) 30 150)
assert equal ($leaks | get family) ["D" "A"]
assert equal $leaks.0 {family: "D", nowMb: 200, runDelta: 0, bootDelta: 200}
assert equal $leaks.1 {family: "A", nowMb: 140, runDelta: 40, bootDelta: 90}
# no boot baseline -> bootΔ counted from zero: D (200) crosses, A keeps
# its runΔ flag, C stays quiet.
let leaks_noboot: list<LeakRow> = (leak-rows $now (some $p1) (none) 30 150)
assert equal ($leaks_noboot | get family) ["D" "A"]

# 10. the protect set: ancestors + their whole subtree fixpoint; a far
#     process is never included.
let tree: list<PsRow> = [
    {pid: 100, ppid: 50, cpu: 0.0, name: "nu"}
    {pid: 50, ppid: 10, cpu: 0.0, name: "zsh"}
    {pid: 10, ppid: 1, cpu: 0.0, name: "launchd"}
    {pid: 200, ppid: 100, cpu: 0.0, name: "helper"}
    {pid: 201, ppid: 100, cpu: 0.0, name: "helper"}
    {pid: 60, ppid: 50, cpu: 0.0, name: "sibling"}
    {pid: 300, ppid: 200, cpu: 0.0, name: "grandchild"}
    {pid: 400, ppid: 999, cpu: 0.0, name: "stranger"}
]
let prot: list<int> = (protect-set $tree 100)
assert equal ($prot | sort) [10 50 60 100 200 201 300]
assert equal (400 in $prot) false

# 11. the descendants fixpoint: the whole subtree, no strangers.
let args_rows: list<ArgsRow> = [
    {pid: 1, ppid: 0, cpu: 0.0, args: "root"}
    {pid: 2, ppid: 1, cpu: 0.0, args: "a"}
    {pid: 3, ppid: 2, cpu: 0.0, args: "a-child"}
    {pid: 4, ppid: 1, cpu: 0.0, args: "b"}
    {pid: 5, ppid: 99, cpu: 0.0, args: "stranger"}
]
assert equal (descendants $args_rows 1 | sort) [1 2 3 4]

# 12. the island partition: idle unprotected islands die; a breathing
#     descendant holds its island back (the breather is named).
let isle_rows: list<ArgsRow> = [
    {pid: 10, ppid: 1, cpu: 0.0, args: "/x/zcode-cli --serve"}
    {pid: 20, ppid: 1, cpu: 0.0, args: "/x/zcode-cli --serve"}
    {pid: 21, ppid: 20, cpu: 50.0, args: "gradle build"}
    {pid: 30, ppid: 1, cpu: 5.0, args: "/x/zcode-cli --serve"}
    {pid: 40, ppid: 1, cpu: 0.0, args: "/usr/bin/idle-thing --wait"}
    {pid: 50, ppid: 1, cpu: 0.0, args: "/x/zcode-cli --serve"}
]
let scan: IslandScan = (island-partition $isle_rows [50])
assert equal ($scan.killable | get pid) [10]
assert equal $scan.held [{pid: 20, breatherPid: 21, breatherCpu: 50.0}]

# 13. the swap parse and the ollama model list.
assert equal (swap-used-mb "total = 4096.00M used = 2434.00M free = 1661.75M") 2434
let ollama_ps: string = "NAME ID SIZE PROCESSOR UNTIL\nnomic-embed-text:latest abc 274 MB 100% GPU 4 minutes from now\nqwen2.5:7b def 4.7 GB 100% GPU 4 minutes from now\n\n"
let loaded: list<string> = (loaded-models $ollama_ps)
assert equal $loaded ["nomic-embed-text:latest" "qwen2.5:7b"]
assert equal (droppable-models $loaded "nomic-embed") ["qwen2.5:7b"]
assert equal (droppable-models [] "nomic-embed") []

# 14. the receipt lines: dead / SURVIVED / respawn shapes, empty when nothing
#     was killed.
let ps2: list<PsRow> = [{pid: 3, ppid: 1, cpu: 0.0, name: "other"}]
assert equal (receipt-dead "islands" [1 2] $ps2) "islands: 2 killed → verified dead"
assert equal (receipt-dead "islands" [2 3] $ps2) "islands: SURVIVED — still alive: 3"
assert equal (receipt-dead "islands" [] $ps2) ""
assert equal (receipt-respawn "AppleSpell" [7] "AppleSpell" $ps2) "AppleSpell: killed → gone — respawns on demand"
assert equal (receipt-respawn "AppleSpell" [7] "other" $ps2) "AppleSpell: killed → already respawned — pids 3"
assert equal (receipt-respawn "AppleSpell" [] "AppleSpell" $ps2) ""
assert equal (login-receipt 1163 0) "LoginItems: killed → not yet respawned after 2s — launchd brings it back"
assert equal (login-receipt 1163 400) "LoginItems: killed → respawned at 400 MB — was 1163 MB"

# 15. the signal outcomes: gone vs refused.
assert equal (signal-outcomes [1 2 3] [2]) {gone: [1, 3], refused: [2]}
assert equal (signal-outcomes [1] []) {gone: [1], refused: []}

print "test_ram_clean ok"
