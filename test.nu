#!/usr/bin/env nu
# test.nu — THE hub gate: nu-check every script (scripts/, hooks included),
# every lib core and every nushell-fp module (syntax/compile only, nothing
# runs), then run every test: the hub's own (tests/lib mirrors lib/,
# tests/scripts mirrors scripts/) and nushell-fp's suite. Offenders are
# reported by name; a failing script makes the gate exit non-zero.
#
#   nu ~/Scripts/test.nu          the whole machine contract
#   nu ~/Scripts/test.nu --ci     same, minus the machine-only legs (the
#                                 tests/scripts layer checks symlinks and
#                                 config.nu, which a runner does not have)

const SELF: path = (path self)

def local-path [root: path, relative: string]: nothing -> path {
    ($root | path join $relative)
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
        error make {msg: ("nu-check failed: " + ($bad | str join ", "))}
    }

    let runnable: list<string> = (if $ci {
        $hub_tests | where {|t| not ($t | str contains '/tests/scripts/')}
    } else {
        $hub_tests
    })
    let tests: list<string> = ($runnable | append $fp_tests)

    let failures: list<string> = ($tests | each {|script|
        let run: record<exit_code: int, stdout: string, stderr: string> = (nu $script | complete)
        if $run.exit_code == 0 {
            print ($run.stdout | str trim)
            null
        } else {
            print ($run.stderr | str trim)
            $script
        }
    } | where {|s| $s != null})

    if ($failures | is-empty) {
        print $"ALL GREEN — ($tests | length) test scripts, ($modules | length) lib modules, ($scripts | length) scripts, ($fp_tests | length) fp tests"
    } else {
        error make {msg: ("failing test scripts: " + ($failures | str join ", "))}
    }
}
