# lang-ok: historical denial spellings (rule 6 — the ledger keeps Spanish-era lines)
# brain-baseline.nu — the pure core of the baseline on literal fixtures: the
# language leg (whose file, which command runs which oracle, how a denial is
# told apart from a harness error, the week grid, the store-to-ledger
# handoff) and the rumbo leg (the replay port). No database, no files, no
# clock: every instant is a number.
use std/assert
use ../../lib/brain-baseline.nu *

# Monday of 2026-W47 (Nov 16) at noon, read in -03:00; and the Sunday that
# ends that week at 23:30 — already Monday W48 in UTC.
const MON: int = 1794841200000
const SUN_LATE: int = 1795401000000

# 1. language-of: the extension decides, case never does, untracked is ''.
assert equal (language-of '/p/a.nu') 'nu'
assert equal (language-of '/p/B.KT') 'kt'
assert equal (language-of 'x.kts') 'kt'
assert equal (language-of 'x.TS') 'ts'
assert equal (language-of 'x.tsx') 'ts'
assert equal (language-of 'x.mjs') 'ts'
assert equal (language-of 'x.hs') 'hs'
assert equal (language-of 'x.py') ''
assert equal (language-of 'Makefile') ''

# 2. oracle-of: an oracle is a COMMAND in the text, never a thing read about.
type OracleCase = record<cmd: string, langs: list<string>>
const ORACLES: list<OracleCase> = [
    {cmd: 'cd /x && ./gradlew test detekt', langs: [kt]}
    {cmd: "cd /x; bash -lc './gradlew test > log; echo EXIT=1'", langs: [kt]}
    {cmd: 'JAVA_HOME=/jdk ./gradlew -q test', langs: [kt]}
    {cmd: 'kotlinc src/a.kt', langs: [kt]}
    {cmd: 'cat build.gradle.kts', langs: []}
    {cmd: 'grep -rn "detekt" --include=*.kts .', langs: []}
    {cmd: 'ls gradle/', langs: []}
    {cmd: 'npx tsc --noEmit', langs: [ts]}
    {cmd: 'pnpm test -- --watch', langs: [ts]}
    {cmd: './node_modules/.bin/vitest run', langs: [ts]}
    {cmd: 'cat vitest.config.ts', langs: []}
    {cmd: 'cabal build all', langs: [hs]}
    {cmd: 'BIN=$(cabal list-bin t) && "$BIN"', langs: [hs]}
    {cmd: 'cat stack.yaml', langs: []}
    {cmd: 'nu tests/lib/x.nu', langs: [nu]}
    {cmd: 'nu --stdin ~/.zcode/hooks/write-guard.nu', langs: [nu]}
    {cmd: 'nu-check scripts/fleet.nu', langs: [nu]}
    {cmd: './scripts/fleet.nu list', langs: [nu]}
    {cmd: "nu -c 'print 1'", langs: []}
    {cmd: 'cat x.nu', langs: []}
    # one step may run several oracles; they answer in the table's order
    {cmd: './gradlew test && nu deploy.nu; npx tsc', langs: [nu kt ts]}
    # a quoted word is an argument, not a command; the quote of a `-c` wrapper is
    {cmd: 'grep -c detekt build.gradle.kts', langs: []}
    {cmd: 'echo "cabal build"', langs: []}
    {cmd: "sh -c 'cd /x && npx vitest run'", langs: [ts]}
    {cmd: 'nu -c "nu /Users/lattenero/Scripts/session-find.nu mirror"', langs: [nu]}
]
for o in $ORACLES {
    assert equal (oracle-of $o.cmd) $o.langs $"oracle-of must read the command, not the words: ($o.cmd)"
}

