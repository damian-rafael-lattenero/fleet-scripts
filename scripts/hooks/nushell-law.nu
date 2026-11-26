#!/opt/homebrew/bin/nu
# PreToolUse(Bash): TWO mechanical laws in one hook.
# The Bash tool itself now runs Nushell (fork build 2026-11-17: nu -l -c), so a
# plain Nu command needs NO wrapper: the old "must contain nu -c" check is gone.
# 1) REACTIVE LAW: a blind sleep >= 10s is denied (job + mailbox or watch instead).
# 2) PAREN-WRAPPED LET LAW: `(let x = ...)` is a parse error; use a .nu script.
# The inline transform is kept for an explicit `nu -c "PAYLOAD"` (nested use).
# Never silent on deny: stderr = the reason the model reads.

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

  let sl: string = (long-sleep $cmd)
  if not ($sl | is-empty) {
    log-denial $log $sid 'nushell-law' 'blind-sleep' 'shell' $cmd
    print -e $"⛔ Reactive law: blind sleep ($sl) is FORBIDDEN — be event-driven instead: `job spawn` + `job send 0` + `job recv --timeout` — the timeout raises an error, wrap it in try/catch — or `watch` as an event stream. Full recipe: KB notes/reactive-jobs.md. Short sleeps below 10s remain legal as measured retry-gaps."
    exit 2
  }

  # PAREN-WRAPPED LET LAW (owner's radical fix, 2026-11-08): `let` is a statement
  # in Nushell — `(let x = ...)` is ALWAYS a parse error, and it kept recurring in
  # multi-inspection `nu -c` blocks. THE unique solution: one top-level `let` is
  # fine inline; the moment a payload needs a second binding — or a paren ever
  # wraps a let — STOP and write a .nu script file instead.
  if ($cmd =~ '(?m)\(\s*let\b') {
    log-denial $log $sid 'nushell-law' 'paren-let' 'shell' $cmd
    print -e "⛔ Paren-wrapped `let` law: `let` is a statement in Nushell — `(let x = ...)` is ALWAYS a parse error. THE fix: keep `let` at top level; the moment a `nu -c` payload needs a second binding, STOP and write a .nu script file (`nu scripts/x.nu`). Retry as a script."
    exit 2
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
