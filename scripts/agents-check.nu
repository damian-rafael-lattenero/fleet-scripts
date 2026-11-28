#!/opt/homebrew/bin/nu
# agents-check.nu — the proof for an instruction file, and AGENTS.md is the one
# that matters: every citation in it — a hook or hub script, a path, a
# repo-relative path, a `fleet` verb, an MCP tool — is checked against what
# this machine actually has, and the file's size is printed beside the
# verdicts. A law that names a path nobody can open is not a law: exit 1 names
# every broken citation. The pure half — reading citations, resolving their
# families, the size — lives in lib/agents-check.nu and is proven in
# tests/lib/agents-check.nu; tests/scripts/agents-check.nu runs this edge.
#
#   fleet agents-check                      the owner's AGENTS.md
#   fleet agents-check <file> [--json]      any instruction file
#
# --hooks, --projects and --hub re-root the lookups; the script test builds
# its fixtures that way and touches nothing real.
use ../lib/agents-check.nu *

const DEFAULT_FILE: path = '/Users/lattenero/.zcode/AGENTS.md'
const DEFAULT_PROJECTS: path = '/Users/lattenero/Projects'
const DEFAULT_HUB: path = '/Users/lattenero/Scripts/scripts'

# Where a hook or hub script name is looked up, in order: the registered hook
# (a symlink), the hub's canon of hooks, the hub's scripts.
const DEFAULT_LOOKUPS: list<string> = [
    /Users/lattenero/.zcode/hooks
    /Users/lattenero/Scripts/scripts/hooks
    /Users/lattenero/Scripts/scripts
]

# The report as one value: what was checked, what broke, and the size.
type Report = record<file: string, checked: int, broken: list<Verdict>, stats: Stats>

def main [
    file: path = $DEFAULT_FILE   # the instruction file to prove
    --hooks: path                # the ONE dir hook and script names are looked up in (default: three)
    --projects: path = $DEFAULT_PROJECTS   # where a repo-relative path is rooted
    --hub: path = $DEFAULT_HUB   # where the `fleet` verbs are scripts
    --json                       # the report as one JSON value
]: nothing -> nothing {
    let text: string = (open --raw $file)
    let lookups: list<string> = (if $hooks == null { $DEFAULT_LOOKUPS } else { [$hooks] })
    let roots: Roots = {lookups: $lookups, projects: $projects, hub: $hub}
    let onDisk: closure = {|p: string| $p | path exists }
    let isServed: closure = {|tool: string| $tool in $MCP_TOOLS }
    let all: list<Verdict> = (verdicts $text $roots $onDisk $isServed)
    let report: Report = {file: $file, checked: ($all | length), broken: (broken $all), stats: (stats $text)}
    if $json {
        $report | to json -r | print
    } else {
        print $"citations checked: ($report.checked) · broken: ($report.broken | length)"
        if not ($report.broken | is-empty) { $report.broken | table | print }
        let size: Stats = $report.stats
        print $"lines: ($size.lines) · words: ($size.words) · bytes: ($size.bytes)"
        print $"bullets: ($size.bullets) · sections: ($size.sections) · duplicate bullets: ($size.duplicates)"
    }
    if ($report.broken | is-empty) { exit 0 } else { exit 1 }
}
