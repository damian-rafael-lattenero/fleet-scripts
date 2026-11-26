# brain-baseline.nu core — the "before" numbers of the denotational-engine
# plan, as data. Two pure legs; the script keeps the effects (the sqlite
# reads, the daemon log, the denial ledger, the printing).
#
#   LANGUAGE  how well the agent writes each language, week by week: writes,
#             oracle runs, oracle failures, law denials
#   RUMBO     the replay of the owner's cancelled turns (tables A-E)
#
# Everything here answers from its arguments alone.

# ── shared ──────────────────────────────────────────────────────────────────

# The edit-shaped tools (a write to a file).
export const EDIT_TOOLS: list<string> = [Edit Write MultiEdit]

# An epoch-ms instant from an ISO timestamp.
export def epoch-ms [ts: string]: nothing -> int {
    $ts | into datetime | format date '%s%3f' | into int
}

# ══ LANGUAGE LEG ═════════════════════════════════════════════════════════════

# A tracked language: the file extensions that make a write its own, and the
# oracle command that verifies it (a regex on a Bash command; one step may run
# several languages' oracles).
export type Lang = record<lang: string, exts: list<string>, oracle: string>

# One tool part as the core sees it: the slim columns the one scan hands over.
export type Part = record<sid: string, t: int, tool: string, status: string, cmd: string, path: string, err: string, sub: int, fail_kt: int, fail_ts: int, fail_hs: int, fail_nu: int>

# One line of the hooks' denial ledger (denials.tsv).
export type Ledger = record<ts: string, sid: string, hook: string, rule: string, language: string, target: string>

# A failure marker in an oracle's output. `has` = anywhere in the output,
# `bol` / `eol` = at the start / end of a line, `digit` = right after a digit,
# `glob` = the text is the whole SQLite GLOB pattern.
export type Marker = record<lang: string, kind: string, text: string>

# What one part, or one ledger line, adds to one (language, week) cell.
export type Tally = record<lang: string, week: string, writes: int, oracle_runs: int, oracle_fails: int, law_denials: int>

# One ISO week of the grid: its label and its Monday.
export type Week = record<week: string, monday: string>

# One cell of the language leg.
export type Cell = record<week: string, monday: string, lang: string, writes: int, oracle_runs: int, oracle_fails: int, law_denials: int, denials_per_1000_writes: float>

# An oracle is a COMMAND: it stands right after a command separator, optional
# env assignments and an optional directory (`cd x && ./gradlew`). Reading
# about it is not running it (`cat build.gradle.kts`, `grep "detekt"`). The one
# quote that opens a command is a shell's `-c '...'` wrapper.
const CMD_START: string = '(?m)(?:^|[;&|({\n]|-{1,2}\w*c\w*\s+[\x22\x27])\s*\^?(?:[A-Za-z_][\w.]*=(?:"[^"]*"|\x27[^\x27]*\x27|\S*)\s+)*'
const DIR_PREFIX: string = '[\w.$@~(){}<>/+\-]*/?'
const RUNS_FILE: string = ($CMD_START + $DIR_PREFIX + '(?:nu|nu-nightly)\s+(?:-{1,2}[\w-]+\s+)*\S+\.nu\b')
const RUNS_CHECK: string = ($CMD_START + $DIR_PREFIX + 'nu-check\b')
const RUNS_PATH: string = ($CMD_START + '(?:\.{1,2}/|~/|/)[^\s\x22\x27]*\.nu\b')
const VIA_NPX: string = '(?:(?:npx|bunx)\s+|pnpm\s+exec\s+|yarn\s+dlx\s+|npm\s+exec\s+)?'

export const LANGS: list<Lang> = [
    {lang: 'nu', exts: [nu], oracle: ($RUNS_FILE + '|' + $RUNS_CHECK + '|' + $RUNS_PATH)}
    {lang: 'kt', exts: [kt kts], oracle: ($CMD_START + $DIR_PREFIX + '(?:gradlew?|kotlinc|detekt)\b')}
    {lang: 'ts', exts: [ts tsx js mjs], oracle: ($CMD_START + $DIR_PREFIX + $VIA_NPX + '(?:tsc|vitest|eslint|jest)\b|' + $CMD_START + '(?:npm|pnpm|yarn|bun)\s+(?:run\s+)?test\b')}
    {lang: 'hs', exts: [hs], oracle: ($CMD_START + $DIR_PREFIX + '(?:ghc|cabal|stack)\b')}
]

