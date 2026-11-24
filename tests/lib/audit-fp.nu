# audit-fp.nu — the inventory's pure core: the glob anchoring that makes rg
# match under an absolute root, the rg-line parser, and the markdown pieces.
use std/assert
use ../../lib/audit-fp.nu *

# 1. rg-glob: a bare glob is anchored, an absolute or already-anchored one is
#    left alone (the 24/11 measurement: 0 hits vs 16 for the same tree).
assert equal (rg-glob 'modules/*/src/main/**') '**/modules/*/src/main/**'
assert equal (rg-glob '**/src/main/**') '**/src/main/**'
assert equal (rg-glob '/abs/src/**') '/abs/src/**'

# 2. parse-hits: path, line and the rest (which may contain ':') survive.
let stdout: string = ([
    '/repo/src/a.kt:12:synchronized (lock) {'
    ''
    '/repo/src/b.kt:7:map.forEach { x -> x }'
] | str join (char nl))
let hits: list<Hit> = (parse-hits $stdout 'handrolled' '/repo')
assert equal ($hits | length) 2 "blank lines are dropped"
assert equal ($hits | get 0.file) 'src/a.kt'
assert equal ($hits | get 0.line) 12
assert equal ($hits | get 0.text) 'synchronized (lock) {'
assert equal ($hits | get 1.line) 7
assert equal (($hits | get 1).category) 'handrolled'

# 3. counts-line and category-report: the report's two shapes.
assert equal (counts-line $hits 'handrolled') '- **handrolled**: 2'
assert equal (counts-line $hits 'forbidden') '- **forbidden**: 0'
let empty: list<string> = (category-report $hits 'forbidden')
assert equal ($empty | last) '(none)'
let filled: list<string> = (category-report $hits 'handrolled')
assert equal ($filled | get 0) '## handrolled'
assert equal ($filled | get 2) '| file | line | text |'
assert (($filled | get 4) | str contains '`src/a.kt`')

print "lib/audit-fp ok"
