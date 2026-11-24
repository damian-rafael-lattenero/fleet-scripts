#!/opt/homebrew/bin/nu
# SessionStart hook: injects recent brain memory as session context.
# stdin: hook JSON payload (ignored). stdout: strict HookJSONOutput (known keys only).
# Law: a down brain NEVER breaks session start — degrades with one honest line.

const BRAIN: string = '/Users/lattenero/Projects/agent-brain/core/build/install/agent-brain/bin/agent-brain'
const K: int = 8

def recent-memory [k: int]: nothing -> string {
  let res: record = (do { ^$BRAIN memory recent --k $k } | complete)
  if $res.exit_code != 0 {
    'brain degraded (CLI non-zero exit): recent memory unavailable this session.'
  } else {
    let rows: list<any> = ($res.stdout | from json)
    if ($rows | is-empty) {
      'brain has no recent memories.'
    } else {
      $rows | each {|m| $"- [($m.kind)] ($m.content)" } | str join (char newline)
    }
  }
}

def main []: string -> nothing {
  let text: string = (recent-memory $K)
  let ctx: string = [
    $"🧠 Recent brain memory — last ($K):"
    $text
    ''
    'Startup laws: ALL work output in ENGLISH (code, names, comments, docs, commits — conversation with the owner stays Spanish); consult rag_query before writing .nu (KB Nushell 0.116) and before designing/refactoring non-trivial code (FP-KB); web searches ONLY via serper; the ZCode Bash tool IS Nushell (write Nu directly, no `nu -c` wrapper; outside ZCode use `nu -c` or .nu scripts); the owner default terminal IS Nushell (Ghostty command = nu since 21/11 — config.nu + aliases load in every new tab, no `nu -c` needed there either; the OS UserShell stays /bin/zsh BY DESIGN, never suggest chsh).'
  ] | str join (char newline)
  { hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: $ctx } } | to json -r | print
}
