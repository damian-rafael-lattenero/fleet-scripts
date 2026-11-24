# test_session_find.nu — the pure-core proofs for lib/session-find.nu: the
# LIKE escape, the alive clause, the SQL assembly and the render projection.
use std/assert
use ../../lib/session-find.nu *

# 1. the LIKE escape doubles quotes and leaves clean text alone.
assert equal (sql-escape "O'Brien") "O''Brien"
assert equal (sql-escape "mirror") "mirror"
assert equal (sql-escape "a'b'c") "a''b''c"

# 2. the alive clause: default hides deleted/archived, --all widens.
assert equal (alive-clause false) "deleted = 0 AND archived = 0"
assert equal (alive-clause true) "1=1"

# 3. the SQL carries the escaped fragment, the alive clause, the order, the limit.
let sql: string = (find-sql "O'Brien" 5 false)
assert str contains $sql "LIKE '%O''Brien%'"
assert str contains $sql "deleted = 0 AND archived = 0"
assert str contains $sql "ORDER BY updated_at DESC LIMIT 5"
assert str contains (find-sql "" 15 true) "WHERE 1=1"

# 4. the render projection: empty title -> "", 50-char title cut at 45,
#    workspace reduced to its basename, status defaulted.
let long: string = "01234567890123456789012345678901234567890123456789"   # 50 chars
let rows: list<MatchRow> = (match-rows [
    {task_id: "abc-123", title: $long, workspace_path: "/Users/lattenero/Projects/foo", task_status: "completed", updated: "2026-11-24 10:00:00"}
    {task_id: "def-456", title: null, workspace_path: "/tmp/bar", task_status: null, updated: "2026-11-23 09:00:00"}
])
assert equal ($rows | length) 2
assert equal $rows.0.sid "abc-123"
assert equal ($rows.0.title | str length) 45
assert equal $rows.0.ws "foo"
assert equal $rows.0.status "completed"
assert equal $rows.1.title ""
assert equal $rows.1.status ""

print "test_session_find ok"
