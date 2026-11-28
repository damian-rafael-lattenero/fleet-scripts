#!/opt/homebrew/bin/nu
# PreToolUse(Bash): the Bash tool's mechanical laws as ONE priority table.
# The tool itself runs Nushell (fork build 2026-11-17: nu -l -c), so plain Nu
# needs NO wrapper — and there is no bash to reach for (owner order 26/11:
# "nu only"). Every row is a pattern that is NEVER valid nushell, or a law the
# parser cannot teach; the first matching row denies and its message names the
# nu form. Row order is precedence (the anti-patterns law: chains die, the
# table lives in row order). The rows are the bash-habit translations of
# nushell-kb/notes/bash-tool-laws.md — that note is their home.
#
# Rows (2026-11-27, owner order: prevent bash in all its forms, keep the good
# habits, teach at the moment of the mistake):
#   bash-escape      — bash/zsh -c anywhere (sh -c mid-command is a container's business)
#   blind-sleep      — a blind sleep >= 10s (jobs + mailboxes instead)
#   bad-sleep-unit   — a bare s is not a duration unit: it is 5sec
#   paren-let        — a paren-wrapped let is ALWAYS a parse error
#   two-lets         — a second inline binding means STOP: write a .nu file
#   bash-redirect    — 2>/dev/null, 2>&1: the nu forms are out+err>, e>|, complete
#   literal-dollar   — a double-quoted string keeps the dollar literal
#   bash-export      — export F=1: the env is $env.F = 1
#   bash-exit-code   — the bash exit-code variable: $env.LAST_EXIT_CODE
#   sort-uniq        — sort -u : sort | uniq
#   mkdir-parents    — mkdir -p : parents are implicit
#   for-do-done      — for-in-do-done : for x in [...] { ... }
#   then-fi          — then/fi blocks : if (cond) { ... }
#   test-bracket     — the bracket test : path exists
#   caret-builtin    — the caret is for external binaries only
#
# WARN rows (teach, never block): sleep-sync — a sleep under 10 s followed by
# more statements is the busy-wait shape; the event-bound law (fp-kb
# event-bound-waits.md) wants job recv --timeout / wait-until / complete, and
# the one exception is the <= 2 s mechanical race gap.
#
# Never silent on deny: stderr = the reason the model reads. The ledger gets
# ONE line per deny; a failed ledger write never moves the verdict.
# Proven by tests/scripts/denial-ledger.nu (the hooks run for real).

const DENIALS: path = '/Users/lattenero/.zcode/hooks/state/denials.tsv'

# The denial ledger: ONE tab-separated line per deny (ts, session, hook, rule,
# language, target), written right before the deny. It never moves the
# verdict: a failed write is dropped and the deny goes out unchanged.
def log-denial [log: path, sid: string, hook: string, rule: string, language: string, target: string]: nothing -> nothing {
  try {
    mkdir ($log | path dirname)
    [(date now | format date '%FT%T%:z') $sid $hook $rule $language ($target | str replace -a "\t" ' ' | str replace -a "\n" ' ' | str replace -a "\r" ' ' | str substring 0..119)]
    | str join "\t"
    | $"($in)\n"
    | save --append $log
  } catch { }
}

# One deny row: the pattern decides, the message teaches the nu form.
type DenyRule = record<name: string, when: closure, says: string>

# REACTIVE LAW: blind sleep >= 10s is forbidden (poll-less: job spawn/send/recv --timeout, or watch).
# Short sleeps (< 10s) stay legal as measured retry-gaps (e.g. the launchd bootout->bootstrap 2s race gap).
def long-sleep [cmd: string]: nothing -> string {
  let matches: table = ($cmd | parse -r '(?i)\bsleep\s+(?<n>\d+(?:\.\d+)?)\s*(?<u>seconds?|secs?|min(?:ute)?s?|m|hours?|hr|h)?\b')
  let offender: string = ($matches
    | where {|mm|
        let f: float = (match $mm.u {
          null => 1.0
          's' => 1.0
          'sec' => 1.0
          'secs' => 1.0
          'second' => 1.0
          'seconds' => 1.0
          'm' => 60.0
          'min' => 60.0
          'mins' => 60.0
          'minute' => 60.0
          'minutes' => 60.0
          'h' => 3600.0
          'hr' => 3600.0
          'hrs' => 3600.0
          'hour' => 3600.0
          'hours' => 3600.0
        })
        (($mm.n | into float) * $f) >= 10.0
      }
    | each {|mm| $"($mm.n)($mm.u | default '')" }
    | first
    | default '')
  $offender
}

