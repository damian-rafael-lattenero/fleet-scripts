#!/opt/homebrew/bin/nu
# Turn tap for diff-ask (0.9.26): ONE line per turn boundary into the plugin's
# inbox, so its server can record what each turn changed across ALL repos.
# UserPromptSubmit stdin carries {prompt, session_id, cwd}; Stop carries
# {last_assistant_message, session_id, cwd}. Same script for both events — the
# present field decides the kind. Laws: never break a prompt/turn (exit 0
# always), one O_APPEND line, no content in any log.

const INBOX: string = '/Users/lattenero/.zcode/diff-ask/turn-events.jsonl'
const CAP: int = 8000

def tap [payload: record]: nothing -> nothing {
  let prompt: string = ($payload | get -o prompt | default '')
  let reply: string = ($payload | get -o last_assistant_message | default '')
  let sid: string = ($payload | get -o session_id | default '')
  let cwd: string = ($payload | get -o cwd | default '')
  let has_prompt: bool = ($prompt | str trim | str length) > 0
  let has_reply: bool = ($reply | str trim | str length) > 0
  if (not $has_prompt) and (not $has_reply) { return }
  let evt: record = {
    type: (if $has_prompt { 'prompt' } else { 'stop' })
    sid: $sid
    cwd: $cwd
    prompt: ($prompt | str substring 0..<$CAP)
    reply: ($reply | str substring 0..<$CAP)
    at: (date now | date to-timezone UTC | format date '%Y-%m-%dT%H:%M:%S%.3fZ')
  }
  (($evt | to json -r) + (char newline)) | save --append $INBOX
}

def main []: string -> nothing {
  try {
    let payload: record = ($in | from json)
    tap $payload
  } catch {|e| null }
}