# 3. denial-of: the line must START as a hook denial, and the rule must be one
#    the three hooks carry today (the fork's newer wrapper included).
type DenialCase = record<err: string, hook: string, rule: string>
const DENIALS: list<DenialCase> = [
    {err: 'PreToolUse:Write hook error: [command hidden]: ⛔ Typing law — defs WITHOUT an IO signature: main.', hook: 'nushell-typing', rule: 'def-without-signature'}
    {err: '⛔ Ley de tipado — defs SIN firma IO: do-deploy.', hook: 'nushell-typing', rule: 'def-without-signature'}
    {err: 'PreToolUse:Edit hook error: [command hidden]: ⛔ Typing law — params WITHOUT a type: # one path', hook: 'nushell-typing', rule: 'untyped-params'}
    {err: '⛔ Nushell law — hyphenated variables are INVALID: dead-check, respawn-check.', hook: 'nushell-typing', rule: 'hyphenated-variable'}
    {err: '⛔ Ley Nushell — variables con guión, inválidas: apply-all.', hook: 'nushell-typing', rule: 'hyphenated-variable'}
    {err: ('⛔ Reactive law — blind sl' + 'eep 45sec FORBIDDEN: be event-driven'), hook: 'nushell-typing', rule: 'blind-sleep'}
    {err: '⛔ Ley reactiva — sleep ciego 30sec PROHIBIDO', hook: 'nushell-typing', rule: 'blind-sleep'}
    {err: ('PreToolUse:Bash hook error: [command hidden]: ⛔ Reactive law: blind sl' + 'eep 20 is FORBIDDEN'), hook: 'nushell-law', rule: 'blind-sleep'}
    {err: '⛔ Paren-wrapped `let` law: `let` is a statement in Nushell', hook: 'nushell-law', rule: 'paren-let'}
    {err: '⛔ anti-pattern dispatch-chain · AST · law entry 1 — the else-if chain', hook: 'anti-pattern-lint', rule: 'dispatch-chain'}
    {err: 'PreToolUse:Write hook error: [command hidden]: ⛔ anti-pattern-lint · orphaned-branch · HIGH · 2 hit(s)', hook: 'anti-pattern-lint', rule: 'orphaned-branch'}
    {err: '⛔ anti-pattern-lint · paren-let · HIGH · 3 hit(s) — paren-wrapped let', hook: 'anti-pattern-lint', rule: 'paren-let'}
]
for d in $DENIALS {
    let got: any = (denial-of $d.err)
    assert equal ($got.hook? | default '') $d.hook $"the hook of: ($d.err | str substring 0..60)"
    assert equal ($got.rule? | default '') $d.rule $"the rule of: ($d.err | str substring 0..60)"
}
# a harness error that QUOTES hook text is no denial; neither is write-guard's,
# a plan-mode refusal, nor a rule no hook carries today
const NOT_DENIALS: list<string> = [
    'String to replace not found in file. String: print -e $"⛔ Reactive law: blind sleep ($sl) is FORBIDDEN'
    'write-guard: /x/a.nu was not Read in this session'
    'Plan mode only allows read-only, non-destructive tools'
    'File has not been read yet. Read it first before writing to it.'
    '⛔ Nushell law (AGENTS.md): every shell command goes through Nushell.'
    ''
]
for e in $NOT_DENIALS {
    assert equal (denial-of $e) null $"no law denial: ($e | str substring 0..60)"
}
# ...but the retired rule still STARTS like one: it is counted apart, never lost
assert equal (denial-line? '⛔ Nushell law (AGENTS.md): every shell command goes through Nushell.') true
assert equal (denial-line? 'File has not been read yet. Read it first before writing to it.') false
assert equal (denial-line? '') false

# 4. weeks: ISO labels read in a zone — Sunday 23:30 in Buenos Aires is still
#    W47 while UTC already calls it Monday W48.
assert equal (epoch-ms '2026-11-26T12:11:41-03:00') 1795705901000
assert equal (week-of $MON '-03:00') '2026-W47'
assert equal (week-of $SUN_LATE '-03:00') '2026-W47'
assert equal (week-of $SUN_LATE '+00:00') '2026-W48'
assert equal (monday-of $SUN_LATE '-03:00') '11-16'
type WeekCase = record<week: string, monday: string>
# the last n weeks END with the week of the instant, oldest first
const THREE_WEEKS: list<WeekCase> = [{week: '2026-W45', monday: '11-02'} {week: '2026-W46', monday: '11-09'} {week: '2026-W47', monday: '11-16'}]
assert equal (recent-weeks $MON '-03:00' 3) $THREE_WEEKS