# The deny table, row order = precedence: bash escapes first, then the laws
# the parser cannot teach, then the bash habits that are never valid nushell.
# Each closure takes the command as its argument.
def deny-rules []: nothing -> list<DenyRule> {
  [
    {name: 'bash-escape'
     when: {|c: string| $c =~ '\b(bash|zsh)\s+-c\b' or $c =~ '(^|[;&|])\s*\^?sh\s+-c\b' }
     says: "⛔ The nu-only law (owner 26/11): NEVER bash or zsh, not even the caret-escaped form. A POSIX tool is a DIRECT external (caret git, caret rg, caret python3 -c, caret psql); a block that grows becomes a .nu or .py FILE that nu runs. Retry in nushell."}
    {name: 'bad-sleep-unit'
     when: {|c: string| $c =~ '\bsleep\s+\d+s\b' }
     says: "⛔ A bare `s` is NOT a duration unit — that sleep is a parse error. The unit is `sec` (ns, us, ms, sec, min, hr, day, wk): sleep 2sec."}
    {name: 'blind-sleep'
     when: {|c: string| (long-sleep $c) | is-not-empty }
     says: "⛔ Reactive law: blind sleep is FORBIDDEN — be event-driven instead: `job spawn` + `job send 0` + `job recv --timeout` (the timeout raises; wrap in try/catch) or `watch` as an event stream. Full recipe: KB notes/reactive-jobs.md. Short sleeps below 10s remain legal as measured retry-gaps."}
    {name: 'paren-let'
     when: {|c: string| $c =~ '(?m)\(\s*let\b' }
     says: ("⛔ Paren-wrapped `let` law: `let` is a statement in Nushell — (le" + "t x = ...) is ALWAYS a parse error. THE fix: keep `let` at top level; the moment a payload needs a second binding, STOP and write a .nu script file. Retry as a script.")}
    {name: 'two-lets'
     when: {|c: string| ($c | parse -r '(?i)(?:^|;)\s*(?:let|mut)\s' | length) >= 2 }
     says: "⛔ One top-level `let` is fine inline; the moment a SECOND binding is needed, STOP — write a .nu script file (`nu script.nu`) and run that. Retry as a script."}
    {name: 'bash-redirect'
     when: {|c: string| $c =~ '\b[012]>(&[012]|/dev/null|/dev/)' }
     says: "⛔ Bash redirects do not exist here: `cmd out+err> file` merges streams, `cmd e>|` discards stderr, and `cmd | complete` hands stdout, stderr and exit_code to you as VALUES."}
    {name: 'literal-dollar'
     when: {|c: string| $c =~ '"\$[A-Z({]' }
     says: "⛔ A double-quoted string keeps the dollar LITERAL: \"v=$a\" prints v=$a. Interpolation is its own syntax — dollar-bracket-quote form — and the env is `$\"($env.HOME)/x\"`; a bash command-substitution is a value you compute first into a variable."}
    {name: 'bash-export'
     when: {|c: string| $c =~ '\bexport\s+[A-Za-z_][A-Za-z0-9_]*=' }
     says: "⛔ `export F=1` is bash: here the environment is `$env.F = 1` (and it dies with the call — pass what a child needs explicitly)."}
    {name: 'bash-exit-code'
     when: {|c: string| $c =~ '\$\?' }
     says: "⛔ The bash exit-code variable does not exist here: the code is `$env.LAST_EXIT_CODE` — or better, `cmd | complete` and read `.exit_code`."}
    {name: 'sort-uniq'
     when: {|c: string| $c =~ '\bsort\s+-[a-zA-Z]*u' }
     says: "⛔ `sort -u` is bash: nushell dedupes with `sort | uniq` (or `sort-by` first for keyed sorts)."}
    {name: 'mkdir-parents'
     when: {|c: string| $c =~ '\bmkdir\s+-[a-zA-Z]*p' }
     says: "⛔ `mkdir -p` is bash: nushell's `mkdir` makes parents implicitly and takes several dirs at once — `mkdir a/b c`."}
    {name: 'for-do-done'
     when: {|c: string| $c =~ '\bfor\s+\w+\s+in\b.*;\s*do\b' }
     says: "⛔ for-in-do-done is bash: nushell is `for x in [1 2 3] { print $x }` — and a list plus `each` is usually clearer."}
    {name: 'then-fi'
     when: {|c: string| $c =~ ';\s*then\b' }
     says: "⛔ `if …; then …; fi` is bash: nushell is `if (cond) { … } else { … }` — blocks, no keywords."}
    {name: 'test-bracket'
     when: {|c: string| $c =~ '\[\s*-[a-zA-Z]' }
     says: "⛔ The bracket test is bash: nushell asks the value — `('x' | path exists)`, `($x == 'y')`, `($x | is-empty)`."}
    {name: 'caret-builtin'
     when: {|c: string| $c =~ '\^(str|into|split|get|select|save|lines|first|last|each|where|reduce|append|default|parse|describe|update|insert|upsert|flatten|skip|take|chunks|sort-by|group-by|any|all|wrap|transpose|scope|random|complete|ignore|table|hash|encode|decode|ansi|char|format|math|sort)\b' }
     says: "⛔ The caret is for EXTERNAL binaries only (caret git, caret rg); nushell builtins are called bare — `str trim`, not caret str."}
  ]
}

