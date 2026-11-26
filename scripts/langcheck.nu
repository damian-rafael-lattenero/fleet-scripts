#!/usr/bin/env nu
# langcheck.nu — the English gate (owner 2026-11-26).
# lang-ok: detector input (the gate itself carries the Spanish word lists)
# Walk the owned roots and report every file, line or basename that still says
# Spanish. A file whose first three lines carry a `lang-ok:` pragma is skipped,
# and so is any path under a prefix listed in the allowlist, with its reason.
# Worktrees are skipped by default; --include-worktrees scans a branch before
# it is merged (it also enables hidden entries, which is where .worktrees lives).
#
#   nu ~/Scripts/scripts/langcheck.nu ~/Projects ~/Scripts
#   nu ~/Scripts/scripts/langcheck.nu ~/Projects/agent-brain --mode files
#   nu ~/Scripts/scripts/langcheck.nu ~/Projects/.worktrees/repo --include-worktrees
use ../lib/lang-detect.nu *

const EXTS: list<string> = ['md' 'txt' 'kt' 'kts' 'nu' 'hs' 'ts' 'tsx' 'js' 'jsx' 'py' 'sh' 'sql' 'yaml' 'yml' 'json' 'toml' 'plist' 'cabal' 'tex' 'nix']

const SKIP: list<string> = ['/node_modules/' '/build/' '/dist/' '/.gradle/' '/.kotlin/' '/official/' '/third-party/' '/vendor/' '/target/' '/.git/' '/Backups/' '/.worktrees/' '/evals/artifacts/' '/.nu-orphans-archive/' '/archive/']

type Allow = record<prefix: string, reason: string>
type Finding = record<path: string, line: int, kind: string, text: string>
type Run = record<exit_code: int, stdout: string, stderr: string>

def skipped? [path: string, skip: list<string>]: nothing -> bool {
    $skip | any {|seg| $path | str contains $seg }
}

def ext-of [path: string]: nothing -> string {
    $path | path parse | get extension | str lowercase
}

def load-allow [file: path]: nothing -> list<Allow> {
    if not ($file | path exists) { return [] }
    open --raw $file
    | lines
    | where {|l| (not ((($l | str trim)) | is-empty)) and (not ((($l | str trim)) | str starts-with '#')) }
    | each {|l|
        let parts: list<string> = ($l | split row "\t")
        {prefix: ($parts | first | str trim), reason: ($parts | get -o 1 | default '' | str trim)}
    }
}

# macOS reports temp paths as /var/... while rg returns the resolved
# /private/var/... twin; the allowlist must compare the same form.
def plain [path: string]: nothing -> string {
    $path
    | str replace --regex '^/private/var/' '/var/'
    | str replace --regex '^/private/tmp/' '/tmp/'
    | str replace --regex '^/private/etc/' '/etc/'
}

def allowed? [path: string, allow: list<Allow>]: nothing -> bool {
    let p: string = (plain $path)
    $allow | any {|a|
        let q: string = (plain $a.prefix)
        ($p == $q) or ($p | str starts-with ($q + '/'))
    }
}

def glob-args []: nothing -> list<string> {
    $EXTS | each {|e| $'--glob=*.($e)' }
}

def all-files [roots: list<string>, skip: list<string>, extra: list<string>]: nothing -> list<string> {
    let globs: list<string> = (glob-args)
    $roots | each {|root|
        let run: Run = (^rg --files --no-messages ...$globs ...$extra $root | complete)
        if $run.exit_code == 0 { $run.stdout | lines } else { [] }
    } | flatten | where {|f| (not (skipped? $f $skip)) and ((ext-of $f) in $EXTS) } | sort | uniq
}

def content-candidates [roots: list<string>, skip: list<string>, extra: list<string>]: nothing -> list<string> {
    let coarse: string = (coarse-pattern)
    let globs: list<string> = (glob-args)
    $roots | each {|root|
        let run: Run = (^rg -l --no-messages -e $coarse ...$globs ...$extra $root | complete)
        if $run.exit_code == 0 { $run.stdout | lines } else { [] }
    } | flatten | where {|f| not (skipped? $f $skip) } | sort | uniq
}

def content-findings [files: list<string>]: nothing -> list<Finding> {
    let coarse: string = (coarse-pattern)
    $files | each {|f|
        let head: list<string> = (open --raw $f | lines | first 3)
        if (has-pragma? $head) { [] } else {
            let hits: list<any> = (open --raw $f | lines | enumerate | where {|it| ($it.item =~ $coarse) and (spanish-line? $it.item) })
            $hits | each {|it|
                let kind: string = (if ($it.item =~ $ACCENT) { 'accent' } else { 'words' })
                {path: $f, line: ($it.index + 1), kind: $kind, text: ($it.item | str trim | str substring 0..110)}
            }
        }
    } | flatten
}

def main [...roots: string, --mode: string = 'all', --allow: path, --json, --limit: int = 1000, --include-worktrees]: nothing -> nothing {
    let home: string = $env.HOME
    if not ($mode in ['files' 'names' 'all']) {
        error make {msg: $"unknown --mode ($mode): use files, names or all"}
    }
    let defaults: list<string> = [$'($home)/Projects' $'($home)/Scripts' $'($home)/evals']
    let chosen: list<string> = (if ($roots | is-empty) { $defaults } else { $roots })
    let effective: list<string> = ($chosen | path expand)
    let skip: list<string> = (if $include_worktrees { $SKIP | where {|s| $s != '/.worktrees/' } } else { $SKIP })
    let extra: list<string> = (if $include_worktrees { ['--hidden'] } else { [] })
    let allow_file: path = ($allow | default ($home | path join 'Scripts' 'langcheck-allow.tsv'))
    let allow_list: list<Allow> = (load-allow $allow_file)

    let files: list<string> = (if $mode == 'files' { [] } else { all-files $effective $skip $extra })
    let names: list<Finding> = ($files
        | where {|f| (spanish-name? ($f | path basename)) and (not (allowed? $f $allow_list)) }
        | each {|f| {path: $f, line: 0, kind: 'name', text: ($f | path basename)} })
    let content: list<Finding> = (if $mode == 'names' { [] } else { content-findings (content-candidates $effective $skip $extra) })
    let findings: list<Finding> = (($names | append $content)
        | where {|h| not (allowed? $h.path $allow_list) }
        | sort-by path line
        | first $limit)

    if $json {
        print ($findings | to json -r)
    } else {
        if not ($findings | is-empty) {
            $findings | each {|h| $"($h.path)\t($h.line)\t($h.kind)\t($h.text)" } | str join (char nl) | print
        }
        print -e $"langcheck: ($findings | length) findings — roots: ($effective | str join ', ')"
    }
    if ($findings | is-empty) { exit 0 } else { exit 1 }
}
