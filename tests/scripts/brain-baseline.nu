# brain-baseline.nu — the script end to end, on a fixture session store: the
# SQL really runs, the failure flags come back from the database, and both
# legs print what the fixtures put in. The three sources ride flags, so the
# test builds its own and nothing touches ~/.zcode.
# covers: /Users/lattenero/Scripts/scripts/brain-baseline.nu
use std/assert
use /Users/lattenero/Scripts/nushell-fp/mods/proc.nu fold-stderr

const SELF: path = (path self)
const ESC: string = (char --integer 27)

let HUB: path = ($SELF | path expand | path dirname | path dirname | path dirname)

# A SQL string literal.
def lit [s: string]: nothing -> string {
    "'" + ($s | str replace -a "'" "''") + "'"
}

# A row of the session store, as an INSERT (a message row carries no message_id).
def row [table: string, id: string, mid: string, sid: string, t: int, data: record]: nothing -> string {
    let partMid: string = (if ($mid | is-empty) { '' } else { ', message_id' })
    let valMid: string = (if ($mid | is-empty) { '' } else { ', ' + (lit $mid) })
    let head: string = ('insert into ' + $table + ' (id, session_id, time_created, data' + $partMid + ') values (')
    $head + (lit $id) + ', ' + (lit $sid) + ', ' + ($t | into string) + ', ' + (lit ($data | to json -r)) + $valMid + ');'
}

# A tool part, as the CLI persists it.
def tool [id: string, sid: string, t: int, name: string, status: string, input: record, output: string, err: string]: nothing -> string {
    row 'part' $id 'm1' $sid $t {type: 'tool', tool: $name, state: {status: $status, input: $input, output: $output, error: $err}}
}

# The language curves as the script renders them: one record per table line,
# the language taken from the curve's own title line above it.
def cells [out: string]: nothing -> table {
    let rows: table = ($out | lines | reduce --fold {lang: '', rows: []} {|line, acc|
        let title: string = ($line | parse -r '^(?<lang>\w+) — files \[' | get -o 0.lang | default '')
        let lang: string = (if ($title | is-empty) { $acc.lang } else { $title })
        let hits: table = ($line | parse -r '\s*(?<week>\d{4}-W\d{2})\s*│\s*(?<monday>[\d-]+)\s*│\s*(?<writes>\d+)\s*│\s*(?<runs>\d+)\s*│\s*(?<fails>\d+)\s*│\s*(?<denials>\d+)\s*│\s*(?<per>[\d.]+)\s*$')
        {lang: $lang, rows: ($acc.rows | append ($hits | each {|h| $h | insert lang $lang }))}
    } | get rows)
    $rows
}

# One cell of the rendered grid, by week and language.
def cell [out: string, week: string, lang: string]: nothing -> any {
    cells $out | where {|c| ($c.week == $week) and ($c.lang == $lang) } | get 0
}

# The fixture lives in the current ISO week and the one before, in UTC.
let nowMs: int = ((date now) | into int) // 1_000_000
let weekday: int = ($nowMs * 1_000_000 | into datetime | format date '%u' | into int)
let mondayMs: int = ($nowMs - ($nowMs mod 86400_000) - ($weekday - 1) * 86400_000)
let cur: int = ($mondayMs + 36 * 3600_000)                 # Tuesday noon
let prev: int = ($cur - 7 * 86400_000)
let older: int = ($cur - 14 * 86400_000)
def week-label [tMs: int]: nothing -> string {
    $tMs * 1_000_000 | into datetime | format date '%G-W%V'
}
def iso [tMs: int]: nothing -> string {
    $tMs * 1_000_000 | into datetime | format date '%FT%T%.3fZ'
}

# A `live view sealed` line of the daemon log, as the bot writes it.
def seal-line [tMs: int, reason: string]: nothing -> string {
    (iso $tMs) + ' INFO  d.l.b.c.LivePublisher [] live view sealed: taskId=sess_r reason=' + $reason + ' thought=1 tools=2 answer=1 chars'
}

