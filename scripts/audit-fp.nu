#!/Users/lattenero/.local/bin/nu-nightly
# audit-fp.nu — U0 of the FP/concurrency audit: the mechanical inventory of
# the four suspect categories (forbidden reactive/blocking constructs,
# hand-rolled concurrency, impure clock/random/file IO, broad errors) over a
# repo's MAIN sources. This used to be four divergent copies (bot, brain,
# whatsapp, kap) that differed only in the repo constant and the scope globs;
# now it is one script and the differences are ARGUMENTS.
#
# Every hit is a SUSPECT for the U1 semantic review, not a verdict.
#
#   fleet audit-fp <repo> 'modules/*/src/main/**' 'x/src/main/**'
#   fleet audit-fp /Users/lattenero/Projects/kap 'kap-*/src/main/**'
#
# Default scope: modules/*/src/main/** (the house Kotlin layout). Exit is 0
# even with hits — this is an inventory, not a gate.
use ../lib/audit-fp.nu *

def scan [repo: path, label: string, pattern: string, scopes: list<string>]: nothing -> list<Hit> {
    let args: list<string> = ($scopes | each {|s| ['-g' (rg-glob $s)]} | flatten)
    let res: record<exit_code: int, stdout: string> = (do { ^rg -n --no-heading -e $pattern ($repo | into string) ...$args } | complete)
    if $res.exit_code != 0 { return [] }
    parse-hits $res.stdout $label ($repo | into string)
}

def main [repo?: path, ...scopes: string]: nothing -> nothing {
    let root: path = ($repo | default '.' | path expand)
    let globs: list<string> = (if ($scopes | is-empty) { ['modules/*/src/main/**'] } else { $scopes })
    let all: list<Hit> = ($CATEGORIES | each {|c| scan $root $c.name $c.pattern $globs } | flatten)
    let banner: string = ($root | path basename)

    print $"# Concurrency/FP audit — U0 mechanical inventory for ($banner)"
    print ''
    print $"Scope: ($globs | str join ' · ') \(tests excluded\)."
    print 'Every hit is a SUSPECT for the U1 semantic review, not a verdict.'
    print ''
    for c in $CATEGORIES {
        print (counts-line $all $c.name)
    }
    print ''
    for c in $CATEGORIES {
        for line in (category-report $all $c.name) {
            print $line
        }
        print ''
    }
}
