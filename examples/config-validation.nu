# config-validation.nu — a REAL pipeline case: layered config + field
# validation, railway style (Wlaschin's ROP translated to nushell-fp).
#
# The track: parse ONCE into tagged records (parse-don't-validate) →
# validate every field with ACCUMULATION (traverse-validated: all errors,
# input order — one bad field never hides another) → layer defaults under
# the config (deep-merge-all) → read with runtime paths (get-in).
# Run it: nu examples/config-validation.nu  → three PASS lines.
use std/assert
use ../mods/types.nu *
use ../mods/json.nu *

# ── the validators: one field, one rule, Result-valued (pure) ────────────
def validate-host [h: string]: nothing -> record<tag: string, value: any, error: any> {
    if ($h | str length) > 0 { ok $h } else { err "db.host: empty" }
}

def validate-port [p: int]: nothing -> record<tag: string, value: any, error: any> {
    if $p >= 1 and $p <= 65535 { ok $p } else { err $"db.port: out of range ($p)" }
}

def validate-user [u: string]: nothing -> record<tag: string, value: any, error: any> {
    if ($u | str length) >= 3 { ok $u } else { err $"db.user: too short '($u)'" }
}

# ── case 1: TWO broken fields — the accumulator names BOTH, in order ────
let rawBad: record = {db: {host: "", port: 99999, user: "damian"}}
let badVerdict: record<tag: string, value: any, error: any> = ([
    (validate-host $rawBad.db.host)
    (validate-port $rawBad.db.port)
] | traverse-validated {|r| $r})
assert equal $badVerdict (err ["db.host: empty" "db.port: out of range 99999"])
print "PASS accumulate: two broken fields, two errors, input order"

# ── case 2: the full happy track — validate, layer, read, and the lens
#    laws as the runtime sanity gate (GetSet on the merged config) ────────
let raw: record = {db: {host: "prod.db", port: 5432, user: "damian"}}
let verdict: record<tag: string, value: any, error: any> = ([
    (validate-host $raw.db.host)
    (validate-port $raw.db.port)
    (validate-user $raw.db.user)
] | traverse-validated {|r| $r})

assert equal $verdict.tag "ok"
let final: record = ([{db: {host: "localhost", port: 5432, user: "bot", ttl: 30}} $raw] | deep-merge-all)
# user values win over defaults, defaults fill the gaps
assert equal ($final | get-in [db host] "?") "prod.db"
assert equal ($final | get-in [db ttl] 0) 30
# GetSet lens law as the runtime gate: what you write is what you read
assert equal ($final | set-in [db port] 9999 | get-in [db port] 0) 9999
print "PASS railway: validate → layer defaults → get-in reads → lens law holds"

# ── case 3: the railway never throws — the eliminator speaks both ends ──
let spoken: string = ($verdict | result-match {|fields| $"ok with ($fields | length) fields"} {|e| $"failed: ($e)"})
assert equal $spoken "ok with 3 fields"
print "PASS eliminator: success channel renders, no exceptions anywhere"
