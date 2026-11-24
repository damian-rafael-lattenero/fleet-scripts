# lib/worktree-sweep.nu — the pure core of worktree-sweep.nu: the two sweep
# verdict tables (worktree rows, orphan clones), the age gate and the
# "branch at path" item parse. The script keeps the git/rm effects.
export type SweepRow = record<repo: string, item: string, action: string, why: string>

# A linked worktree's verdict: dirty convicts first, then not-merged, then
# the catch-all. Order is the law; the caller only feeds the booleans.
export def wt-verdict [dirty: bool, merged: bool, mb: string]: nothing -> record<action: string, why: string> {
    let rows: list<record<when: bool, action: string, why: string>> = [
        {when: $dirty, action: "KEEP", why: "dirty working tree"}
        {when: (not $merged), action: "KEEP", why: $"not merged into ($mb)"}
        {when: true, action: "CLEAN-able", why: "merged + clean"}
    ]
    $rows | where when | first | select action why
}

# An orphan clone's verdict: a real worktree belongs to the repo audit, an
# origin-owned clone is someone's checkout, then the age gate (a fresh
# fixture may belong to a live test run).
export def orphan-verdict [is_clone: bool, origin_live: bool, age_h: int, min_age_h: int]: nothing -> record<action: string, why: string> {
    let rows: list<record<when: bool, action: string, why: string>> = [
        {when: (not $is_clone), action: "KEEP", why: "real worktree — the repo audit owns it"}
        {when: $origin_live, action: "KEEP", why: "clone with origin — someone's real checkout"}
        {when: ($age_h >= $min_age_h), action: "ORPHAN-able", why: "clone fixture, no origin — past the age gate"}
        {when: true, action: "KEEP", why: "clone fixture fresh — below the age gate, a live test may own it"}
    ]
    $rows | where when | first | select action why
}

# Whole hours between a mtime and now (floor, never negative-rounded).
export def age-h [modified: datetime, now: datetime]: nothing -> int {
    (($now - $modified) / 1hr | math floor)
}

# The sweep row's "branch at path" item split (branch names carry no spaces,
# so the LAST ` at ` is never inside a branch).
export def item-parts [item: string]: nothing -> record<branch: string, path: string> {
    let parts: list<string> = ($item | split row " at ")
    {branch: ($parts | get -o 0 | default ""), path: ($parts | get -o 1 | default "")}
}
