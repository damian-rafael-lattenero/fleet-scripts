# test_aliases.nu — the owner's terminal verbs are config.nu aliases; every
# alias that targets a .nu script must point at an EXISTING file, and the
# five deploy entry points must exist as aliases (a renamed script or a
# typo'd alias must fail the gate, not the operator).
use std/assert

let cfg: path = ($nu.default-config-dir | path join "config.nu")
assert equal ($cfg | path exists) true $"config.nu not found at ($cfg)"

let targets: list<record> = (open --raw $cfg
    | lines
    | where {|l| $l =~ '^alias .*= \^/.*\.nu\s*$' }
    | parse -r '^alias (?<name>\S+) = \^(?<target>.+)$')

# every script-targeting alias resolves
for t in $targets {
    let target: string = ($t.target | str trim)
    assert equal ($target | path exists) true $"alias ($t.name): target missing — ($target)"
}

# the five deploy verbs are aliased (the phone/terminal entry points)
let names: list<string> = ($targets | get name)
for n in [zcode-deploy-all zcode-deploy-brain zcode-deploy-fork zcode-deploy-bot zcode-deploy-whatsapp] {
    assert equal ($n in $names) true $"alias ($n) missing from config.nu"
}

print $"test_aliases ok — ($targets | length) script aliases"
