# zcode-original.nu — structural proof of a script that LAUNCHES an app, so the
# test never opens one: it parses, it keeps the hub's single relative `use`,
# and --print answers with a tagged candidate (or the honest refusal) without
# touching the app. The path is resolved from THIS file (the house idiom), so
# the proof holds in a worktree as well as in the hub.
use std/assert

const SELF: path = (path self)
let HUB: path = ($SELF | path expand | path dirname | path dirname | path dirname)
let SCRIPT: string = ($HUB | path join 'scripts' 'zcode-original.nu' | into string)

assert ($SCRIPT | path exists) "the script is in the hub"
assert (nu-check $SCRIPT) "the script parses"

let src: string = (open --raw $SCRIPT)
# README rule: a script inside the hub imports its lib RELATIVELY; an absolute
# `use` here would mean the hub is cloning itself.
assert equal ($src | lines | where {|l| $l =~ '^use /' } | length) 0 "no absolute use"
assert str contains $src "use ../lib/versions.nu *"

# --print is the honest dry run: exit 0 + one tagged record when the machine
# carries an official build, exit 1 + the refusal text when it carries none.
let probe: record = (do { ^nu $SCRIPT --print } | complete)
assert ($probe.exit_code in [0 1]) $"unexpected exit ($probe.exit_code): ($probe.stderr)"
if $probe.exit_code == 1 {
    assert str contains $probe.stderr "no official ZCode found" $probe.stderr
} else {
    let pick: record = ($probe.stdout | from json)
    assert ($pick.kind in ["volume" "app" "dmg"]) $pick.kind
    assert ($pick.version =~ '^\d+\.\d+') $"not a version: ($pick.version)"
    assert ($pick.kind == "dmg" or ($pick.path | path exists)) $"dead candidate path: ($pick.path)"
}

print "zcode-original structural ok — print path proven, app untouched"
