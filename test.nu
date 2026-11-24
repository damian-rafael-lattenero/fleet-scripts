#!/usr/bin/env nu
# test.nu — gate for ~/Scripts: nu-check every script and every lib module
# (syntax/compile only, nothing runs), then run every tests/*.nu script.
# Offenders are reported by name; a failing script makes the gate exit non-zero.
#
#   nu ~/Scripts/test.nu

const SELF: path = (path self)

def main []: nothing -> nothing {
    let root: path = ($SELF | path dirname)
    let scripts: list<string> = (glob ($root | path join '*.nu') | sort)
    let modules: list<string> = (glob ($root | path join 'lib/*.nu') | sort)
    let tests: list<string> = (glob ($root | path join 'tests/*.nu') | sort)

    let bad_modules: list<string> = (($scripts | append $modules) | where {|m| not (nu-check $m)})
    if not ($bad_modules | is-empty) {
        error make {msg: ("nu-check failed: " + ($bad_modules | str join ", "))}
    }

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
        print $"ALL GREEN — ($tests | length) test scripts, ($modules | length) lib modules, ($scripts | length) scripts"
    } else {
        error make {msg: ("failing test scripts: " + ($failures | str join ", "))}
    }
}
