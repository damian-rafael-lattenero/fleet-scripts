#!/usr/bin/env nu
# test.nu — THE hub gate, and the fleet's ONE verification command:
#   nu-check every hub script, lib core, hook and nushell-fp module,
#   run every hub test (tests/**) and the fp suite, then every repo's tests
#   found on the machine (lib/census.nu holds the root map), and finally the
#   census itself — the law that every script has a test.
# Offenders are named; any failure makes the gate exit non-zero.
#
#   nu ~/Scripts/test.nu          the whole machine contract
#   nu ~/Scripts/test.nu --ci     hub + fp only (no machine paths, no symlinks,
#                                 no config.nu — what a CI runner can prove)
use lib/census.nu *
use lib/run-nu.nu ide-errors

const SELF: path = (path self)

def local-path [root: path, relative: string]: nothing -> path {
    ($root | path join $relative)
}

def run-all [tests: list<string>]: nothing -> list<string> {
    $tests | each {|script|
        let run: record<exit_code: int, stdout: string, stderr: string> = (nu $script | complete)
        if $run.exit_code == 0 {
            print ($run.stdout | str trim)
            null
        } else {
            print ($run.stderr | str trim)
            $script
        }
    } | where {|s| $s != null}
}

def main [--ci]: nothing -> nothing {
    let root: path = (($SELF | path expand) | path dirname)
    let fp: path = (local-path $root 'nushell-fp')

    let scripts: list<string> = (glob (local-path $root 'scripts/**/*.nu') | sort)
    let modules: list<string> = ((glob (local-path $root 'lib/**/*.nu')) ++ (glob (local-path $fp 'mods/*.nu')) | sort)
    let aux: list<string> = ((glob (local-path $fp 'scripts/*.nu')) | sort)
    let hub_tests: list<string> = (glob (local-path $root 'tests/**/*.nu') | sort)
    let fp_tests: list<string> = (glob (local-path $fp 'tests/*.nu') | sort)

    let bad: list<string> = (($scripts | append $modules | append $aux) | where {|m| not (nu-check $m)})
    if not ($bad | is-empty) {
        # the offenders' own diagnostics, located (28/11: ide-check lists ALL
        # parse errors, not just the first the caret would show)
        let details: list<string> = ($bad | each {|m|
            $"($m): ((ide-errors $m | str join ' | '))"
        })
        error make {msg: ("nu-check failed:\n" + ($details | str join "\n"))}
    }

    let runnable: list<string> = (if $ci {
        $hub_tests | where {|t| not ($t | str contains '/tests/scripts/')}
    } else {
        $hub_tests
    })
    let own_tests: list<string> = ($runnable | append $fp_tests)

    let failures: list<string> = (run-all $own_tests)
    if not ($failures | is-empty) {
        error make {msg: ("failing test scripts: " + ($failures | str join ", "))}
    }

    # The machine leg: every repo's tests, run from here. Skipped on --ci (the
    # paths are this Mac's) and always AFTER the hub's own, so a broken hub
    # fails before 213 scripts are walked.
    let machine_tests: list<string> = (if $ci { [] } else {
        tests-under $ROOTS | where {|t| not ($t | str starts-with $root)}
    })
    let machine_failures: list<string> = (run-all $machine_tests)
    if not ($machine_failures | is-empty) {
        error make {msg: ("failing repo test scripts: " + ($machine_failures | str join ", "))}
    }

    print $"ALL GREEN — ($own_tests | length) hub+fp tests, ($machine_tests | length) repo tests, ($modules | length) modules, ($scripts | length) scripts"
}
