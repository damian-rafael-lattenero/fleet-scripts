# wrappers.nu — the four thin deploy wrappers (bot, brain, fork, whatsapp)
# carry no logic by design; their ONE invariant is structural: the canonical
# script and the nu binary they invoke must EXIST. A moved canonical script
# must fail the gate, not a deploy.
# covers: /Users/lattenero/Scripts/scripts/zcode-bot-kotlin-deploy.nu
# covers: /Users/lattenero/Scripts/scripts/zcode-brain-deploy.nu
# covers: /Users/lattenero/Scripts/scripts/zcode-fork-deploy.nu
# covers: /Users/lattenero/Scripts/scripts/zcode-whatsapp-kotlin-deploy.nu
use std/assert

const SELF: path = (path self)
let ROOT: path = ($SELF | path expand | path dirname | path dirname | path dirname)

def script-refs [src: string]: nothing -> list<string> {
    $src | parse -r 'const \w+_SCRIPT: string = "(?<p>[^"]+)"' | get p
}

def nu-refs [src: string]: nothing -> list<string> {
    $src | parse -r 'const NU: string = "(?<p>[^"]+)"' | get p
}

let wrappers: list<string> = (glob ($ROOT | path join "scripts" "zcode-*-deploy.nu"))
assert equal ($wrappers | length) 4 "the four wrappers are all present"

for w in $wrappers {
    let name: string = ($w | path basename)
    let src: string = (open --raw $w)
    let scripts: list<string> = (script-refs $src)
    assert equal ($scripts | length) 1 $"($name): exactly one canonical script const"
    for s in $scripts {
        assert equal ($s | path exists) true $"($name): canonical script missing — ($s)"
    }
    let nus: list<string> = (nu-refs $src)
    assert equal ($nus | length) 1 $"($name): exactly one nu binary const"
    for n in $nus {
        assert equal ($n | path exists) true $"($name): nu binary missing — ($n)"
    }
}

print "test_deploy_wrappers ok"
