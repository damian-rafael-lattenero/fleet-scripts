#!/usr/bin/env nu
# canon-survey.nu — the Kotlin `var` / `!!` survey (U10, plan-denotational-engine).
# Counts, per package directory, two mechanical signals the Canon cares about:
#   var  — mutable declarations (`\bvar\s+[A-Za-z_<]`)
#   !!   — non-null assertions
# rg respects .gitignore, so build/ and vendor trees stay out. Counts are an
# approximation (string/comment occurrences included) — fine for a trend line:
# the instrument is identical every weekly sample, so the DELTA is honest.
#
# Usage: canon-survey.nu [repo...]  (default: agent-brain + zcode-bot-kotlin)

# One signal over one repo: `rg -n` rows `path:line:content` → {package, hits}.
def scan [
  repo: string,
  pattern: string,
]: nothing -> table<package: string, hits: int> {
    let res: record<stdout: string, exit_code: int> = (do { ^rg -n --glob '*.kt' --no-heading -e $pattern $repo } | complete)
    if ($res.exit_code != 0) and ($res.stdout | is-empty) {
        return []
    }
    $res.stdout
    | lines
    | each {|row|
        let parts = ($row | split column --number 3 ':' | into record)
        {package: ($parts.column0 | path dirname)}
    }
    | group-by package
    | items {|pkg, rows| {package: $pkg, hits: ($rows | length)}}
    | sort-by package
}

# Hits of a scan within one package (0 when the scan found nothing there).
def hits-of [
  rows: table<package: string, hits: int>,
  pkg: string,
]: nothing -> int {
    let hits: list<int> = ($rows | where package == $pkg | get -o hits | default [])
    if ($hits | is-empty) { return 0 }
    $hits | math sum
}

# The survey for one repo: files + both signals, per package directory.
export def survey [
  repo: string,
]: nothing -> table<repo: string, package: string, files: int, var: int, bang: int> {
    let files: list<string> = (do { ^rg --files --glob '*.kt' $repo } | complete | get stdout | lines)
    let var: table<package: string, hits: int> = (scan $repo '\bvar\s+[A-Za-z_<]')
    let bang: table<package: string, hits: int> = (scan $repo '!!')
    let packages = ($files
        | each {|f| ($f | path dirname)}
        | uniq
        | sort)
    $packages
    | wrap package
    | each {|r|
        {
            repo: ($repo | path basename),
            package: $r.package,
            files: ($files | where {|f| ($f | path dirname) == $r.package} | length),
            var: (hits-of $var $r.package),
            bang: (hits-of $bang $r.package),
        }
    }
    | sort-by var
}

export def main [...repos: string]: nothing -> table<repo: string, package: string, files: int, var: int, bang: int> {
    let targets: list<string> = (if ($repos | is-empty) {
        [/Users/lattenero/Projects/agent-brain /Users/lattenero/Projects/zcode-bot-kotlin]
    } else {
        $repos
    })
    $targets | each {|r| survey $r} | flatten
}
