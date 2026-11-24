#!/usr/bin/env nu
# examples/agents-dashboard.nu — the daily cross-session agent check, as a
# live demo of nushell-fp composition:
#
#   1. CONCURRENT JSON reads — one job per agent metadata.json (traverse-jobs)
#   2. CONCURRENT git calls — agent/* branch count per repo (second job wave)
#   3. JOIN — builtin `join` welds agents x repos
#   4. NESTED JSON access — get-in pulls usage fields off runtime paths
#   5. PRETTY PARSED RENDER — dates humanized, tokens on the K/M ladder
#
# This is the parallel-session duplicate-work check, automated.

use ../mods/async.nu *
use ../mods/json.nu *
use ../mods/fmt.nu *

const HOME_DIR: string = "/Users/lattenero"
const PROJECTS: string = "/Users/lattenero/Projects"
const META_GLOB: string = "/Users/lattenero/.zcode/cli/agents/*/*/metadata.json"

# One agent metadata.json -> one dashboard row. Every field defensive:
# running agents carry no createdAt/completedAt, some rows lack cwd — the
# hardened traverse-jobs turns any leftover crash into an indexed error.
def read-agent [file: string]: nothing -> record {
    let m: record = (open $file)
    let tsRaw: any = ($m | get-in [createdAt] ($m | get-in [updatedAt] null))
    let started: datetime = (if ($tsRaw | describe) == "nothing" { date now } else { $tsRaw | into datetime })
    let cwd: string = ($m | get-in [cwd] ($m | get-in [workspaceRoot] "unknown"))
    {
        session: ($m | get-in [parentSessionId] "?session" | str substring 5..16),
        profile: ($m | get-in [profileId] "?"),
        status: ($m | get-in [status] "?"),
        repo: ($cwd | path basename),
        description: ($m | get-in [description] "" | str substring 0..38),
        started: $started,
        age: ($started | date humanize),
        tokens: (human-num ($m | get-in [totalTokens] 0)),
        tools: ($m | get-in [totalToolUseCount] 0),
        output: (human-num ($m | get-in [usage outputTokens] 0)),
    }
}

# One repo -> its agent/* branch count (the worktree leftovers check).
def read-repo-branches [repo: string]: nothing -> record {
    let dir: string = ($PROJECTS | path join $repo)
    let run: record<exit_code: int, stdout: string, stderr: string> = (do {|| git -C $dir branch --list "agent/*" } | complete)
    let branches: int = ($run.stdout | lines | where {|l| ($l | str trim) != ""} | length)
    {repo: $repo, agent_branches: $branches}
}

def main []: nothing -> nothing {
    # wave 1: every metadata.json read concurrently, structure order kept
    let files: list<string> = (glob $META_GLOB)
    let agents: list<record> = ($files | each {|f| {|| read-agent $f }} | traverse-jobs)

    # wave 2: branch state for every touched repo, concurrently
    let repos: list<string> = ($agents | get repo | uniq)
    let repoState: list<record> = ($repos | each {|r| {|| read-repo-branches $r }} | traverse-jobs)

    # join + pretty parse: recent first (real datetime, not the age string),
    # the sort key dropped before display
    let joined: table = ($agents
        | join $repoState repo repo --left
        | update agent_branches {|r| $r.agent_branches? | default "-" }
        | sort-by started --reverse
        | first 12
        | reject started)

    print $"agent check — ($files | length) metadata files read in parallel, ($repos | length) repos probed"
    print ($joined | table --index false)
}
