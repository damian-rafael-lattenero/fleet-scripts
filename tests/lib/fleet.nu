# fleet.nu — the door's pure core: discovery (file list -> verbs), the six
# explicit alias rows, the union table and the TOTAL resolver. No filesystem
# here: the caller hands the file list in, so every case is a literal fixture.
use std/assert
use ../../lib/fleet.nu *

# 1. verbs: one row per file, verb = stem, and the door itself is not a verb.
let files: list<string> = [
    "/hub/scripts/brain.nu"
    "/hub/scripts/fleet.nu"
    "/hub/scripts/wt-done.nu"
]
let rows: list<Command> = (verbs $files)
assert equal ($rows | length) 2 "fleet.nu must not appear as a verb"
assert equal ($rows | get verb | sort) [brain wt-done]
assert equal ($rows | where {|r| $r.verb == 'brain'} | get 0.script) "/hub/scripts/brain.nu"

# 2. aliases: the five deploy verbs the owner types from memory + healthcheck,
#    each pointing at its real script (the zcode- prefix stays in the file).
let a: list<Command> = (aliases "/hub" "/skills/healthcheck.nu")
assert equal ($a | length) 6
assert equal ($a | where {|r| $r.verb == 'deploy-all'} | get 0.script) "/hub/scripts/zcode-deploy-all.nu"
assert equal ($a | where {|r| $r.verb == 'deploy-brain'} | get 0.script) "/hub/scripts/zcode-brain-deploy.nu"
assert equal ($a | where {|r| $r.verb == 'deploy-fork'} | get 0.script) "/hub/scripts/zcode-fork-deploy.nu"
assert equal ($a | where {|r| $r.verb == 'deploy-bot'} | get 0.script) "/hub/scripts/zcode-bot-kotlin-deploy.nu"
assert equal ($a | where {|r| $r.verb == 'deploy-whatsapp'} | get 0.script) "/hub/scripts/zcode-whatsapp-kotlin-deploy.nu"
assert equal ($a | where {|r| $r.verb == 'healthcheck'} | get 0.script) "/skills/healthcheck.nu"

# 3. verb-table: the union of both sources, sorted by verb (the listing order).
let t: list<Command> = (verb-table $a $rows)
assert equal ($t | length) 8
assert equal ($t | get verb) ($t | get verb | sort)
assert equal ($t | where {|r| $r.verb == 'brain'} | length) 1 "no verb may appear twice"

# 4. resolve is TOTAL: a hit answers exactly one row, a miss answers [] — the
#    refusal is the edge's decision, never the table's.
assert equal ((resolve "deploy-bot" $t) | get 0.script) "/hub/scripts/zcode-bot-kotlin-deploy.nu"
assert equal ((resolve "brain" $t) | get 0.script) "/hub/scripts/brain.nu"
assert equal (resolve "nope" $t) []

# 5. arguments-of: the SIGNATURE is the source. A multi-line signature with
#    flags, a defaulted flag, an optional positional and a rest parameter is
#    rendered compactly; the inline comments inside it never leak. The params
#    are newline-separated on purpose — the house style, and what the real
#    scripts (brain.nu, ram-clean.nu) do.
let src: string = ([
    '#!/usr/bin/env nu'
    '# thing.nu — a thing that does the thing with the stuff and more words here'
    '# and the paragraph continues on this line.'
    'def main ['
    '    repo?: path                # where the thing lives (never checked)'
    '    --k: int = 5               # how many'
    '    --fix                     # bool flag, no type'
    '    ...extra: string'
    ']: nothing -> nothing {'
    '    print 1'
    '}'
] | str join (char nl))
assert equal (arguments-of $src) '[repo] <path> · --k <int> · --fix · ...extra <string>'
assert equal (description-of $src) 'a thing that does the thing with the stuff and more words here and the paragraph continues on this line.'
assert equal (arguments-of 'def main []: nothing -> nothing { }') '-'
assert equal (arguments-of 'print 1') '-'

# 6. split-params: a comma inside a record type never splits; the newline is a
#    separator too (that is how the house writes signatures).
assert equal (split-params 'a: int, b: record<x: int, y: int>, c: string') ['a: int' 'b: record<x: int, y: int>' 'c: string']
assert equal (split-params 'a: int, b: int') ['a: int' 'b: int']

# 7. render-param: each shape has one label, and a typed value carries <type>.
assert equal (render-param 'question?: string') '[question] <string>'
assert equal (render-param 'repo: path') '"repo" <path>'
assert equal (render-param '--k: int = 5') '--k <int>'
assert equal (render-param '--fix') '--fix'
assert equal (render-param '...scopes: string') '...scopes <string>'

# 8. description-of and arguments-of agree with the kind discipline: a script
#    row and an alias row are both complete Commands (the listing needs no
#    extra lookup).
assert equal ($a | get kind | uniq) ['alias']
assert equal ($rows | get kind | uniq) ['script']

print "lib/fleet ok"
