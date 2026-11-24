#!/usr/bin/env nu
# test.nu — gate for the nushell-fp library: nu-check every module, then run every
# tests/*.nu script. Failing modules/scripts are reported by name.

const SELF: path = (path self)

def main []: nothing -> nothing {
    let root: path = ($SELF | path dirname)
    let modules: list<string> = (glob ($root | path join mods '*.nu') | sort)
    let scripts: list<string> = (glob ($root | path join tests '*.nu') | sort)

    let bad_modules: list<string> = ($modules | where {|m| not (nu-check $m)})
    if not ($bad_modules | is-empty) {
        error make {msg: ("nu-check failed: " + ($bad_modules | str join ", "))}
    }

    let failures: list<string> = ($scripts | each {|script|
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
        print "ALL GREEN"
    } else {
        error make {msg: ("failing test scripts: " + ($failures | str join ", "))}
    }
}