# One warn row: the shape teaches, the allow still goes out.
type WarnRule = record<name: string, when: closure, says: string>

# The warn table: the busy-wait shapes the deny table cannot name without
# breaking the measured <= 2 s race-gap exception. A sleep UNDER 10 s that is
# NOT the last statement is synchronization by duration — warn with the
# event-bound recipe.
def warn-rules []: nothing -> list<WarnRule> {
  [
    {name: 'sleep-sync'
     when: {|c: string|
        let hit: bool = ($c =~ '(?i)\bsleep\s+[\d.]+\s*(?:seconds?|secs?|sec|m|minutes?|min|h|hrs?|hours?)\b')
        let rest: string = ($c | parse -r '(?is)\bsleep\s+[\d.]+\s*[a-z]*\s*(?:;|\n)\s*(?<rest>.+)' | get -o 0.rest | default '' | str trim)
        $hit and (not ($rest | is-empty))
     }
     says: "⚠️ Event-bound waits (owner law 28/11): a sleep followed by work is busy-waiting — time is never the synchronization mechanism. Subscribe instead: `job spawn` + `job recv --timeout` (onFinish = the value arrives; onError = the timeout raises, wrap in try/catch), `watch` for changes, `cmd | complete` for process exit, `wait-until deadline probe` for readiness. The one exception is a <= 2 s mechanical race gap as the LAST statement. Law: fp-kb/notes/event-bound-waits.md."}
  ]
}

# double-quoted payload WITHOUT double backslash (unescape order is untractable; that case fails loud and gets fixed by hand)
def transform-inline [cmd: string]: nothing -> record {
  let m: string = ($cmd | parse -r '(?s)^\s*nu\s+(?:-c|--commands)\s+"(?<payload>.+)"\s*$' | get -o 0.payload | default '')
  if ($m | is-empty) or ($m =~ '\\\\') {
    { act: false }
  } else {
    mkdir /tmp/nu-inline
    let scriptPath: string = $"/tmp/nu-inline/nu-($m | hash md5 | str substring 0..10).nu"
    $m | save -f $scriptPath
    { act: true, script: $scriptPath }
  }
}

def main [--log: path = $DENIALS]: string -> nothing {
  let payload: record = ($in | from json)
  let cmd: string = ($payload | get -o tool_input.command | default '')
  if ($cmd | is-empty) { exit 0 }
  let sid: string = ($payload | get -o session_id | default '')

  # The table decides: the FIRST matching row denies, its message teaches.
  let hits: list<DenyRule> = (deny-rules | where {|r| try { do $r.when $cmd } catch { false } })
  if not ($hits | is-empty) {
    let hit: DenyRule = ($hits | first)
    log-denial $log $sid 'nushell-law' $hit.name 'shell' $cmd
    if $hit.name == 'blind-sleep' {
      let sl: string = (long-sleep $cmd)
      print -e $"⛔ Reactive law: blind sleep ($sl) is FORBIDDEN — be event-driven instead: `job spawn` + `job send 0` + `job recv --timeout` — the timeout raises an error, wrap it in try/catch — or `watch` as an event stream. Full recipe: KB notes/reactive-jobs.md. Short sleeps below 10s remain legal as measured retry-gaps."
    } else {
      print -e $hit.says
    }
    exit 2
  }

  # The warn table speaks (stderr) but never blocks: the deny table had no
  # hit, so this is an allow that teaches.
  let warns: list<WarnRule> = (warn-rules | where {|r| try { do $r.when $cmd } catch { false } })
  if not ($warns | is-empty) {
    print -e (($warns | first | get says))
  }

  let t: record = (transform-inline $cmd)
  if $t.act {
    let updated: record = ($payload | get tool_input | update command $"nu ($t.script)")
    print ({ hookSpecificOutput: {
      hookEventName: 'PreToolUse'
      permissionDecision: 'allow'
      permissionDecisionReason: $"double-quoted payload converted to script without an extra shell layer: ($t.script)"
      updatedInput: $updated
    } } | to json -r | print)
  }
  exit 0
}