# MEASURED 2026-11-26 on the store: a failing run is `status = completed` with
# the failure text inside state.output. `status = error` is the harness's own
# (a cancelled step, plan mode, a hook denial) and no exit code is stored.
# The markers are the failure voices seen in real outputs, per oracle.
export const MARKERS: list<Marker> = [
    {lang: 'kt', kind: 'has', text: 'BUILD FAILED'}
    {lang: 'kt', kind: 'eol', text: 'FAILED'}
    {lang: 'kt', kind: 'bol', text: 'e: '}
    {lang: 'kt', kind: 'bol', text: 'error: '}
    {lang: 'kt', kind: 'has', text: 'Compilation error'}
    {lang: 'kt', kind: 'has', text: 'FAILURE: Build'}
    {lang: 'ts', kind: 'has', text: 'error TS'}
    {lang: 'ts', kind: 'has', text: 'FAIL '}
    {lang: 'ts', kind: 'digit', text: ' failed'}
    {lang: 'ts', kind: 'glob', text: '*([1-9]* errors*'}
    {lang: 'hs', kind: 'has', text: ': error:'}
    {lang: 'hs', kind: 'has', text: 'Failed to build'}
    {lang: 'hs', kind: 'has', text: 'FAIL '}
    {lang: 'hs', kind: 'has', text: '*** Exception:'}
    {lang: 'hs', kind: 'has', text: 'HasCallStack backtrace'}
    {lang: 'nu', kind: 'has', text: 'Error: nu::'}
    {lang: 'nu', kind: 'has', text: ('Error:' + (char --integer 27) + '[')}
]

# The anchored shape of a hook denial in the store: the hook's own line, or
# the fork's newer wrapper around it. Harness errors QUOTE hook text too (a
# failed Edit naming the line it could not find), so the line must START as one.
const DENIAL_HEAD: string = '^(PreToolUse:\w+ hook error: (\[command hidden\]: )?)?⛔ '

# A rule of one of the three denying hooks, by a substring of its real message
# (the Spanish-era spelling of the same law included).
export type RuleRow = record<hook: string, rule: string, needle: string>
export const DENIAL_RULES: list<RuleRow> = [
    {hook: 'nushell-typing', rule: 'def-without-signature', needle: 'WITHOUT an IO signature'}
    {hook: 'nushell-typing', rule: 'def-without-signature', needle: 'SIN firma'}
    {hook: 'nushell-typing', rule: 'untyped-params', needle: 'params WITHOUT a type'}
    {hook: 'nushell-typing', rule: 'hyphenated-variable', needle: 'hyphenated variables are INVALID'}
    {hook: 'nushell-typing', rule: 'hyphenated-variable', needle: 'variables con guión'}
    {hook: 'nushell-typing', rule: 'blind-sleep', needle: 'Reactive law — blind sleep'}
    {hook: 'nushell-typing', rule: 'blind-sleep', needle: 'Ley reactiva — sleep ciego'}
    {hook: 'nushell-law', rule: 'blind-sleep', needle: 'Reactive law: blind sleep'}
    {hook: 'nushell-law', rule: 'paren-let', needle: 'Paren-wrapped `let` law'}
    {hook: 'anti-pattern-lint', rule: 'paren-let', needle: 'paren-wrapped let'}
    {hook: 'anti-pattern-lint', rule: 'dispatch-chain', needle: 'dispatch-chain'}
    {hook: 'anti-pattern-lint', rule: 'orphaned-branch', needle: 'orphaned-branch'}
]

# The language that owns a file extension ('' when untracked).
export def language-of-ext [ext: string]: nothing -> string {
    $LANGS | where {|lang| $ext in $lang.exts } | get -o 0.lang | default ''
}

