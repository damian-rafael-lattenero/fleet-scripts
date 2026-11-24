# fleet.nu — the door's end-to-end invariants: the installed symlink, EVERY
# advertised verb resolving to a real file (a moved script must fail the gate,
# not a deploy), the two exit codes the callers depend on (0 for list, 2 for an
# unknown verb), and config.nu's side of the contract — one `fleet` alias, no
# per-script wrapper left behind.
use std/assert
use ../../lib/fleet.nu *

const SELF: path = (path self)
let HUB: path = ($SELF | path expand | path dirname | path dirname | path dirname)
let FLEET: string = ($nu.home-dir | path join '.local/bin/fleet' | into string)
let HC: string = ($nu.home-dir | path join '.agents/skills/fleet-healthcheck/scripts/healthcheck.nu' | into string)

# 1. the door is installed: a symlink whose target is this hub's fleet.nu.
assert equal ($FLEET | path type) "symlink" $"($FLEET) must be a symlink"
assert equal (((^readlink $FLEET | str trim) | path expand)) ($HUB | path join 'scripts' 'fleet.nu') "the link must point at the hub"

# 2. every advertised verb answers a file on disk — the table cannot lie — and
#    every script documents itself: `fleet list`'s description column is the
#    script's own header paragraph, so a headerless script is a blank row.
let rows: list<Command> = (verb-table (aliases $HUB $HC) (verbs (glob ($HUB | path join 'scripts' '*.nu'))))
for r in $rows {
    assert equal ($r.script | path exists) true $"verb ($r.verb): missing script — ($r.script)"
    assert ($r.kind in ['script' 'alias']) $"verb ($r.verb): kind must be script or alias, got ($r.kind)"
    let src: string = (open --raw $r.script)
    assert ((description-of $src) != '-') $"verb ($r.verb): no header paragraph to describe it"
    assert ((arguments-of $src) != '') $"verb ($r.verb): empty arguments cell"
}

# 3. the two exit codes the callers depend on: list is 0, an unknown verb is 2
#    (with the known verbs spoken on stderr, never a silent failure).
let ok: record<exit_code: int, stdout: string, stderr: string> = (do { ^$FLEET list } | complete)
assert equal $ok.exit_code 0 "fleet list must exit 0"
let bad: record<exit_code: int, stdout: string, stderr: string> = (do { ^$FLEET nope } | complete)
assert equal $bad.exit_code 2 "fleet <unknown> must exit 2"
assert ($bad.stderr =~ 'unknown verb') "the refusal must name the verb"

# 4. --json is the machine leg (the phone's discovery): the same rows, with the
#    script path the daemon spawns and nothing else. A consumer that cannot see
#    a verb cannot offer it, so the shape is pinned here.
let out: record<exit_code: int, stdout: string, stderr: string> = (do { ^$FLEET list --json } | complete)
assert equal $out.exit_code 0 "fleet list --json must exit 0"
let machine: list<record> = ($out.stdout | from json)
assert equal (($machine | length)) ($rows | length) "the json must carry every verb"
assert equal (($machine | get name | sort)) ($rows | get verb | sort)
for r in $machine {
    assert (($r.script | path exists)) $"json row ($r.name): script missing"
    assert (($r.kind in ['script' 'alias'])) $"json row ($r.name): kind must be script|alias"
    assert (($r.description | is-not-empty)) $"json row ($r.name): description is the phone's only doc"
}

# 5. config.nu's side: the one alias exists and no per-script wrapper survived
#    (the 24/11 consolidation: 17 entries died, 1 was born).
let cfg: string = (open --raw ($nu.default-config-dir | path join 'config.nu'))
assert ($cfg =~ 'alias fleet = \^/') "config.nu must alias fleet"
assert (not ($cfg =~ '\^/Users/lattenero/Scripts/')) "config.nu must not exec hub paths directly"
assert (not ($cfg =~ 'alias zcode-deploy-')) "the five deploy aliases are the door's verbs now"

print $"scripts/fleet ok — ($rows | length) verbs, exit codes pinned"
