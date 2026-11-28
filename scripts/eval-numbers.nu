#!/opt/homebrew/bin/nu
# eval-numbers.nu — the plan's three numbers as eval-ledger rows (U22).
# first-pass: per tracked language (nu, kt, hs — TypeScript stays out), the
# last FULL ISO week's oracle runs and failures, read off the session store
# through lib/brain-baseline.nu's language leg. rumbo: the cancel replay over
# the whole sealed log. The rows POST to the brain's /eval/record — the ledger
# keeps ONE writer, the brain — and /learn shows them.
#
#   fleet eval-numbers [--dry-run] [--weeks 2] [--brain http://127.0.0.1:8765]
# Exit 1 when a row is refused or the brain is down: a number that did not
# land is not a number.

use ../lib/brain-baseline.nu *
use ../lib/eval-numbers.nu *
use ../nushell-fp/mods/proc.nu fold-stderr

const DB: string = '/Users/lattenero/.zcode/cli/db/db.sqlite'
const LOG: string = '/Users/lattenero/.zcode/bot-kotlin/logs/launchd.out.log'
const DENIALS: string = '/Users/lattenero/.zcode/hooks/state/denials.tsv'

$env.config.table.mode = 'compact'

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
    if ($res.stdout | str trim | is-empty) { [] } else { $res.stdout | from json }
}

def main [
    --dry-run            # print the rows as JSON, POST nothing
    --weeks: int = 2     # the language leg loads this many; the row uses the last FULL one
    --zone: string = 'local'
    --db: string = $DB
    --log: string = $LOG
    --denials: string = $DENIALS
    --brain: string = 'http://127.0.0.1:8765'
]: nothing -> nothing {
    let nowMs: int = ((date now) | into int) // 1_000_000
    let weeks: list<Week> = (recent-weeks $nowMs $zone $weeks)
    let sinceMs: int = ($nowMs - ($weeks | length) * 7 * 86400_000)

    # ── first-pass: the language leg, the LAST FULL week ──
    let parts: list<Part> = (query $db (parts-query $sinceMs))
    let ledger: list<Ledger> = (ledger-rows (read-text $denials))
    let cells: table = (language-table (tallies-of $parts $ledger $zone) $weeks)
    let fullWeek: string = ($weeks | first | get week)
    let fpRows: list<MetricRun> = (first-pass-rows $cells $fullWeek)

    # ── rumbo: the whole sealed log ──
    let seals: table = (parse-seals (read-text $log))
    let sids: list<string> = (if ($seals | is-empty) { [] } else { $seals | get sid | uniq })
    let steps: table = (if ($sids | is-empty) { [] } else { query $db (steps-query $sids) })
    let requests: table = (if ($sids | is-empty) { [] } else { query $db (requests-query $sids) })
    let turns: table = (replay-rows $seals $steps $requests)
    let rRow: MetricRun = (rumbo-row $turns)

    let rows: list<MetricRun> = ($fpRows | append $rRow)
    if $dry_run {
        print ($rows | to json -r)
        return
    }

    print $"== eval-numbers: ($fpRows | length) first-pass rows + 1 rumbo row → ($brain) =="
    let failed: bool = ($rows | each {|row|
        let res: any = (try {
            http post --content-type application/json $"($brain)/eval/record" ($row | to json -r)
        } catch {|e| {error: ($e.msg | str substring 0..200)} })
        if ($res | get -o suite? | default '') == $row.suite {
            print $"✅ ($row.suite) ($row.passed)/($row.total) gate ($row.gate) — recorded"
            false
        } else {
            print $"❌ ($row.suite) — refused: (($res | get -o error? | default 'no answer'))"
            true
        }
    } | any {|f| $f })

    if $failed { exit 1 }
}