export def language-of [path: string]: nothing -> string {
    language-of-ext ($path | str lowercase | path parse | get -o extension | default '')
}

# The languages whose oracle a Bash command runs (often none).
export def oracle-of [cmd: string]: nothing -> list<string> {
    $LANGS | where {|lang| $cmd =~ $lang.oracle } | get lang
}

# True when a stored error STARTS as a hook denial — of any rule, the retired
# ones included (the ones no hook carries today are not law denials).
export def denial-line? [err: string]: nothing -> bool {
    $err =~ $DENIAL_HEAD
}

# The hook rule a stored error carries, or null when it is no denial of the
# three hooks.
export def denial-of [err: string]: nothing -> any {
    if not (denial-line? $err) { return null }
    $DENIAL_RULES | where {|r| $err | str contains $r.needle } | first
}

# The ISO week label (2026-W48) of an epoch-ms instant, read in `zone` (an
# offset like -03:00, or local).
export def week-of [tMs: int, zone: string]: nothing -> string {
    $tMs * 1_000_000 | into datetime | date to-timezone $zone | format date '%G-W%V'
}

# The Monday of that week, as MM-DD (the ISO week date with weekday 1).
export def monday-of [tMs: int, zone: string]: nothing -> string {
    ($tMs * 1_000_000 | into datetime | date to-timezone $zone | format date '%G-W%V') + '-1' | into datetime --format '%G-W%V-%u' | format date '%m-%d'
}

# The last `n` ISO weeks, oldest first (the last one is the week of `nowMs`).
export def recent-weeks [nowMs: int, zone: string, n: int]: nothing -> list<Week> {
    0..<$n
    | each {|i|
        let tMs: int = ($nowMs - $i * 7 * 86400_000)
        ({week: (week-of $tMs $zone), monday: (monday-of $tMs $zone)})
    }
    | reverse
}

# The ledger's rows; a line without its six fields is no denial record.
export def ledger-rows [text: string]: nothing -> list<Ledger> {
    $text
    | lines
    | each {|l| $l | split row "\t" }
    | where {|f| ($f | length) == 6 }
    | each {|f| ({ts: $f.0, sid: $f.1, hook: $f.2, rule: $f.3, language: $f.4, target: $f.5}) }
}

# One marker as a SQLite test over the output column `o` (never a `%` or `_`,
# which LIKE would read as wildcards).
def marker-sql [marker: Marker]: nothing -> string {
    let lit: string = "'" + ($marker.text | str replace -a "'" "''") + "'"
    match $marker.kind {
        'has' => ('instr(o, ' + $lit + ') > 0')
        'bol' => ("(o like (" + $lit + " || '%') or instr(o, char(10) || " + $lit + ') > 0)')
        'eol' => ("(o like ('%' || " + $lit + ') or instr(o, ' + $lit + ' || char(10)) > 0)')
        'digit' => ("o glob ('*[0-9]' || " + $lit + " || '*')")
        _ => ('o glob ' + $lit)
    }
}

# The language leg's ONE scan: every Edit/Write/MultiEdit/Bash part since
# `sinceMs`, each with the oracle-failure flags computed where the output
# lives. The parts are materialized once so the output is extracted once.
export def parts-query [sinceMs: int]: nothing -> string {
    let flags: string = ($LANGS | each {|lang|
        let tests: string = ($MARKERS | where lang == $lang.lang | each {|m| marker-sql $m } | str join ' or ')
        ('case when ' + $tests + ' then 1 else 0 end as fail_' + $lang.lang)
    } | str join ', ')
    let raw: string = ("session_id as sid, time_created as t, json_extract(data,'$.tool') as tool, "
        + "coalesce(json_extract(data,'$.state.status'), '') as status, "
        + "coalesce(json_extract(data,'$.state.input.command'), '') as cmd, "
        + "lower(coalesce(json_extract(data,'$.state.input.file_path'), '')) as path, "
        + "substr(coalesce(json_extract(data,'$.state.error'), ''), 1, 400) as err, "
        + "(session_id like 'sess_subagent%') as sub, "
        + "coalesce(json_extract(data,'$.state.output'), '') as o ")
    ('with p as materialized (select ' + $raw + 'from part where time_created > ' + ($sinceMs | into string)
        + " and json_extract(data,'$.type') = 'tool' and json_extract(data,'$.tool') in ('Edit','Write','MultiEdit','Bash')) "
        + 'select sid, t, tool, status, cmd, path, err, sub, ' + $flags + ' from p')
}