# 5. ledger-rows: six tab-separated fields make a record; anything else is noise.
type LedgerCase = record<ts: string, sid: string, hook: string, rule: string, language: string, target: string>
const LEDGER_TEXT: string = ("2026-11-26T12:33:20-03:00\tses_1\tnushell-typing\thyphenated-variable\tnu\t/p/a.nu" + (char nl)
    + 'not a line' + (char nl) + (char nl)
    + "2026-11-26T12:40:00-03:00\tses_2\tnushell-law\tblind-sleep\tshell\tprint 1" + (char nl))
const LEDGER_ROWS: list<LedgerCase> = [
    {ts: '2026-11-26T12:33:20-03:00', sid: 'ses_1', hook: 'nushell-typing', rule: 'hyphenated-variable', language: 'nu', target: '/p/a.nu'}
    {ts: '2026-11-26T12:40:00-03:00', sid: 'ses_2', hook: 'nushell-law', rule: 'blind-sleep', language: 'shell', target: 'print 1'}
]
assert equal (ledger-rows $LEDGER_TEXT) $LEDGER_ROWS
assert equal (ledger-rows '') []

# 6. parts-query: ONE scan; the output is extracted once (a materialized CTE)
#    and every marker is a test over it; the window and the tool filter ride along.
let q: string = (parts-query 1790867577000)
assert equal ($q | split row "json_extract(data,'$.state.output')" | length) 2 "the output is extracted exactly once"
assert str contains $q 'with p as materialized (select'
assert str contains $q 'time_created > 1790867577000'
assert str contains $q "json_extract(data,'$.tool') in ('Edit','Write','MultiEdit','Bash')"
assert str contains $q "(session_id like 'sess_subagent%') as sub"
assert str contains $q "instr(o, 'BUILD FAILED') > 0"
assert str contains $q "(o like ('%' || 'FAILED') or instr(o, 'FAILED' || char(10)) > 0)"
assert str contains $q "(o like ('e: ' || '%') or instr(o, char(10) || 'e: ') > 0)"
assert str contains $q "o glob ('*[0-9]' || ' failed' || '*')"
assert str contains $q "o glob '*([1-9]* errors*'"
for lang in [nu kt ts hs] {
    assert str contains $q $" then 1 else 0 end as fail_($lang)" $"one failure flag for ($lang)"
}
# the LIKE law: a marker is a literal, never a wildcard
assert equal ($MARKERS | where {|m| $m.text =~ '[_%]' } | length) 0

# 7. tallies-of / language-table: every number of a (language, week) cell, and
#    the handoff — the ledger is authoritative from its first line on; before
#    it, the store's own denials stand in. A Bash denial is the shell = nu.
# one stored part of the fixture, as the scan hands it over
def part [sid: string, t: int, tool: string, status: string, cmd: string, path: string, err: string, sub: int, kt: int, ts: int, hs: int, fnu: int]: nothing -> Part {
    {sid: $sid, t: $t, tool: $tool, status: $status, cmd: $cmd, path: $path, err: $err, sub: $sub}
    | merge {fail_kt: $kt, fail_ts: $ts, fail_hs: $hs, fail_nu: $fnu}
}
# one cell of the language grid, by week and language
def cell [cells: table, week: string, lang: string]: nothing -> any {
    $cells | where {|c| ($c.week == $week) and ($c.lang == $lang) } | get 0
}

