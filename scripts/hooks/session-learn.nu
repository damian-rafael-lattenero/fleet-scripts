#!/opt/homebrew/bin/nu
# Stop hook: publish the turn's final reply to agent-brain's bus so EVERY
# ZCode session learns — not only the bot-bound conversation (owner's order,
# 2026-11-08). Contract (fork bundle zcode.cjs, hook-input builder): the Stop
# event carries `last_assistant_message` (= responseText ?? responsePreview),
# `session_id` and `cwd`, so no transcript parsing is needed.
#
# Laws:
# - never break a turn: every failure is swallowed (hook exit is always 0);
# - one atomic O_APPEND line per turn into the brain's bus file;
# - source "hook" (whitelisted in BusEvents.SOURCES) + kind "turn.completed";
# - payload.reply carries the reply — mandatory for the memory worker (P3);
# - silence when the reply is empty (silence is data), one tiny log line either
#   way (no reply content in the log — it goes only to the bus).

const BUS: string = '/Users/lattenero/.zcode/agent-brain/bus-events.jsonl'
const LOG: string = '/Users/lattenero/.zcode/hooks/logs/session-learn.jsonl'
const REPLY_CAP: int = 8000

def learn [payload: record]: nothing -> nothing {
  let reply: string = ($payload | get -o last_assistant_message | default '')
  let sid: string = ($payload | get -o session_id | default '')
  let ws: string = ($payload | get -o cwd | default '')
  let chars: int = ($reply | str trim | str length)
  let now: int = (date now | into int) // 1_000_000 # epoch ms — into int is ns
  if $chars == 0 {
    (({at: $now, sid: $sid, chars: 0, published: false, why: 'empty reply'} | to json -r) + (char newline))
    | save --append $LOG
    return
  }
  let evt: record = {
    id: (random uuid | str replace -a '-' '')
    ts: (date now | date to-timezone UTC | format date '%Y-%m-%dT%H:%M:%S%.3fZ')
    kind: 'turn.completed'
    sid: $sid
    turn: ($now | into string)
    source: 'hook'
    payload: {
      reply: ($reply | str substring 0..$REPLY_CAP)
      title: ($ws | path basename)
      model: 'session'
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
