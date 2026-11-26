#!/opt/homebrew/bin/nu
# brain-baseline.nu — the "before" numbers of the denotational-engine plan.
# READ-ONLY against its sources. Two legs: the LANGUAGE leg (per language per
# ISO week: writes, oracle runs, oracle failures, law denials — how well the
# agent writes each language) and the RUMBO leg (the replay of the owner's
# cancelled turns, tables A-E). Every definition the numbers rest on prints
# under its table.
#
#   fleet brain-baseline [--weeks 8] [--db ..] [--log ..] [--denials ..]
use ../lib/brain-baseline.nu *
use ../nushell-fp/mods/proc.nu fold-stderr

const DB: string = '/Users/lattenero/.zcode/cli/db/db.sqlite'
const LOG: string = '/Users/lattenero/.zcode/bot-kotlin/logs/launchd.out.log'
const DENIALS: string = '/Users/lattenero/.zcode/hooks/state/denials.tsv'

# The render laws: compact tables, one line per row. Colors go only with an
# explicit strip (measured 0.117.0: an empty color_config keeps them), so the
# numbers paste clean anywhere.
$env.config.table.mode = 'compact'

# A rendered table, printed without colors.
def plain []: string -> nothing {
    ansi strip | print
}

# The file's text; a missing source reads as empty.
def read-text [path: string]: nothing -> string {
    if ($path | path exists) { open --raw $path } else { '' }
}

# One query: the database opens with sqlite3 -readonly, never otherwise.
def query [db: string, sql: string]: nothing -> table {
    let res: record = (do { ^sqlite3 -readonly -json $db $sql } | complete)
    if $res.exit_code != 0 {
        print -e (fold-stderr $res | str trim | str substring 0..300)
        exit 1
    }
    let rows: table = (if ($res.stdout | str trim | is-empty) { [] } else { $res.stdout | from json })
    $rows
}

# Everything the language table's numbers rest on, read off the same tables
# the core computes with (the honest-indicators law).
def print-definitions [parts: list<Part>, ledger: list<Ledger>, zone: string]: nothing -> nothing {
    let exts: string = ($LANGS | each {|l| $'($l.lang) [($l.exts | str join " ")]' } | str join ' · ')
    let fails: table = ($parts | where status == error)
    let retired: int = ($fails | where {|p| (denial-line? $p.err) and ((denial-of $p.err) == null) } | length)
    let sub: list<Part> = ($parts | where sub == 1)
    let subDenials: int = ($sub | where {|p| (denial-of $p.err) != null } | length)
    let unguarded: string = (if (($sub | length) > 0) and ($subDenials == 0) { ' — no hook denial among them: law denials only see the guarded sessions' } else { '' })
    print 'Definitions — every number above rests on these:'
    print $'  weeks     ISO weeks read in ($zone); the last one is partial'
    print $'  write     a COMPLETED Edit/Write/MultiEdit part, by extension: ($exts)'
    $LANGS | each {|l| print $'  oracle    ($l.lang): a completed Bash step whose command matches /($l.oracle)/' }
    $MARKERS | group-by lang --to-table | rename lang markers | each {|g|
        # the escape character prints as <esc>: an invisible byte must not ride into a pasted table
        let shown: string = ($g.markers | each {|m| $m.kind + ' "' + ($m.text | str replace -a (char --integer 27) '<esc>') + '"' } | str join ' | ')
        print ('  fails     ' + $g.lang + ': the output carries ' + $shown)
    }
    print '  status    a failing run is `completed` with the failure inside state.output; `error` is the harness (cancelled, plan mode, a hook) and no exit code is stored'
    print $'  law       ($ledger | length) ledger lines, authoritative from its first line ($ledger | get -o 0.ts | default 'none'); before it, stored parts whose error STARTS as a hook line, by the rule substrings the three hooks carry today; shell counts as nu. ($retired) stored denials carry a rule no hook has today — not counted'
    print $'  unguarded ($sub | length) of ($parts | length) tool steps came from subagent sessions and ($subDenials) of them carry a hook denial($unguarded)'
}

def main [
    --weeks: int = 8               # how many ISO weeks, oldest first
    --zone: string = 'local'       # where the weeks are read: local, or an offset like -03:00
    --db: string = $DB             # the CLI session store, opened read-only
    --log: string = $LOG           # the daemon log: one `live view sealed` line per turn
    --denials: string = $DENIALS   # the hooks' denial ledger
]: nothing -> nothing {
    let nowMs: int = ((date now) | into int) // 1_000_000
    let weeks: list<Week> = (recent-weeks $nowMs $zone $weeks)

    # ── 1. language ────────────────────────────────────────────────────────
    # one curve per language: its eight weeks, side by side
    let sinceMs: int = ($nowMs - ($weeks | length) * 7 * 86400_000)
    let parts: list<Part> = (query $db (parts-query $sinceMs))
    let ledger: list<Ledger> = (ledger-rows (read-text $denials))
    let cells: table = (language-table (tallies-of $parts $ledger $zone) $weeks)
    print $"== 1. LANGUAGE — ($weeks | length) ISO weeks · ($parts | length) tool parts · ($ledger | length) ledger lines =="
    $LANGS | each {|lang|
        print $"\n($lang.lang) — files [($lang.exts | str join ' ')]"
        $cells | where lang == $lang.lang | reject lang | table --index false --width 150 | plain
    }
    print-definitions $parts $ledger $zone

    # ── 2. rumbo ───────────────────────────────────────────────────────────
    print "\n== 2. RUMBO — the replay of the owner's cancelled turns =="
    let seals: table = (parse-seals (read-text $log))
    let sids: list<string> = (if ($seals | is-empty) { [] } else { $seals | get sid | uniq })
    let steps: table = (if ($sids | is-empty) { [] } else { query $db (steps-query $sids) })
    let requests: table = (if ($sids | is-empty) { [] } else { query $db (requests-query $sids) })
    print $"sealed turns in the log: ($seals | length) · sessions: ($sids | length) · tool steps loaded: ($steps | length) · user messages: ($requests | length)"

    let rows: table = (replay-rows $seals $steps $requests)
    let matched: int = ($rows | length)
    let killedN: int = ($rows | where reason == cancelled | length)
    let okN: int = ($rows | where reason == success | length)
    let base: float = (base-rate $killedN $matched)
    let basePct: float = (($base * 100) | math round --precision 1)
    print $"turns matched to real steps: ($matched) · cancelled ($killedN) = ($basePct) in 100 · success ($okN)"

    print "\n=== A. Where the cancel lands (step count of the cancelled turns) ==="
    cancel-landing $rows $killedN | table -e | plain

    print "\n=== B. Cancelled vs success — the measured facts ==="
    population-table $rows | table -e -w 260 | plain

    print $"\n=== C. Discrimination — base rate of a cancelled turn = ($basePct) in 100 · lift 1.0 means no signal ==="
    metric-table $rows $base | select signal at flagged cancelled_in_flagged precision_pct lift recall_pct coverage_pct | table -e -w 260 | plain

    print "\n=== D. Sample of cancelled turns — for a human read of the cause (every 4th) ==="
    $rows | where reason == cancelled
    | sort-by sid
    | enumerate
    | where index mod 4 == 0
    | each {|pair| sample-line $pair }
    | str join "\n"
    | print

    print "\n=== E. What the cancel actually was — mechanical causes ==="
    cause-table $rows | table -e -w 260 | plain
}
