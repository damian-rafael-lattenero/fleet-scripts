#!/Users/lattenero/.local/bin/nu-nightly
# fleet.nu — THE door to the hub. One stable name for every script in
# scripts/: codes, launchd and the terminal all say `fleet <verb> [args...]`
# instead of a path, so moving a script never breaks a caller again.
#
# Adding a script IS adding a verb: the table is a glob over scripts/*.nu plus
# the five deploy verbs the owner's muscle memory knows and healthcheck (in
# the skills tree). The pure half — discovery, the alias rows, the total
# resolver — lives in lib/fleet.nu and is proven in tests/lib/fleet.nu.
#
# Exit code and stdio belong to the child: run-external inherits both and a
# non-zero child ends this process with its exact code (measured 0.117).
#
#   fleet list                  every verb and the script behind it
#   fleet <verb> [args...]      run it with the same interpreter as fleet
#
# The symlink ~/.local/bin/fleet points here, so `use` must be ABSOLUTE: a
# relative path would resolve from ~/.local/bin (the path as invoked), not
# from this file — measured 24/11: `use ../lib/fleet.nu` died with
# module-not-found through the link. This is the one absolute import inside
# the hub, and the same line every repo consumer writes.
use /Users/lattenero/Scripts/lib/fleet.nu *

const SELF: path = (path self)

def root []: nothing -> path {
    ($SELF | path expand | path dirname | path dirname)
}

def healthcheck-script []: nothing -> path {
    ($nu.home-dir | path join '.agents/skills/fleet-healthcheck/scripts/healthcheck.nu')
}

def verb-rows []: nothing -> list<Command> {
    let hub: path = (root)
    let files: list<string> = (glob ($hub | path join 'scripts' '*.nu'))
    verb-table (aliases $hub (healthcheck-script)) (verbs $files)
}

def usage [rows: list<Command>]: nothing -> nothing {
    print 'fleet — the single door to ~/Scripts/scripts'
    print ''
    print 'usage: fleet <verb> [args...]'
    print '       fleet list   every verb and the script behind it'
    print '       fleet help   this text'
    print ''
    $rows | each {|c| {verb: $c.verb, script: ($c.script | path basename)}} | print
}

def unknown [verb: string, rows: list<Command>]: nothing -> nothing {
    let known: string = ($rows | get verb | str join ', ')
    print -e $"fleet: unknown verb '($verb)' — known: ($known)"
    exit 2
}

def --wrapped main [...args: string]: nothing -> nothing {
    let rows: list<Command> = (verb-rows)
    let verb: string = (if ($args | is-empty) { 'list' } else { $args | first })
    let rest: list<string> = ($args | skip 1)
    if $verb in ['list' 'help' '--help' '-h'] {
        usage $rows
        return
    }
    let hits: list<Command> = (resolve $verb $rows)
    if ($hits | is-empty) {
        unknown $verb $rows
    }
    let cmd: Command = ($hits | first)
    run-external $nu.current-exe $cmd.script ...$rest
}
