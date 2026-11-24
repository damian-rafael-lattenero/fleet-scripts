# usage-report.nu — the report's pure half: the SQL it builds (executions, not
# mentions), the three count sources (agent / terminal / phone), the scheduled
# flag and the ranking. Fixtures are literal; no database, no files.
use std/assert
use ../../lib/usage-report.nu *

# 1. count-query: one column per name, both spellings, and ONLY Bash calls —
#    a Write part carries the script's source and would count an edit as a run.
let q: string = (count-query ['ram-clean' 'brain'] 1000)
assert ($q | str contains "json_extract(data,'$.state.input.command')") "the command field is the evidence"
assert ($q | str contains "json_extract(data, '$.tool') = 'Bash'") "only Bash calls count"
assert ($q | str contains 'as "ram-clean"') "one column per name"
assert ($q | str contains "'/brain.nu'") "the path spelling"
assert ($q | str contains "'fleet brain '") "the verb spelling (trailing space: the boundary)"
assert ($q | str contains 'time_created > 1000') "the window rides the query"

# 2. agent-counts: a column the query did not answer is zero, never null.
let agent: list<record<name: string, count: int>> = (agent-counts {ram-clean: 7} ['ram-clean' 'brain'])
assert equal ($agent | where name == ram-clean | get 0.count) 7
assert equal ($agent | where name == brain | get 0.count) 0

# 3. text-counts: a history line counts once, both spellings, and a near name
#    never steals another's count (brain vs brain-eval).
let history: string = ([
    'fleet brain "what is kap"'
    'fleet brain-eval'
    'nu /Users/lattenero/Scripts/scripts/brain.nu --recent'
    'fleet ram-clean --clean'
] | str join (char nl))
let t: list<record<name: string, count: int>> = (text-counts $history ['brain' 'brain-eval' 'ram-clean'])
assert equal ($t | where name == brain | get 0.count) 2 "two literal brain lines (the third is brain.nu, counted under brain too)"
assert equal ($t | where name == brain-eval | get 0.count) 1
assert equal ($t | where name == ram-clean | get 0.count) 1

# 4. phone-counts: the ledger keys are palette names (snake), the verbs kebab.
let ledger: record = {counts: {ram_clean: 3, fleet_healthcheck: 5}}
let p: list<record<name: string, count: int>> = (phone-counts $ledger ['ram-clean' 'healthcheck' 'brain'])
assert equal ($p | where name == ram-clean | get 0.count) 3
assert equal ($p | where name == healthcheck | get 0.count) 5
assert equal ($p | where name == brain | get 0.count) 0

# 5. scheduled?: a plist that names the script (or the verb) is automatic.
assert equal (scheduled? '<string>/Users/lattenero/Scripts/scripts/rag-nightly.nu</string>' 'rag-nightly') true
assert equal (scheduled? '<string>fleet healthcheck</string>' 'healthcheck') true
assert equal (scheduled? '<string>/usr/bin/true</string>' 'brain') false

# 6. join-uses: the owner's own use outweighs agent volume (a terminal line
#    counts 10x, a phone command 20x) and the flag is the scheduled list.
let rows: list<Use> = (join-uses
    ['a' 'b' 'c']
    [{name: a, count: 1} {name: b, count: 0} {name: c, count: 0}]
    [{name: a, count: 0} {name: b, count: 0} {name: c, count: 1}]
    [{name: a, count: 0} {name: b, count: 1} {name: c, count: 0}]
    ['c'])
assert equal ($rows | first | get name) 'b' "a phone command weighs most"
assert equal (($rows | get name) | last) 'a' "agent-only volume ranks last"
assert equal ($rows | where name == c | get 0.auto) true
assert equal ($rows | where name == a | get 0.auto) false

print "lib/usage-report ok"
