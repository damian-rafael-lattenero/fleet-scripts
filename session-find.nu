#!/opt/homebrew/bin/nu
# session-find.nu — find a ZCode session by ANY fragment: title, workspace
# path, or sid (the full uuid or its tail). One command from any terminal;
# the answer names the sid + workspace so the bot's attach (or a /tasks tap)
# can aim at it. READ-ONLY: the tasks-index opens mode=ro, the CLI db is
# never touched.
#
#   session-find mirror          # any session naming "mirror"
#   session-find aae68169        # the sid tail finds the session directly
#   session-find pg-base --all   # include deleted/archived rows too
#
# The index only knows what the fork's task list knows; sessions the fork
# never titled show with an empty title and their sid tail as the handle.

const INDEX: string = "/Users/lattenero/.zcode/v2/tasks-index.sqlite"

# Render the matches as the thin table (the render laws: local theme —
# nested nu does not load config.nu — measured 21/11).
$env.config.table.mode = "thin"

def main [
    text: string          # title / workspace / sid fragment ('' lists the latest)
    --limit: int = 15     # newest N matches
    --all                 # include deleted and archived rows too
]: nothing -> nothing {
    # the user's text rides into a LIKE clause — the '' doubling is the
    # SQL escape (a local read-only query, but the boundary still escapes)
    let safe: string = ($text | str replace -a "'" "''")
    let alive: string = (if $all { "1=1" } else { "deleted = 0 AND archived = 0" })
    # CONCATENATION, not interpolation: the SQL's literal parens — datetime(...),
    # the LIKE groups — would parse as command calls inside $"..." (the
    # psql-count law, re-measured here on the first live run)
    let sql: string = (
        "SELECT task_id, title, workspace_path, task_status, datetime(updated_at / 1000, 'unixepoch', 'localtime') AS updated "
        + "FROM tasks WHERE " + $alive
        + " AND (task_id LIKE '%" + $safe + "%' OR title LIKE '%" + $safe + "%' OR workspace_path LIKE '%" + $safe + "%') "
        + "ORDER BY updated_at DESC LIMIT " + ($limit | into string)
    )
    let out: record = (do { ^sqlite3 -json $"file:($INDEX)?mode=ro" $sql } | complete)
    if $out.exit_code != 0 {
        print -e $"✗ the index read failed: ($out.stderr | str trim | str substring 0..160)"
        exit 1
    }
    let rows: list<any> = (if ($out.stdout | str trim | is-empty) { [] } else { $out.stdout | from json })
    if ($rows | is-empty) {
        print $"no sessions match '($text)' — --all widens to deleted/archived"
        return
    }
    print ($rows
        | each {|r|
            {
                sid: $r.task_id
                title: ($r.title | default "" | str substring 0..44)
                ws: ($r.workspace_path | path basename)
                status: ($r.task_status | default "")
                updated: $r.updated
            }
        }
        | table)
    print $"($rows | length) matches — the sid is the attach handle"
}
