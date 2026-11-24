# lib/session-find.nu — the pure core of session-find.nu: the LIKE escape,
# the alive clause, the SQL assembly and the render projection. The script
# keeps the effects (the sqlite read, the printing); everything here answers
# from its arguments alone.
export type MatchRow = record<sid: string, title: string, ws: string, status: string, updated: string>

# The user's text rides into a LIKE clause: '' is the SQL escape (the query is
# a local read-only one, but the boundary still escapes).
export def sql-escape [text: string]: nothing -> string {
    $text | str replace -a "'" "''"
}

# Default hides deleted/archived rows; --all widens to everything.
export def alive-clause [all: bool]: nothing -> string {
    if $all { "1=1" } else { "deleted = 0 AND archived = 0" }
}

# CONCATENATION, not interpolation: the SQL's literal parens — datetime(...),
# the LIKE groups — would parse as command calls inside $"..." (the
# psql-count law, re-measured on the first live run).
export def find-sql [text: string, limit: int, all: bool]: nothing -> string {
    let safe: string = (sql-escape $text)
    let alive: string = (alive-clause $all)
    (
        "SELECT task_id, title, workspace_path, task_status, datetime(updated_at / 1000, 'unixepoch', 'localtime') AS updated "
        + "FROM tasks WHERE " + $alive
        + " AND (task_id LIKE '%" + $safe + "%' OR title LIKE '%" + $safe + "%' OR workspace_path LIKE '%" + $safe + "%') "
        + "ORDER BY updated_at DESC LIMIT " + ($limit | into string)
    )
}

# The thin render projection: empty title -> "", long titles cut at 45 chars,
# workspace path reduced to its basename (the sid tail stays the handle).
export def match-rows [rows: list<any>]: nothing -> list<MatchRow> {
    $rows | each {|r|
        {
            sid: $r.task_id
            title: ($r.title | default "" | str substring 0..44)
            ws: ($r.workspace_path | path basename)
            status: ($r.task_status | default "")
            updated: $r.updated
        }
    }
}