const W_PREV: int = ($MON - 7 * 86400_000)        # the week before: 2026-W46
const OLDER: int = ($W_PREV + 3600_000)          # W46, an hour after noon
const TYPING: string = 'PreToolUse:Edit hook error: [command hidden]: ⛔ Typing law — '
const BLIND: string = ('PreToolUse:Bash hook error: [command hidden]: ⛔ Reactive law: blind sl' + 'eep 20 is FORBIDDEN')
let parts: list<Part> = [
    # the week before the ledger: everything comes from the store
    (part 's1' $OLDER 'Write' 'completed' '' '/p/d.tsx' '' 0 0 0 0 0)
    (part 's1' $OLDER 'Edit' 'completed' '' '/p/a.nu' '' 0 0 0 0 0)
    (part 's1' ($OLDER + 1000) 'Edit' 'error' '' '/p/a.nu' ($TYPING + 'defs WITHOUT an IO signature: main.') 0 0 0 0 0)
    (part 's1' ($OLDER + 2000) 'Edit' 'error' '' '/p/e.kt' 'File has not been read yet. Read it first before writing to it.' 0 0 0 0 0)
    (part 's1' ($OLDER + 3000) 'Bash' 'completed' 'npx tsc --noEmit' '' '' 0 0 1 0 0)
    (part 's1' ($OLDER + 4000) 'Bash' 'completed' 'cabal build' '' '' 0 0 0 0 0)
    (part 's1' ($OLDER + 5000) 'Bash' 'completed' 'nu x.nu' '' '' 0 0 0 0 1)
    (part 's1' ($OLDER + 6000) 'Bash' 'error' 'x' '' $BLIND 0 0 0 0 0)
    # the ledger's week: before its first line (13:00) the store still stands in...
    (part 's1' $MON 'Edit' 'completed' '' '/p/a.nu' '' 0 0 0 0 0)
    (part 's1' ($MON + 1800_000) 'Edit' 'error' '' '/p/a.nu' ($TYPING + 'params WITHOUT a type: x') 0 0 0 0 0)
    # ...and after it a stored denial is already one of the ledger's own lines
    (part 's1' ($MON + 5400_000) 'Edit' 'error' '' '/p/a.nu' ($TYPING + 'params WITHOUT a type: y') 0 0 0 0 0)
    (part 's1' ($MON + 600_000) 'Bash' 'completed' './gradlew test' '' '' 0 1 0 0 0)
    (part 's1' ($MON + 700_000) 'Bash' 'completed' 'cat build.gradle.kts' '' '' 0 0 0 0 0)
    (part 'sess_subagent_1' ($MON + 800_000) 'Bash' 'completed' 'ls' '' '' 1 0 0 0 0)
]
const LEDGER_2: string = ("2026-11-16T13:00:00-03:00\tses_9\tnushell-typing\tblind-sleep\tnu\t/p/a.nu" + (char nl)
    + "2026-11-16T14:00:00-03:00\tses_9\tnushell-law\tblind-sleep\tshell\tnu x.nu" + (char nl)
    + "2026-11-16T14:01:00-03:00\tses_9\tsome-future-hook\tsome-rule\tpy\t/p/a.py" + (char nl))
let ledger: list<Ledger> = (ledger-rows $LEDGER_2)

let weeks: list<Week> = (recent-weeks $MON '-03:00' 2)
let cells: table = (language-table (tallies-of $parts $ledger '-03:00') $weeks)
assert equal ($cells | length) 8 "every language x every week, zeros included"
assert equal (cell $cells '2026-W46' 'nu' | select week monday lang writes oracle_runs oracle_fails law_denials denials_per_1000_writes) {week: '2026-W46', monday: '11-09', lang: 'nu', writes: 1, oracle_runs: 1, oracle_fails: 1, law_denials: 2, denials_per_1000_writes: 2000.0}
assert equal (cell $cells '2026-W46' 'ts' | select writes oracle_runs oracle_fails law_denials) {writes: 1, oracle_runs: 1, oracle_fails: 1, law_denials: 0}
assert equal (cell $cells '2026-W46' 'hs' | select writes oracle_runs oracle_fails) {writes: 0, oracle_runs: 1, oracle_fails: 0}
assert equal (cell $cells '2026-W46' 'kt' | select writes oracle_runs oracle_fails law_denials) {writes: 0, oracle_runs: 0, oracle_fails: 0, law_denials: 0}
assert equal (cell $cells '2026-W47' 'nu' | select writes oracle_runs law_denials denials_per_1000_writes) {writes: 1, oracle_runs: 0, law_denials: 3, denials_per_1000_writes: 3000.0}
assert equal (cell $cells '2026-W47' 'kt' | select writes oracle_runs oracle_fails) {writes: 0, oracle_runs: 1, oracle_fails: 1}

# 8. nothing in, a grid of zeros out; and where denials exist but no writes do,
#    the ratio is undefined (null) rather than a fake zero.
let none: table = (language-table (tallies-of [] [] '-03:00') $weeks)
assert equal ($none | where {|c| ($c.writes + $c.oracle_runs + $c.oracle_fails + $c.law_denials) > 0 } | length) 0
assert equal ($none | get denials_per_1000_writes | uniq) [0.0]
const ONLY_SHELL: string = ("2026-11-16T13:00:00-03:00\tses_9\tnushell-law\tblind-sleep\tshell\tnu x.nu" + (char nl))
let shellOnly: table = (language-table (tallies-of [] (ledger-rows $ONLY_SHELL) '-03:00') $weeks)
assert equal (cell $shellOnly '2026-W47' 'nu' | select writes law_denials denials_per_1000_writes) {writes: 0, law_denials: 1, denials_per_1000_writes: null}