# A (language, week) cell before anything is added to it.
def zero [lang: string, week: string]: nothing -> Tally {
    {lang: $lang, week: $week, writes: 0, oracle_runs: 0, oracle_fails: 0, law_denials: 0}
}

# Everything the parts and the ledger add, one tally per (part, language).
# The ledger is authoritative from its first line on; before that instant the
# store's own denials stand in. A Bash denial is the shell, and the shell is nu.
export def tallies-of [parts: list<Part>, ledger: list<Ledger>, zone: string]: nothing -> list<Tally> {
    # no ledger yet: the sentinel is the last instant of year 9999, so every stored denial stands in
    let firstLineMs: int = (if ($ledger | is-empty) {
        253402300799999
    } else {
        $ledger.ts | each {|ts| epoch-ms $ts } | math min
    })
    $parts
    | each {|p|
        let written: string = (if ($p.tool in $EDIT_TOOLS) and ($p.status == 'completed') { language-of $p.path } else { '' })
        let runs: list<string> = (if ($p.tool == 'Bash') and ($p.status == 'completed') { oracle-of $p.cmd } else { [] })
        let denied: string = (if ($p.status == 'error') and ($p.t < $firstLineMs) and ((denial-of $p.err) != null) {
            if $p.tool == 'Bash' { 'nu' } else { language-of $p.path }
        } else {
            ''
        })
        if ($written | is-empty) and ($runs | is-empty) and ($denied | is-empty) {
            []
        } else {
            let week: string = (week-of $p.t $zone)
            let writes: list<Tally> = (if ($written | is-empty) { [] } else { [(zero $written $week | merge {writes: 1})] })
            let oracle: list<Tally> = ($runs | each {|lang|
                zero $lang $week | merge {oracle_runs: 1, oracle_fails: (if ($p | get $'fail_($lang)') == 1 { 1 } else { 0 })}
            })
            let denials: list<Tally> = (if ($denied | is-empty) { [] } else { [(zero $denied $week | merge {law_denials: 1})] })
            $writes | append $oracle | append $denials
        }
    }
    | append ($ledger | each {|l|
        let lang: string = (if $l.language == 'shell' { 'nu' } else { language-of-ext $l.language })
        if ($lang | is-empty) { [] } else { [(zero $lang (week-of (epoch-ms $l.ts) $zone) | merge {law_denials: 1})] }
    })
    | flatten
}

# The totals per (language, week); a cell nothing touched is absent.
export def sum-tallies [tallies: list<Tally>]: nothing -> table {
    $tallies
    | group-by --to-table lang week
    | each {|g| ($g.items | math sum writes oracle_runs oracle_fails law_denials | insert lang $g.lang | insert week $g.week) }
}

# Law denials per 1,000 writes: 0 where nothing happened, null where there
# were denials but no writes to divide by.
def per-1000 [denials: int, writes: int]: nothing -> float {
    if $writes == 0 { return (if $denials == 0 { 0.0 } else { null }) }
    ((($denials * 1000.0 / $writes) * 10.0 | math round) / 10.0)
}

# The language leg: every language x every week, zeros where nothing happened.
export def language-table [tallies: list<Tally>, weeks: list<Week>]: nothing -> list<Cell> {
    let sums: table = (sum-tallies $tallies)
    $LANGS
    | each {|lang|
        $weeks | each {|w|
            let s: Tally = ($sums | where {|r| ($r.lang == $lang.lang) and ($r.week == $w.week) } | first | default (zero $lang.lang $w.week))
            {
                week: $w.week
                monday: $w.monday
                lang: $lang.lang
                writes: $s.writes
                oracle_runs: $s.oracle_runs
                oracle_fails: $s.oracle_fails
                law_denials: $s.law_denials
                denials_per_1000_writes: (per-1000 $s.law_denials $s.writes)
            }
        }
    }
    | flatten
}

