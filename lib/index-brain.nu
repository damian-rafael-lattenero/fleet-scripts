# lib/index-brain.nu — the pure core of index-brain.nu: the first-match
# classifier, the launchctl/psql parses, the four layer verdicts (containers,
# pgvector, ollama, serve) and the docs delta. The script keeps every probe's
# external call, the ladder data and the repairs.
use /Users/lattenero/Scripts/nushell-fp/mods/types.nu *

export type LayerProbe = record<ok: bool, detail: string>
export type Prior = record<tag: string, value: any>
# A classifier row: the predicate picks the branch, only the winner renders
# (the anti-patterns law — chains die, precedence lives in row order).
export type RenderRule = record<when: closure, render: closure>

# The first matching row renders; the catch-all row is last (row order = precedence).
export def classify [rules: list<RenderRule>]: nothing -> string {
    let hit: RenderRule = ($rules | where {|r| do $r.when } | first)
    (do $hit.render)
}

# The boot chain's missing labels from a `launchctl list` capture: a label
# absent from the table is missing (unparseable rows count as absent).
export def missing-from [text: string, agents: list<string>]: nothing -> list<string> {
    let rows: table = ($text | lines | where {|r| $r =~ 'com\.zcode' } | parse "{pid}\t{exit}\t{label}")
    $agents | where {|n| ($rows | where label == $n | length) == 0 }
}

# The containers layer: pg must run and every agent-brain container must be
# healthy; non-agent containers are ignored. The health marker is matched as
# "(healthy)" EXACTLY: the plain word also matches inside "(unhealthy)" —
# the substring made a sick container pass as healthy until the test pinned
# it (2026-11-24).
export def containers-verdict [rows: list<any>, pg_container: string]: nothing -> LayerProbe {
    let running: list<any> = ($rows | where name =~ '^agent-brain')
    let has_pg: bool = (($running | where name == $pg_container | length) > 0)
    let unhealthy: list<any> = ($running | where {|r| $r.status !~ '\(healthy\)' })
    let rules: list<RenderRule> = [
        {when: {|| not $has_pg}, render: {|| $"($pg_container) not running"}}
        {when: {|| not ($unhealthy | is-empty)}, render: {|| $"unhealthy: ($unhealthy | get name | str join ', ')"}}
        {when: {|| true}, render: {|| $"($running | length) running, all healthy"}}
    ]
    {ok: ($has_pg and ($unhealthy | is-empty)), detail: (classify $rules)}
}

# The pgvector layer: the extension's version (empty = missing).
export def pgvector-verdict [version: string]: nothing -> LayerProbe {
    let v: string = ($version | str trim)
    # the literal parens need the escape: inside $"..." a bare (...) is a
    # COMMAND CALL and the parens vanish from the output (measured here).
    {ok: ($v | is-not-empty), detail: (if ($v | is-empty) { "vector extension MISSING" } else { $"vector \(($v))" })}
}

# The ollama layer: the embedder model must appear in the tag list.
export def ollama-verdict [models: list<string>, model: string]: nothing -> LayerProbe {
    let hit: list<string> = ($models | where {|m| $m =~ $model })
    {ok: (not ($hit | is-empty)), detail: (if ($hit | is-empty) { $"($model) NOT loaded" } else { $hit | first })}
}

# The serve layer: /ready's own JSON — status, pending migrations, embed probe.
export def serve-verdict [j: record]: nothing -> LayerProbe {
    let pending: list<string> = ($j.checks?.db?.pending? | default [])
    let embed_ok: bool = ($j.checks?.embed?.ok? | default false)
    let rules: list<RenderRule> = [
        {when: {|| $j.status != "ok"}, render: {|| $"status ($j.status)"}}
        {when: {|| not ($pending | is-empty)}, render: {|| $"pending migrations: ($pending | str join ', ')"}}
        {when: {|| not $embed_ok}, render: {|| "embed probe failed"}}
        {when: {|| true}, render: {|| $"ok — db + embed ($j.checks?.embed?.model? | default '?')"}}
    ]
    {ok: ($j.status == "ok" and ($pending | is-empty) and $embed_ok), detail: (classify $rules)}
}

# The documents receipt from psql's `count|freshest` line; none when the
# query answered nothing usable. The constructor needs the PARENS: bare
# `return none` answers the STRING "none" (measured while testing).
export def doc-stats-parse [text: string]: nothing -> Prior {
    let line: string = ($text | lines | where {|l| ($l | str trim) != "" } | first | default "" | str trim)
    let parts: list<string> = ($line | split row '|')
    if ($parts | length) < 2 { return (none) }
    some {docs: ($parts.0 | into int), freshest: $parts.1}
}

# The before→after receipt: the delta when both sides answered, "?" otherwise.
export def delta-line [before: Prior, after: Prior]: nothing -> string {
    $before | option-match {|b|
        $after | option-match {|a| $"+($a.docs - $b.docs) docs · freshest ($a.freshest)" } {|| "?" }
    } {|| "?" }
}

# What one repair answered, shaped for the ladder: exit_code 0 and an empty
# stderr when the repair ran clean, exit_code 1 and the message when it
# raised. `complete` cannot shape a closure (it is external-only, measured
# 27/11: the ladder died AFTER kickstarting the brain); try/catch is the one
# shape that covers a repair ending in anything.
export type RepairOutcome = record<exit_code: int, stderr: string>

export def repair-outcome [repair: closure]: nothing -> RepairOutcome {
    try {
        do { do $repair }
        {exit_code: 0, stderr: ''}
    } catch {|e|
        {exit_code: 1, stderr: ($e.msg | into string)}
    }
}