# 9. parse-seals: one row per `live view sealed` line of the daemon log, time
#    as epoch ms, oldest first inside each session. Noise lines are skipped.
const T0: int = 1795629600000                    # 2026-11-25T18:00Z
const T1: int = 1795631400000                    # 18:30Z
const T2: int = 1795633200000                    # 19:00Z
const SEAL: string = 'Z INFO  d.l.b.c.LivePublisher [] live view sealed: taskId='
const LOG_TEXT: string = ('2026-11-25T18:00:00.000' + $SEAL + 'sess_a reason=success thought=10 tools=2 answer=100 chars' + (char nl)
    + 'noise without a seal' + (char nl)
    + '2026-11-25T19:00:00.000' + $SEAL + 'sess_b reason=success thought=10 tools=1 answer=100 chars' + (char nl)
    + '2026-11-25T18:30:00.000' + $SEAL + 'sess_a reason=cancelled thought=10 tools=3 answer=100 chars' + (char nl))
let seals: table = (parse-seals $LOG_TEXT)
assert equal ($seals | select sid ts reason tools) [
    {sid: sess_a, ts: $T0, reason: 'success', tools: 2}
    {sid: sess_a, ts: $T1, reason: 'cancelled', tools: 3}
    {sid: sess_b, ts: $T2, reason: 'success', tools: 1}
]
assert equal (parse-seals '') []

# 10. turns-of: each seal owns the window (previous seal of its session, this seal].
let turns: table = (turns-of $seals)
assert equal ($turns | select sid t0 t1 reason) [
    {sid: sess_a, t0: 0, t1: $T0, reason: 'success'}
    {sid: sess_a, t0: $T0, t1: $T1, reason: 'cancelled'}
    {sid: sess_b, t0: 0, t1: $T2, reason: 'success'}
]

# 11. replay-rows: the turns that matched real steps, with their features. The
#     first turn of a session has no duration (its window opens at the epoch).
const STEPS: table = [
    {sid: sess_a, t: ($T0 + 300000), tool: 'Read', status: 'completed', path: '/f.nu', cmd: ''}
    {sid: sess_a, t: ($T0 + 600000), tool: 'Edit', status: 'completed', path: '/f.nu', cmd: ''}
    {sid: sess_a, t: ($T0 + 900000), tool: 'Edit', status: 'completed', path: '/f.nu', cmd: ''}
    {sid: sess_a, t: ($T0 + 960000), tool: 'Edit', status: 'completed', path: '/f.nu', cmd: ''}
    {sid: sess_a, t: ($T0 + 1200000), tool: 'Bash', status: 'error', path: '', cmd: 'nu x.nu'}
    {sid: sess_a, t: ($T0 + 1260000), tool: 'Bash', status: 'error', path: '', cmd: 'nu y.nu'}
    {sid: sess_b, t: ($T2 - 600000), tool: 'Read', status: 'completed', path: '/g.kt', cmd: ''}
    {sid: sess_b, t: ($T2 - 300000), tool: 'Glob', status: 'completed', path: '', cmd: ''}
]
const REQUESTS: table = [
    {sid: sess_a, t: ($T0 - 30000), txt: 'fix the login'}
    {sid: sess_a, t: ($T0 + 60000), txt: 'Contexto de memoria ...'}
    {sid: sess_b, t: ($T2 - 600000), txt: 'look at the kt'}
]
let rows: table = (replay-rows $seals $STEPS $REQUESTS)
assert equal ($rows | length) 2 "the first turn of sess_a matched no step"
let killed: Features = ($rows | where reason == cancelled | get 0)
assert equal ($killed | select reason n files max_per_file errs edits dur_min stalled_min request reedit_5 redloop_5 any_5 reedit_all redloop_all any_all nocheck_all) {reason: 'cancelled', n: 6, files: 1, max_per_file: 3, errs: 2, edits: 3, dur_min: 30.0, stalled_min: 9.0, request: 'fix the login', reedit_5: true, redloop_5: false, any_5: true, reedit_all: true, redloop_all: true, any_all: true, nocheck_all: true}
assert equal ($rows | where reason == success | get 0.dur_min) null
# ...and a turn without a duration still reads through every table it reaches
let first: Features = ($rows | where reason == success | get 0)
assert equal (sample-line {index: 4, item: $first}) "[1] n=2 files=0 maxreedit=0 errs=0 min=? · sess_b\n      look at the kt"
assert equal (cause-of $first) 'b. quick stop: 5 steps or less'
assert equal (cause-of $killed) 'd. middle: 6 to 50 steps'