const TYPING: string = 'PreToolUse:Edit hook error: [command hidden]: ⛔ Typing law — params WITHOUT a type: x'
const RETIRED: string = '⛔ Nushell law (AGENTS.md): every shell command goes through Nushell.'
const BLIND: string = ('PreToolUse:Bash hook error: [command hidden]: ⛔ Reactive law: blind sl' + 'eep 30 is FORBIDDEN')
const NU_ERROR: string = ('before ' + $ESC + '[31mError:' + $ESC + '[0m nu::parser::parse_mismatch' + ' after')
let seal: int = ($cur + 6 * 3600_000)                     # the rumbo fixture: a sealed, cancelled turn
let statements: string = ([
    'create table part (id text primary key, message_id text not null, session_id text not null, time_created integer not null, data text not null);'
    'create table message (id text primary key, session_id text not null, time_created integer not null, data text not null);'
    # the current week
    (tool 'p01' 's1' $cur 'Edit' 'completed' {file_path: '/p/a.nu', old_string: 'a', new_string: 'b'} '' '')
    (tool 'p02' 's1' ($cur + 1000) 'Write' 'completed' {file_path: '/p/B.KT', content: 'x'} '' '')
    (tool 'p03' 's1' ($cur + 2000) 'Edit' 'error' {file_path: '/p/c.nu', old_string: 'a', new_string: 'b'} '' $TYPING)
    (tool 'p04' 's1' ($cur + 2500) 'Edit' 'error' {file_path: '/p/c.nu', old_string: 'a', new_string: 'b'} '' $RETIRED)
    (tool 'p05' 's1' ($cur + 3000) 'Bash' 'completed' {command: './gradlew test'} 'BUILD FAILED in 3s' '')
    (tool 'p06' 's1' ($cur + 4000) 'Bash' 'completed' {command: 'nu tests/x.nu'} 'all good' '')
    (tool 'p07' 's1' ($cur + 5000) 'Bash' 'completed' {command: 'cat build.gradle.kts'} 'plugins {}' '')
    (tool 'p08' 'sess_subagent_1' ($cur + 6000) 'Bash' 'completed' {command: 'ls'} '' '')
    # the week before
    (tool 'p09' 's1' $prev 'Write' 'completed' {file_path: '/p/d.tsx', content: 'x'} '' '')
    (tool 'p10' 's1' ($prev + 1000) 'Edit' 'completed' {file_path: '/p/a.nu', old_string: 'a', new_string: 'b'} '' '')
    (tool 'p11' 's1' ($prev + 2000) 'Bash' 'completed' {command: 'npx tsc --noEmit'} 'src/a.ts(1,1): error TS2322: nope' '')
    (tool 'p12' 's1' ($prev + 3000) 'Bash' 'completed' {command: 'cabal build'} 'Up to date' '')
    (tool 'p13' 's1' ($prev + 4000) 'Bash' 'completed' {command: 'nu x.nu'} $NU_ERROR '')
    (tool 'p14' 's1' ($prev + 5000) 'Bash' 'error' {command: 'x'} '' $BLIND)
    # a week no hook had been born in: nothing but noise
    (tool 'p15' 's1' $older 'Bash' 'completed' {command: 'cat x.nu'} '' '')
    # the rumbo fixture: a session's FIRST seal, cancelled, with its two read-only
    # steps and its request — the turn has no previous seal, so no duration
    (tool 'p16' 'sess_r' ($seal - 600000) 'Read' 'completed' {file_path: '/g.kt'} '' '')
    (tool 'p17' 'sess_r' ($seal - 300000) 'Glob' 'completed' {pattern: '**/*.kt'} '' '')
    (row 'message' 'm1' '' 'sess_r' ($seal - 60000) {role: 'user'})
    (row 'part' 't1' 'm1' 'sess_r' ($seal - 60000) {type: 'text', text: 'do the thing'})
] | str join (char nl))
let sql: string = ($statements + (char nl))

let tmp: path = ($"($env.TMPDIR? | default /tmp)/brain-baseline-(random uuid)")
mkdir $tmp
let db: path = ($tmp | path join 'db.sqlite')
let logPath: path = ($tmp | path join 'launchd.out.log')
let ledgerPath: path = ($tmp | path join 'denials.tsv')
let script: path = ($HUB | path join 'scripts' 'brain-baseline.nu')

