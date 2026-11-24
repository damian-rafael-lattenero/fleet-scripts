#!/opt/homebrew/bin/nu
# PreToolUse(Edit|Write): the ENGLISH law as mechanics (top-level maxim, 2026-11-06).
# ALL work output (code, names, comments, docs, commits) is ALWAYS English.
# This hook WARNS (never blocks) when comments look Spanish: accented chars (a, e, i, o, u, n, inverted punctuation)
# are an unambiguous signal, plus a few univocal Spanish words in comment lines.
# False positives only cost an advisory line; silence on English files is free.

def is-comment-line [l: string]: nothing -> bool {
  $l =~ '^\s*(//|#|--|/\*|\*|<!--|;;)'
}

def spanish-comment-lines [src: string]: nothing -> list<string> {
  $src
  | lines
  | where {|l| (is-comment-line $l) and (($l =~ '[áéíóúñü¿¡]') or ($l =~ '(?i)\b(que|para|pero|porque|también|además|archivo|función|devuelve|permite|corré|según|versión|código|opción|entonces|cuando|solamente|hacer)\b')) }
  | each {|l| $l | str trim | str substring 0..110 }
}

def main []: string -> nothing {
  let payload: record = ($in | from json)
  let ti: record = ($payload | get -o tool_input | default {})
  let file: string = ($ti | get -o file_path | default '')
  let body: string = (if ($payload | get -o tool_name | default '') == 'Write' { $ti | get -o content } else { $ti | get -o new_string } | default '')
  if ($file | is-empty) or ($body | is-empty) { exit 0 }
  if not ($file =~ '\.(kt|kts|ts|tsx|js|jsx|java|rs|py|nu|scala|go|rb|sh|sql|md|yaml|yml|toml)$') { exit 0 }

  let malas: list<string> = (spanish-comment-lines $body)
  if ($malas | is-empty) { exit 0 }
  let ctx: string = $"⚖️ English law on ($file | path basename) — these comment lines look Spanish: ($malas | str join ' ⏎ '). ALL work output is English by default — top-level maxim: code, names, comments, docs, commits. Rewrite them in English."
  { hookSpecificOutput: { hookEventName: 'PreToolUse', additionalContext: $ctx } } | to json -r | print
}
