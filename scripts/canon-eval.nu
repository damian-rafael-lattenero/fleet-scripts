#!/opt/homebrew/bin/nu
# canon-eval.nu — the eval SUITES as one word (the gap brain-eval.nu does not
# fill: that script is the 21/11 question battery; this one runs the agent-brain
# eval suites, canon-recall by default, and leaves one verdict line in
# ~/Library/Logs/canon-eval.log. Exit 1 when the suite misses its gate.
#
# The suite argument is a PATH: the loader reads a real file FIRST and only
# falls back to the copy bundled inside the installed binary — a path means
# the repo's live suite file, no rebuild needed (measured 27/11, Suite.kt).

const BIN: string = "/Users/lattenero/Projects/agent-brain/core/build/install/agent-brain/bin/agent-brain"
const SUITE: string = "/Users/lattenero/Projects/agent-brain/evals/suites/canon-recall.json"
const OUT: string = "/Users/lattenero/Projects/agent-brain/evals/artifacts"
const LOG_FILE: string = "/Users/lattenero/Library/Logs/canon-eval.log"

# The run's headline: numbers plus the ids that missed.
export type Verdict = record<passed: int, total: int, ok: bool, missed: list<string>>

# One completed external run.
type RunResult = record<stdout: string, stderr: string, exit_code: int>

# The run's verdict as one record: the headline numbers plus the case ids
# that missed. Pure — the test pins it.
export def verdict-of [report: record]: nothing -> Verdict {
    let cases: list = ($report | get -o cases | default [])
    let missed: list<string> = ($cases
        | where {|c| ($c | get -o ok | default true) == false}
        | each {|c| ($c | get -o id | default '?')})
    {
        passed: ($report | get -o passed | default 0),
        total: ($report | get -o total | default 0),
        ok: ($report | get -o ok | default false),
        missed: $missed,
    }
}

# One voice for stdout AND the run log.
def emit [line: string]: nothing -> nothing {
    print $line
    try {
        $"($line)\n" | save --append $LOG_FILE
    } catch { }
}

# main — --suite takes the suite file's absolute path (or a bundled name);
# a path reads the repo's live file, no rebuild needed.
def main [
    --suite: string = $SUITE,
]: nothing -> nothing {
    let res: RunResult = (do { run-external $BIN eval "--suite" $suite "--out" $OUT } | complete)
    if ($res.stdout | is-empty) {
        emit $"❌ canon-eval: no report on stdout, exit ($res.exit_code) — ($res.stderr | str substring 0..160)"
        exit 1
    }
    let report: record = ($res.stdout | from json)
    let v: Verdict = (verdict-of $report)
    if ($v.missed | is-empty) {
        emit $"✅ canon-eval ($suite | path basename): ($v.passed)/($v.total) green in ($report | get -o durationMs | default 0) ms"
    } else {
        emit $"⚠️ canon-eval ($suite | path basename): ($v.passed)/($v.total), missed: ($v.missed | str join ', ')"
    }
    if not $v.ok { exit 1 }
}
