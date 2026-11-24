#!/opt/homebrew/bin/nu
# SessionStart hook: warns when the nushell-kb mirror is stale.
# stdin: hook JSON payload (ignored). stdout: strict HookJSONOutput.
# Laws: never break session start (total try/catch, always exit 0); silence on
# any failure; LOCAL check only (head committerdate — no network at boot; the
# pull + reindex stay with scripts/update-kb.nu); speak ONLY when stale.
# Gotcha law baked in: in $"..." EVERY (...) is EVALUATED — prose in parens
# inside interpolated strings is forbidden (it runs commands at runtime).

const MIRROR: string = '/Users/lattenero/Projects/nushell-kb/official'
const STALE_DAYS: int = 21
const NS_PER_DAY: int = 86_400_000_000_000

def freshness-warning [mirror: string, stale_days: int]: nothing -> string {
  let res: record = (do { git -C $mirror log -1 '--format=%cI' } | complete)
  if $res.exit_code != 0 {
    return ''
  }
  let head_date: datetime = ($res.stdout | str trim | into datetime)
  let age_days: int = (((date now) - $head_date) | into int) // $NS_PER_DAY
  if $age_days > $stale_days {
    $"⚖️ nushell-kb mirror is ($age_days) days old — run `nu ~/Projects/nushell-kb/notes/scripts/update-kb.nu` — pull + reindex, so rag_query keeps teaching the current release."
  } else {
    ''
  }
}

def main []: string -> nothing {
  let warning: string = (try { freshness-warning $MIRROR $STALE_DAYS } catch { '' })
  if ($warning | str trim) != '' {
    { hookSpecificOutput: { hookEventName: 'SessionStart', additionalContext: $warning } } | to json -r | print
  }
}
