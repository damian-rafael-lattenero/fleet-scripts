#!/opt/homebrew/bin/nu
# UserPromptSubmit hook: publish the user's prompt to agent-brain's bus so the
# brain learns the QUESTION side of every desktop session too (the bot path
# already publishes user.prompt; this closes the desktop gap — companion of
# session-learn.nu which publishes the reply on Stop).
# Contract (fork bundle zcode.cjs, hook-input builder nWo): UserPromptSubmit
# carries `prompt`, `session_id`, `cwd`.
#
# Laws: never break a prompt (every failure swallowed, exit 0 always);
# one atomic O_APPEND line per prompt; source "hook" + kind "user.prompt"
# (both whitelisted in BusEvents.SOURCES/KINDS); silence for trivial prompts
# (< 12 chars — taps and noise teach nothing); no prompt content in the log.

const BUS: string = '/Users/lattenero/.zcode/agent-brain/bus-events.jsonl'
const LOG: string = '/Users/lattenero/.zcode/hooks/logs/prompt-learn.jsonl'
const PROMPT_CAP: int = 4000

def learn [payload: record]: nothing -> nothing {
  let prompt: string = ($payload | get -o prompt | default '')
  let sid: string = ($payload | get -o session_id | default '')
  let ws: string = ($payload | get -o cwd | default '')
  let chars: int = ($prompt | str trim | str length)
  let now: int = (date now | into int) // 1_000_000 # epoch ms — into int is ns
  if $chars < 12 {
    (({at: $now, sid: $sid, chars: $chars, published: false, why: 'too short to teach'} | to json -r) + (char newline))
    | save --append $LOG
    return
  }
  let evt: record = {
    id: (random uuid | str replace -a '-' '')
    ts: (date now | date to-timezone UTC | format date '%Y-%m-%dT%H:%M:%S%.3fZ')
    kind: 'user.prompt'
    sid: $sid
    turn: ($now | into string)
    source: 'hook'
    payload: {
      title: ($ws | path basename)
      ws: $ws
      prompt_chars: $chars
      prompt: ($prompt | str substring 0..$PROMPT_CAP)
    }
  }
  (($evt | to json -r) + (char newline)) | save --append $BUS
  (({at: $now, sid: $sid, chars: $chars, published: true} | to json -r) + (char newline))
  | save --append $LOG
}

def main []: string -> nothing {
  try {
    let payload: record = ($in | from json)
    learn $payload
  } catch {|e| null }
}