$sql | ^sqlite3 $db
# the ledger opens two hours into the current week: from then on it is the authority
([
    ((iso ($cur + 7200_000)) + "\ts1\tnushell-typing\tblind-sleep\tnu\t/p/a.nu")
    ((iso ($cur + 10800_000)) + "\ts1\tnushell-law\tblind-sleep\tshell\tprint 1")
] | str join (char nl)) | save --force $ledgerPath
([
    (seal-line $seal 'cancelled')
    (seal-line ($seal + 1800_000) 'success')
] | str join (char nl)) | save --force $logPath

let res: record = (do { ^$nu.current-exe $script --db $db --log $logPath --denials $ledgerPath --weeks 3 --zone '+00:00' } | complete)
rm -rf $tmp
assert equal $res.exit_code 0 (fold-stderr $res)
assert equal (fold-stderr $res | str trim) '' "the script is silent on stderr"
let out: string = $res.stdout

# 1. the language leg: every cell the fixtures put in, zeros where they did not.
assert str contains $out '== 1. LANGUAGE — 3 ISO weeks · 15 tool parts · 2 ledger lines =='
assert equal ((cells $out) | length) 12 "3 weeks x 4 languages"
let wCur: string = (week-label $cur)
let wPrev: string = (week-label $prev)
let wOlder: string = (week-label $older)
assert equal (cell $out $wCur 'nu' | select writes runs fails denials per) {writes: '1', runs: '1', fails: '0', denials: '3', per: '3000.00'}
assert equal (cell $out $wCur 'kt' | select writes runs fails denials) {writes: '1', runs: '1', fails: '1', denials: '0'}
assert equal (cell $out $wCur 'ts' | select writes runs fails denials per) {writes: '0', runs: '0', fails: '0', denials: '0', per: '0.00'}
assert equal (cell $out $wPrev 'nu' | select writes runs fails denials per) {writes: '1', runs: '1', fails: '1', denials: '1', per: '1000.00'}
assert equal (cell $out $wPrev 'ts' | select writes runs fails denials) {writes: '1', runs: '1', fails: '1', denials: '0'}
assert equal (cell $out $wPrev 'hs' | select writes runs fails denials) {writes: '0', runs: '1', fails: '0', denials: '0'}
assert equal (cell $out $wPrev 'kt' | select writes runs fails denials) {writes: '0', runs: '0', fails: '0', denials: '0'}
assert equal (cell $out $wOlder 'nu' | select writes runs fails denials) {writes: '0', runs: '0', fails: '0', denials: '0'}

# 2. the definitions under the table: the measured caveats, in words.
assert str contains $out 'a failing run is `completed` with the failure inside state.output'
assert str contains $out '1 stored denials carry a rule no hook has today — not counted'
assert str contains $out '1 of 15 tool steps came from subagent sessions and 0 of them carry a hook denial'
assert str contains $out (iso ($cur + 7200_000))

# 3. the rumbo leg: the sealed turn matched its two steps, and it was cancelled.
assert str contains $out 'sealed turns in the log: 2 · sessions: 1 · tool steps loaded: 2 · user messages: 1'
assert str contains $out 'turns matched to real steps: 1 · cancelled 1 = 100.0 in 100 · success 0'
assert str contains $out 'do the thing'
assert str contains $out '│ cancelled │' "the populations name their reason"
assert str contains $out 'min=? · sess_r' "a turn with no duration says so instead of counting from the epoch"

# 4. read-only by construction: the one sqlite call is the readonly one, and
#    nothing in the script writes, moves or removes a file.
let src: string = (open --raw $script)
assert equal ($src | split row '^sqlite3' | length) 2 "exactly one sqlite call"
assert str contains $src '^sqlite3 -readonly -json'
assert equal ($src | lines | where {|l| ($l =~ '\| save') or ($l =~ '\| rm\b') or ($l =~ '\bmkdir\b') or ($l =~ '\bcp\b') or ($l =~ '\bmv\b') } | length) 0

print "scripts/brain-baseline ok — both legs on a fixture store, sources read-only"
