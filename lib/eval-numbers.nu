# eval-numbers.nu core — the plan's three numbers as eval-ledger rows (U22).
# The edge queries the sources (session store, daemon log, denial ledger),
# computes through lib/brain-baseline.nu's pure cores, and POSTs each row to
# the brain's /eval/record — the ledger keeps ONE writer, the brain. Everything
# here answers from its arguments alone.

# The languages the plan tracks (TypeScript stays out — plan §1).
export const TRACKED: list<string> = [nu kt hs]

# The plan's number: ≤ 5% first-try oracle failure (plan §7).
export const FIRST_PASS_GATE: float = 0.95

# One eval-ledger row: the StoredRun shape /eval/record takes. runId is
# omitted so the brain generates it; the metric has no model — the fields are
# honest placeholders the ledger's NOT NULL columns demand.
export type MetricRun = record<suite: string, kind: string, axis: string, model: string, provider: string, passed: int, total: int, gate: float, ok: bool, detail: record>

# The first-pass rows: one per tracked language whose week had oracle runs.
# passed = clean oracle runs; ok = the share clears the 5% gate. A language
# with no oracle runs is skipped — nothing to measure is not zero. The week's
# language facts ride in detail so the ledger keeps the definitions.
export def first-pass-rows [cells: table, week: string]: nothing -> list<MetricRun> {
    $cells
    | where {|c| ($c.lang in $TRACKED) and ($c.week == $week) and ($c.oracle_runs > 0) }
    | each {|c|
        let total: int = $c.oracle_runs
        let passed: int = ($total - $c.oracle_fails)
        {
            suite: $"first-pass-($c.lang)"
            kind: 'metric'
            axis: 'fleet'
            model: 'n/a'
            provider: 'fleet-scripts'
            passed: $passed
            total: $total
            gate: $FIRST_PASS_GATE
            ok: (($passed / $total) >= $FIRST_PASS_GATE)
            detail: {
                week: $week
                monday: $c.monday
                lang: $c.lang
                writes: $c.writes
                oracle_runs: $total
                oracle_fails: $c.oracle_fails
                law_denials: $c.law_denials
                denials_per_1000_writes: $c.denials_per_1000_writes
                definition: 'first-pass = oracle runs without a failure marker / all oracle runs, one ISO week; the failure markers ride lib/brain-baseline.nu MARKERS'
            }
        }
    }
}

# The rumbo row: the cancel replay's population. passed = the turns that were
# NOT cancelled, total = the turns matched to real steps — so total - passed
# reads as the cancels. gate 0.0: the plan says "a la baja"; the target number
# is the owner's call, until then the row is informational (ok = true).
export def rumbo-row [rows: table]: nothing -> MetricRun {
    let matched: int = ($rows | length)
    let killed: table = ($rows | where reason == cancelled)
    let cancelled: int = ($killed | length)
    let allSteps: int = (if $matched == 0 { 0 } else { $rows | get n | math sum })
    let wasted: int = (if $cancelled == 0 { 0 } else { $killed | get n | math sum })
    let per100: float = (if $matched == 0 {
        0.0
    } else {
        ((($cancelled * 100.0 / $matched) * 10.0 | math round) / 10.0)
    })
    let wastedPct: float = (if $allSteps == 0 {
        0.0
    } else {
        ((($wasted * 100.0 / $allSteps) * 10.0 | math round) / 10.0)
    })
    {
        suite: 'rumbo'
        kind: 'metric'
        axis: 'fleet'
        model: 'n/a'
        provider: 'fleet-scripts'
        passed: ($matched - $cancelled)
        total: $matched
        gate: 0.0
        ok: true
        detail: {
            matched: $matched
            cancelled: $cancelled
            success: ($matched - $cancelled)
            cancels_per_100: $per100
            wasted_steps_pct: $wastedPct
            definition: 'cancels per 100 sealed turns matched to real steps; wasted_steps_pct = the share of all tool steps spent inside cancelled turns; the plan says "a la baja" — the target number is the owner call'
        }
    }
}
