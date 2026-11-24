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

print "lib/fleet ok"
