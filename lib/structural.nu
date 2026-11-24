# structural.nu — the owner's proof for effect-only scripts (the law's mode B):
# they PARSE, the interpreter their shebang names EXISTS, and they do not
# import what the 24/11 restructure moved (a stale absolute path is a script
# that will die at 04:00 under launchd, where nobody is watching).
#
# That is exactly as far as a generic proof can go without the script's own
# semantics; anything richer belongs to the script's own test. Pure: paths in,
# findings out (no printing, no exit) — the family tests decide.
export type Finding = record<path: string, reason: string, detail: string>

const STALE: list<string> = [
    'Projects/nushell-fp/'
    'zcode-bot-kotlin/scripts/lib/deploy.nu'
]

def shebang [src: string]: nothing -> string {
    let first: string = ($src | lines | first)
    if $first =~ '^#!' { $first | str replace --regex '^#!' '' | str trim } else { '' }
}

# A shebang is honest when its interpreter resolves: an absolute path must
# point at a file; `/usr/bin/env X` must find X on PATH (the house's
# launchd-narrow-PATH trap, measured 10/11 — a plist's env is not the
# terminal's, so scripts that launchd runs directly pin the absolute path).
def resolves? [interp: string]: nothing -> bool {
    if ($interp | str starts-with '/usr/bin/env ') {
        let bin: string = ($interp | str replace '/usr/bin/env ' '')
        ((which $bin | length) > 0)
    } else {
        (($interp | path type) != null)
    }
}

def interpreter-missing [src: string]: nothing -> string {
    let interp: string = (shebang $src)
    let broken: bool = (not ($interp | is-empty)) and (not (resolves? $interp))
    if $broken { $interp } else { '' }
}

def stale-imports [src: string]: nothing -> list<string> {
    $src | lines | where {|l| ($l =~ '^use ') and ($STALE | any {|s| $l | str contains $s})}
}

export def findings [files: list<string>]: nothing -> list<Finding> {
    $files | each {|f|
        let src: string = (open --raw $f)
        let parse: list<Finding> = (if (nu-check $f) { [] } else { [{path: $f, reason: 'parse', detail: 'nu-check failed'}] })
        let interp: string = (interpreter-missing $src)
        let shebang_finding: list<Finding> = (if ($interp | is-empty) { [] } else { [{path: $f, reason: 'shebang', detail: $"($interp) does not exist"}] })
        let stale: list<Finding> = (stale-imports $src | each {|l| {path: $f, reason: 'stale-import', detail: ($l | str trim)}})
        $parse | append $shebang_finding | append $stale
    } | flatten
}