# ══ RUMBO LEG ════════════════════════════════════════════════════════════════
# Port of the working reference `replay-cancelled.nu` (2026-11-26).
#
# A turn DENOTES the time window (previous seal of its session, this seal];
# a signal DENOTES a predicate on a step prefix; a metric DENOTES how well one
# predicate separates the cancelled turns from the rest of the population.

# One tool call of a turn, slimmed from the part row.
export type Step = record<t: int, tool: string, status: string, path: string, cmd: string>

# A turn with its real steps: the window (previous seal, this seal].
export type Turn = record<sid: string, t0: int, t1: int, reason: string, steps: list<Step>>

# One turn's features: measured facts plus the flags at three horizons.
export type Features = record<sid: string, reason: string, n: int, dur_min: float, stalled_min: float, files: int, max_per_file: int, errs: int, edits: int, request: string, reedit_5: bool, sprawl_5: bool, redloop_5: bool, errrate_5: bool, readheavy_5: bool, agent_5: bool, late_5: bool, any_5: bool, reedit_10: bool, sprawl_10: bool, redloop_10: bool, errrate_10: bool, readheavy_10: bool, agent_10: bool, late_10: bool, any_10: bool, reedit_all: bool, sprawl_all: bool, redloop_all: bool, errrate_all: bool, readheavy_all: bool, agent_all: bool, late_all: bool, nocheck_all: bool, any_all: bool>

# The discrimination of one signal at one horizon.
export type Metric = record<signal: string, at: string, flagged: int, cancelled_in_flagged: int, precision_pct: float, lift: float, recall_pct: float, coverage_pct: float>

# The flag names, without horizon suffix.
export const SIGNALS: list<string> = [reedit sprawl redloop errrate readheavy agent late nocheck]

# The horizons: the first 5 steps, the first 10, the whole turn.
export const HORIZONS: list<string> = ['5' '10' 'all']

# The read-shaped tools (looking without touching).
export const READ_TOOLS: list<string> = [Read Glob Grep]

# The cancel-step buckets, each one the upper bound of its range.
export type Bucket = record<upto: int, name: string>
export const BUCKETS: list<Bucket> = [
    {upto: 5, name: 'a. <=5'}
    {upto: 10, name: 'b. 6-10'}
    {upto: 20, name: 'c. 11-20'}
    {upto: 50, name: 'd. 21-50'}
    {upto: 1000000000, name: 'e. >50'}
]

# The bucket a step count falls in (the first row whose bound covers it).
export def bucket-of [n: int]: nothing -> string {
    $BUCKETS | where upto >= $n | first | get name
}

# The sealed turns of the daemon log, oldest first (the log text in).
export def parse-seals [text: string]: nothing -> table {
    $text | lines
    | where $it =~ 'live view sealed'
    | parse -r '^(?<ts>\S+) .*taskId=(?<sid>\S+) reason=(?<reason>\w+) thought=(?<thought>\d+) tools=(?<tools>\d+)'
    | upsert ts {|row| epoch-ms $row.ts }
    | upsert thought {|row| $row.thought | into int }
    | upsert tools {|row| $row.tools | into int }
    | select sid ts reason tools thought
    | sort-by sid ts
}

# The turns: each seal owns the window (previous seal of its session, this seal].
export def turns-of [seals: table]: nothing -> table {
    $seals | group-by --to-table sid
    | each {|group|
        $group.items
        | sort-by ts
        | enumerate
        | each {|pair|
            let prev: list<int> = ($group.items | where ts < $pair.item.ts | get ts)
            {
                sid: $pair.item.sid
                t0: (if ($prev | length) > 0 { $prev | math max } else { 0 })
                t1: $pair.item.ts
                reason: $pair.item.reason
                steps: []
            }
        }
    }
    | flatten
}

