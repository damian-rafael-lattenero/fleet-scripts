# agents-check.nu — the edge end to end on a fixture built for the run: a
# clean instruction file exits 0 and prints its counts; a broken hook, a
# broken verb, a missing path and an unserved tool each show by name with
# exit 1; --json answers one value with the verdicts and the size. Nothing
# touches the real AGENTS.md or the real lookups.
# covers: /Users/lattenero/Scripts/scripts/agents-check.nu
use std/assert

const SELF: path = (path self)
const SCRIPT: path = ($SELF | path expand | path dirname | path dirname | path dirname | path join 'scripts' 'agents-check.nu')

# A clean file: one citation per family, all present in the fixture.
const CLEAN: string = "# Law\n\n- a hook `good.nu`, a path `kb/notes/a.md`, a verb `fleet real`, an explicit verb `fleet list`, a tool `mcp__serper__scrape`\n"

# The same file with every citation broken.
const BROKEN: string = "# Law\n\n- `ghost.nu`, `fleet gone`, `fleet lost`, `mcp__serper__nope`, `kb/notes/missing.md`\n"

# What a run answers.
type Run = record<exit_code: int, stdout: string, stderr: string>

# Fire the script over a file, with or without the JSON switch.
def fire [file: path, hooks: path, projects: path, hub: path, json: bool]: nothing -> Run {
    let args: list<string> = (if $json { [$file --hooks $hooks --projects $projects --hub $hub --json] } else { [$file --hooks $hooks --projects $projects --hub $hub] })
    do { ^$nu.current-exe $SCRIPT ...$args } | complete
}

let root: path = (mktemp -d -t 'agents-check.XXXXXX')
let hooks: path = ($root | path join 'hooks')
let projects: path = ($root | path join 'projects')
let hub: path = ($root | path join 'hub')
mkdir $hooks ($projects | path join 'kb' 'notes') $hub
'' | save --force ($hooks | path join 'good.nu')
'' | save --force ($projects | path join 'kb' 'notes' 'a.md')
'' | save --force ($hub | path join 'real.nu')
$CLEAN | save --force ($root | path join 'clean.md')
$BROKEN | save --force ($root | path join 'broken.md')

let clean: Run = (fire ($root | path join 'clean.md') $hooks $projects $hub false)
assert equal ($clean.stderr | str trim) '' $"the script must answer, never error: ($clean.stderr)"
assert equal $clean.exit_code 0 'exit 0 when every citation holds'
assert str contains ($clean.stdout | str trim) 'citations checked: 5 · broken: 0'

let bad: Run = (fire ($root | path join 'broken.md') $hooks $projects $hub true)
assert equal ($bad.stderr | str trim) '' $"the script must answer, never error: ($bad.stderr)"
assert equal $bad.exit_code 1 'exit 1 on a broken citation'
let report: record = ($bad.stdout | from json)
assert equal ($report.broken | get ref | sort) ['ghost.nu' 'gone' 'kb/notes/missing.md' 'lost' 'mcp__serper__nope']
assert equal $report.checked 5
assert equal ($report.stats | get bullets) 1

rm -r -f $root
print 'scripts/agents-check ok — exit 0 when clean with the counts, four broken families by name with exit 1, one JSON value'
