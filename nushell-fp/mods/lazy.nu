# lazy.nu — deference in a strict shell (the defer law's mechanisms).
#
# Nushell is EAGER: `let x = expensive` evaluates NOW, there are no thunks
# by default, and no lazy lists. What the shell DOES have, measured live
# (0.117, 21/11 — the defer law, fp-kb notes/defer-law-nu.md):
#
# 1. CLOSURES ARE THUNKS: `{|| expensive }` is a VALUE — nothing runs until
#    `do` forces it. This module formalizes that as the lazy record
#    (the healthcheck's `{f: closure}` leg pattern, promoted to the stdlib).
# 2. SHORT-CIRCUIT and/or: the right side SKIPS when the left decides —
#    measured: `false and (boom)` never ran the side effect.
# 3. STREAMING PIPELINES: `seq 1 5000000 | first 3` took 789µs — the
#    million never materialized. Order pipelines cheap-first: filter/take
#    early, transform late.
# 4. GUARDS BEFORE BUILDS: `if` before the `let` — never precompute what a
#    guard might discard.
#
# THE LAW (fp-kb notes/defer-law-nu.md): defer expensive or conditional work
# in closures; force only at the point of use. ANTI-LAW: premature laziness
# — a value that is ALWAYS used builds eagerly and correctly; wrapping it
# in a closure is ceremony without payoff.

# Wrap a closure into the lazy record: building is free, the body runs only
# when `force` (or a plain `do`) reaches it.
#
# Example — the expensive transform defers past a guard:
#   let report = thunk {|| open data.csv | group-by region | each {|g| ... }}
#   if $needs_report { force $report }   # built only when actually asked
export def thunk [body: closure]: nothing -> record {
    {f: $body}
}

# Force a lazy record: run its closure NOW and return the result.
#
# Example — the deferred build pays at the point of use:
#   let t = thunk {|| 1..1000000 | each {|x| $x * $x} }
#   let n = (force $t | length)   # the million squares build HERE, not at
#                                 # the thunk line
export def force [t: record]: nothing -> any {
    do $t.f
}

# Force with an argument: the thunk's closure receives it (a deferred
# function call, not just a deferred value).
#
# Example — defer the expensive lookup until the key is known:
#   let lookup = {key: $key}
#   ... later: force-with $lookup {|key| open $"cache/($key).json" }
export def force-with [t: record, arg: any]: nothing -> any {
    do $t.f $arg
}