# The slim tool steps of the given sessions (the SQL; the script runs it).
export def steps-query [sids: list<string>]: nothing -> string {
    let inList: string = ('(' + ($sids | uniq | each {|sid| "'" + $sid + "'" } | str join ',') + ')')
    ("select session_id as sid, time_created as t,
        json_extract(data, '$.tool') as tool,
        json_extract(data, '$.state.status') as status,
        coalesce(json_extract(data, '$.state.input.file_path'), '') as path,
        substr(replace(coalesce(json_extract(data, '$.state.input.command'), json_extract(data, '$.state.input.description'), ''), char(10), ' '), 1, 110) as cmd
        from part
        where json_extract(data, '$.type') = 'tool' and
        session_id in " + $inList + "
        order by session_id, time_created")
}

# The real user messages (never the runtime's synthetic reminders) of the sessions.
export def requests-query [sids: list<string>]: nothing -> string {
    let inList: string = ('(' + ($sids | uniq | each {|sid| "'" + $sid + "'" } | str join ',') + ')')
    ("select m.session_id as sid, m.time_created as t,
        substr(replace(json_extract(p.data, '$.text'), char(10), ' '), 1, 230) as txt
        from message m join part p on p.message_id = m.id
        where json_extract(m.data, '$.role') = 'user' and
        json_extract(p.data, '$.type') = 'text' and
        coalesce(json_extract(m.data, '$.synthetic'), 0) = 0 and
        m.session_id in " + $inList + "
        order by m.session_id, m.time_created")
}

# How many times each edited file was edited.
export def edits-per-file [steps: list<Step>]: nothing -> list<int> {
    let edits: table = ($steps | where tool in $EDIT_TOOLS)
    if ($edits | length) == 0 {
        []
    } else {
        $edits | group-by --to-table path | update items {|group| $group.items | length } | get items
    }
}

# The largest value of a list, 0 when the list is empty.
export def max-or-0 [values: list<int>]: nothing -> int {
    if ($values | length) == 0 { 0 } else { $values | math max }
}

# The drift flags of one step prefix.
export type Flags = record<reedit: bool, sprawl: bool, redloop: bool, errrate: bool, readheavy: bool, agent: bool, late: bool>

# The drift flags of a step prefix. A prefix shorter than the horizon simply
# yields what exists. `late` = explored a lot without editing anything yet.
export def flags-of [steps: list<Step>, horizon: string]: nothing -> Flags {
    let n: int = ($steps | length)
    let perFile: list<int> = (edits-per-file $steps)
    let errs: int = ($steps | where status == error | length)
    let reads: int = ($steps | where tool in $READ_TOOLS | length)
    let firstEdit: list<int> = ($steps | enumerate | where item.tool in $EDIT_TOOLS | get index)
    let reeditAt: int = (if $horizon == 'all' { 3 } else { 2 })
    {
        reedit: ((max-or-0 $perFile) >= $reeditAt)
        sprawl: (($perFile | length) >= 4)
        redloop: ($errs >= 2)
        errrate: (($n >= 4) and (($errs / $n) >= 0.25))
        readheavy: (($n >= 6) and (($reads / $n) >= 0.5))
        agent: (($steps | where tool == Agent | length) >= 1)
        late: ((($firstEdit | length) == 0) and ($n >= 8))
    }
}

# True when any flag of the record is set.
export def any-flag [flags: record]: nothing -> bool {
    $flags | columns | any {|name| $flags | get $name }
}

# Did the turn run any verification (test/build/lint) after its first edit?
export def checked-after-edit [steps: list<Step>]: nothing -> bool {
    let firstEdit: list<int> = ($steps | enumerate | where item.tool in $EDIT_TOOLS | get index)
    if ($firstEdit | length) == 0 {
        true
    } else {
        let checks: int = ($steps | skip ($firstEdit | first)
            | where {|step| ($step.tool == 'Bash') and ($step.cmd =~ '(?i)test|gradlew|lint|check|spec|pytest|npm run') }
            | length)
        $checks > 0
    }
}

# One turn's features: the measured facts and the flags at 5, 10 and all steps.
export def features-of [turn: Turn, requests: table]: nothing -> Features {
    let s: list<Step> = ($turn.steps | sort-by t)
    let n: int = ($s | length)
    let perFile: list<int> = (edits-per-file $s)
    let errs: int = ($s | where status == error | length)
    let edits: int = ($s | where tool in $EDIT_TOOLS | length)
    let asked: table = ($requests | where sid == $turn.sid and t >= ($turn.t0 - 60000) and t <= $turn.t1)
    let real: table = ($asked | where {|m| ($m.txt | str starts-with 'Contexto de memoria') == false })
    let f5: record = (flags-of ($s | first 5) '5')
    let f10: record = (flags-of ($s | first 10) '10')
    let fa: record = (flags-of $s 'all')
    {
        sid: $turn.sid
        reason: $turn.reason
        n: $n
        # a session's first seal has no previous seal (t0 = 0): its duration
        # would count from the epoch, so it is not a duration at all
        dur_min: (if $turn.t0 == 0 { null } else { ((($turn.t1 - $turn.t0) / 60000.0) | math round --precision 1) })
        stalled_min: (((($turn.t1 - ($s | last | get t)) / 60000.0)) | math round --precision 1)
        files: ($perFile | length)
        max_per_file: (max-or-0 $perFile)
        errs: $errs
        edits: $edits
        request: (if ($real | length) > 0 { $real | last | get txt } else { '' })
        reedit_5: $f5.reedit, sprawl_5: $f5.sprawl, redloop_5: $f5.redloop, errrate_5: $f5.errrate, readheavy_5: $f5.readheavy, agent_5: $f5.agent, late_5: $f5.late, any_5: (any-flag $f5)
        reedit_10: $f10.reedit, sprawl_10: $f10.sprawl, redloop_10: $f10.redloop, errrate_10: $f10.errrate, readheavy_10: $f10.readheavy, agent_10: $f10.agent, late_10: $f10.late, any_10: (any-flag $f10)
        reedit_all: $fa.reedit, sprawl_all: $fa.sprawl, redloop_all: $fa.redloop, errrate_all: $fa.errrate, readheavy_all: $fa.readheavy, agent_all: $fa.agent, late_all: $fa.late, nocheck_all: ((checked-after-edit $s) == false), any_all: (any-flag $fa)
    }
}

# How well one signal at one horizon separates cancelled from the rest.
# precision = cancelled share among the flagged · lift = precision / base rate
# recall = cancelled turns the flag catches · coverage = turns it fires on.
export def metric-of [rows: table, signal: string, horizon: string, base: float]: nothing -> Metric {
    let col: string = ($'($signal)_($horizon)')
    let hit: table = ($rows | where {|row| $row | get $col })
    let hitN: int = ($hit | length)
    let killed: int = ($hit | where reason == cancelled | length)
    let total: int = ($rows | length)
    let baseN: int = ($rows | where reason == cancelled | length)
    let precision: float = (if $hitN > 0 { $killed / $hitN } else { 0.0 })
    {
        signal: $signal
        at: $horizon
        flagged: $hitN
        cancelled_in_flagged: $killed
        precision_pct: (($precision * 100) | math round --precision 1)
        lift: ((if ($precision > 0.0) and ($base > 0.0) { $precision / $base } else { 0.0 }) | math round --precision 2)
        recall_pct: ((if $baseN > 0 { ($killed / $baseN) * 100 } else { 0.0 }) | math round --precision 1)
        coverage_pct: ((if $total > 0 { ($hitN / $total) * 100 } else { 0.0 }) | math round --precision 1)
    }
}

# The table of every signal at every horizon, most discriminating first.
export def metric-table [rows: table, base: float]: nothing -> table {
    $SIGNALS | each {|signal|
        $HORIZONS
        | where {|horizon| ($signal != 'nocheck') or ($horizon == 'all') }
        | each {|horizon| metric-of $rows $signal $horizon $base }
    }
    | flatten
    | sort-by lift -r
}

# The mean of the numbers that are known (nulls skipped); null when none is.
def avg-known [values: list<any>]: nothing -> any {
    let known: list<any> = ($values | where {|v| $v != null })
    if ($known | is-empty) { null } else { $known | math avg | math round --precision 1 }
}

# The facts of each verdict population, side by side.
export def population-table [rows: table]: nothing -> table {
    $rows | group-by --to-table reason | update items {|group|
        {
            turns: ($group.items | length)
            avg_steps: ($group.items.n | math avg | math round --precision 1)
            avg_files: ($group.items.files | math avg | math round --precision 1)
            avg_max_reedit: ($group.items.max_per_file | math avg | math round --precision 2)
            avg_tool_errors: ($group.items.errs | math avg | math round --precision 2)
            avg_min: (avg-known $group.items.dur_min)
            with_3plus_reedit: ($group.items | where max_per_file >= 3 | length)
            no_check_after_edit: ($group.items | where nocheck_all | length)
        }
    }
    | each {|group| $group.items | insert reason $group.reason }
}

# One entry of the cancelled-turn sample: the facts, then the request.
export def sample-line [pair: record<index: int, item: Features>]: nothing -> string {
    let row: Features = $pair.item
    let tag: int = ($pair.index / 4 | math floor)
    let head: string = $"[($tag)] n=($row.n) files=($row.files) maxreedit=($row.max_per_file) errs=($row.errs) min=($row.dur_min) · ($row.sid | str substring 0..13)"
    $"($head)\n      ($row.request | str substring 0..170)"
}

# The cancel causes, most specific first: the first row whose predicate
# holds names the turn. Mechanical on purpose — a wedge is not a drift.
export def causes []: nothing -> list<record<name: string, when: closure>> {
    [
        {name: 'a. wedge: stalled over 10 min before the cancel', when: {|row: Features| $row.stalled_min > 10.0 }}
        {name: 'b. quick stop: 5 steps or less', when: {|row: Features| $row.n <= 5 }}
        {name: 'c. long run: more than 50 steps', when: {|row: Features| $row.n > 50 }}
        {name: 'd. middle: 6 to 50 steps', when: {|row: Features| true }}
    ]
}

# The cause of one cancelled turn.
export def cause-of [row: Features]: nothing -> string {
    let rows: list<record<name: string, when: closure>> = (causes)
    $rows | where {|cause| do $cause.when $row } | first | get name
}

# The cancelled turns grouped by cause, with the steps each cause wasted.
export def cause-table [rows: table]: nothing -> table {
    let killedRows: table = ($rows | where reason == cancelled)
    if ($killedRows | is-empty) { return [] }
    let wasted: int = ($killedRows.n | math sum)
    $killedRows
    | upsert cause {|row| cause-of $row }
    | group-by --to-table cause
    | update items {|group|
        {
            turns: ($group.items | length)
            avg_steps: ($group.items.n | math avg | math round --precision 1)
            steps_wasted: ($group.items.n | math sum)
            share_of_wasted_steps: (((($group.items.n | math sum) / $wasted) * 100) | math round --precision 1)
            with_2plus_errors: ($group.items | where errs >= 2 | length)
        }
    }
    | rename cause items
    | update items {|group| $group.items | insert cause $group.cause }
    | get items
    | flatten
}

# Every sealed turn with its real steps and its features (only the turns
# that matched at least one step; dur_min is null where no duration exists).
export def replay-rows [seals: table, steps: table, requests: table]: nothing -> table {
    turns-of $seals
    | each {|turn|
        $turn
        | update steps {|t| $steps | where sid == $t.sid and t > $t.t0 and t <= $t.t1 }
    }
    | where {|turn| ($turn.steps | length) > 0 }
    | each {|turn| features-of $turn $requests }
}

# The share of a cancelled turn's base rate, 0.0 when nothing matched.
export def base-rate [killed: int, matched: int]: nothing -> float {
    if $matched == 0 { 0.0 } else { $killed / $matched }
}

# Table A: where the cancel lands (the step count of the cancelled turns).
export def cancel-landing [rows: table, killedN: int]: nothing -> table {
    $rows | where reason == cancelled
    | upsert bucket {|row| bucket-of $row.n }
    | group-by --to-table bucket | update items {|group| $group.items | length } | rename bucket cancelled
    | upsert share_pct {|row| ((($row.cancelled / $killedN) * 100) | math round --precision 1) }
    | sort-by bucket
}