# 12. metric-of: precision, lift against the base rate, recall, coverage; and
#     the full table: `nocheck` exists at `all` only, and empties raise nothing.
const BASE: float = 0.5
assert equal (metric-of $rows 'redloop' 'all' $BASE) {signal: 'redloop', at: 'all', flagged: 1, cancelled_in_flagged: 1, precision_pct: 100.0, lift: 2.0, recall_pct: 100.0, coverage_pct: 50.0}
assert equal (metric-of $rows 'late' '5' $BASE) {signal: 'late', at: '5', flagged: 0, cancelled_in_flagged: 0, precision_pct: 0.0, lift: 0.0, recall_pct: 0.0, coverage_pct: 0.0}
let metrics: table = (metric-table $rows $BASE)
assert equal ($metrics | length) 22 "7 signals x 3 horizons + nocheck at all"
assert equal ($metrics | where signal == nocheck | get at) [all]
assert equal ($metrics | where lift == 2.0 | length) 8
assert equal ((metric-table [] $BASE) | where lift > 0.0 | length) 0

# 13. the populations, the causes and the landing: a duration is averaged only
#     where it exists, the reason labels its row, and an empty population is empty.
let pop: table = (population-table $rows)
assert equal ($pop | where reason == cancelled | get 0 | select reason turns avg_steps avg_files avg_max_reedit avg_tool_errors avg_min with_3plus_reedit no_check_after_edit) {reason: 'cancelled', turns: 1, avg_steps: 6.0, avg_files: 1.0, avg_max_reedit: 3.0, avg_tool_errors: 2.0, avg_min: 30.0, with_3plus_reedit: 1, no_check_after_edit: 1}
assert equal ($pop | where reason == success | get 0.avg_min) null
assert equal (population-table []) []
assert equal (cause-table $rows | get 0 | select turns steps_wasted share_of_wasted_steps with_2plus_errors cause) {turns: 1, steps_wasted: 6, share_of_wasted_steps: 100.0, with_2plus_errors: 1, cause: 'd. middle: 6 to 50 steps'}
assert equal (cause-table ($rows | where reason == success)) []
assert equal (cancel-landing $rows 1) [{bucket: 'b. 6-10', cancelled: 1, share_pct: 100.0}]
assert equal (cancel-landing ($rows | where reason == success) 0) []
assert equal (base-rate 0 0) 0.0
assert equal (base-rate 1 2) 0.5

# 14. the small pieces the legs are built from.
assert equal [(bucket-of 5) (bucket-of 6) (bucket-of 50) (bucket-of 51)] ['a. <=5' 'b. 6-10' 'd. 21-50' 'e. >50']
assert equal (edits-per-file $STEPS) [3]
assert equal (edits-per-file []) []
assert equal (max-or-0 []) 0
assert equal (max-or-0 [4 9 2]) 9
assert equal (any-flag (flags-of [] 'all')) false
assert equal (checked-after-edit $STEPS) false "no verification ran after the edits"
assert equal (checked-after-edit [{t: 1, tool: 'Bash', status: 'completed', path: '', cmd: './gradlew test'}]) true "nothing to verify"

# 15. the rumbo leg's SQL: the sessions ride an IN list, in time order.
assert str contains (steps-query ['sess_b' 'sess_a' 'sess_a']) "session_id in ('sess_b','sess_a')"
assert str contains (requests-query ['sess_a']) "json_extract(m.data, '$.role') = 'user'"
assert str contains (requests-query ['sess_a']) 'order by m.session_id, m.time_created'

print "lib/brain-baseline ok"
