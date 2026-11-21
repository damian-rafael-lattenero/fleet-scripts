#!/opt/homebrew/bin/nu
# ram-clean.nu — the RAM relief routine the owner asked for twice on 20/11.
# Default: PLAN ONLY (measures, names every candidate, frees nothing).
# --clean executes, one decision per line, stdout AND the run log:
#   1. idle Task-Island zcode-cli processes — cpu < 1%, never my own
#      ancestry and never my session's own helper descendants
#   2. the qwen2.5:1.5b extraction model unloaded from ollama RAM (NEVER
#      deleted — the brain's memory worker reloads it on demand)
#   3. AppleSpell killed (macOS growth bug; respawns small on demand)
#   4. idle gradle daemons killed (respawn on the next build; a BUILDING
#      daemon breathes above the idle threshold and is never touched)
# Every run appends to ~/Library/Logs/ram-clean.log.

const LOG_FILE: string = "/Users/lattenero/Library/Logs/ram-clean.log"
const QWEN: string = "qwen2.5:1.5b"
# cpu percent under which a process counts as idle. A live turn or an
# active build breathes well above this; abandoned things sit at 0.
const IDLE_CPU: float = 1.0

def emit [line: string]: nothing -> nothing {
    print $line
    $"($line)\n" | save --append --raw $LOG_FILE
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

# The full ps snapshot as records (the builtin ps lacks pcpu and args).
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

def main [--clean]: nothing -> nothing {
    let stamp: string = (date now | format date "%Y-%m-%d %H:%M:%S")
    let ps: table = (snap)
    let prot: list<int> = (protect-set $ps)
    let freeBefore: int = (free-pct)
    let swapBefore: string = (swap-line)
    emit $"== ram-clean ($stamp) — clean=($clean) =="
    emit $"before: free ($freeBefore)% · swap ($swapBefore)"

    # 1. Task-Island zcode-cli processes.
    let isles: table = (islands $ps $prot)
    emit $"islands: ($isles | length) idle zcode-cli candidates — pids ($isles | get pid | str join ', ')"
    if $clean and (($isles | length) > 0) {
        kill ...($isles | get pid)
        emit $"killed islands: ($isles | get pid | str join ', ')"
    }

    # 2. the extraction model's resident RAM (stop != delete; it reloads).
    let ops: record = (do { ollama ps } | complete)
    let qwenLoaded: bool = ($ops.stdout | lines | any {|l| $l =~ $QWEN })
    let qstate: string = (if $qwenLoaded { "loaded in RAM" } else { "not loaded" })
    emit $"qwen ($QWEN): ($qstate)"
    if $clean and $qwenLoaded {
        let stop: record = (do { ollama stop $QWEN } | complete)
        emit $"ollama stop ($QWEN): exit ($stop.exit_code)"
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
