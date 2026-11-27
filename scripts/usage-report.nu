#!/Users/lattenero/.local/bin/nu-nightly
# usage-report.nu — which fleet scripts actually RUN, so the phone's commands
# are chosen by usage and not by taste. Three sources, each with its own
# honesty about dates:
#
#   agent     the ZCode CLI's own tool calls, last N days (one SQL scan of
#             ~/.zcode/cli/db/db.sqlite: the parts that mention a script path
#             or `fleet <verb>`)
#   terminal  the owner's nushell history.txt — ALL TIME (the file has no
#             timestamps)
#   phone     the bot's palette ledger (command-usage.json) — ALL TIME
#   auto      a LaunchAgent runs it: scheduled work needs no phone command
#
#   fleet usage-report [--days 14] [--top 12]
use ../lib/usage-report.nu *
use ../lib/fleet.nu *

const DB: string = '/Users/lattenero/.zcode/cli/db/db.sqlite'
const HISTORY: string = '/Users/lattenero/Library/Application Support/nushell/history.txt'
const LEDGER: string = '/Users/lattenero/.zcode/bot-kotlin/command-usage.json'
const PLISTS: string = '/Users/lattenero/Library/LaunchAgents'

# The hub root rides the script's own path (`path self` is parse-time only;
# $env.FILE_PWD is the caller's PWD, measured 24/11 — it pointed at another
# repo and the verb table came back empty).
const SELF: path = (path self)

def main [--days: int = 14, --top: int = 12]: nothing -> nothing {
    let hub: path = (($SELF | path expand) | path dirname | path dirname)
    let commands: list<Command> = (verb-table (aliases ($nu.home-dir | path join '.agents/skills/fleet-healthcheck/scripts/healthcheck.nu')) (verbs (glob ($hub | path join 'scripts' '*.nu'))))
    let names: list<string> = ($commands | get verb)

    let since: int = (((date now | format date '%s' | into int)) - ($days * 86400))
    let query: string = (count-query $names $since)
    let agent: list<record<name: string, count: int>> = (agent-counts (^sqlite3 -json $DB $query | from json | first) $names)
    let terminal: list<record<name: string, count: int>> = (text-counts (open --raw $HISTORY) $names)
    let phone: list<record<name: string, count: int>> = (phone-counts (open --raw $LEDGER | from json) $names)

    let plist_texts: list<string> = (glob ($PLISTS | path join '*.plist') | each {|p| open --raw $p })
    let scheduled: list<string> = ($names | where {|n| ($plist_texts | any {|t| scheduled? $t $n})})

    let rows: list<Use> = (join-uses $names $agent $terminal $phone $scheduled | first $top)

    print $"== fleet usage — last ($days) days \(agent\), all time \(terminal, phone\) =="
    print ''
    $rows | table --index false | print
    print ''
    print 'auto = a LaunchAgent already runs it (a phone command adds nothing)'
    print 'terminal and phone carry NO dates: their files have no timestamps — the columns are all-time'
}
