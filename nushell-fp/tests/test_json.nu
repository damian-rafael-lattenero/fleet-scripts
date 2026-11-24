# test_json.nu — assertions for mods/json.nu (runtime paths, layering, round-trip).
use std/assert
use ../mods/json.nu *

let cfg: record = {db: {host: "localhost", port: 5432}, name: "app"}

# ── get-in: runtime paths with a fallback ────────────────────────────────
assert equal ($cfg | get-in [db host] "?") "localhost"
assert equal ($cfg | get-in [db port] 0) 5432
assert equal ($cfg | get-in [db missing deep] "dflt") "dflt"
assert equal ($cfg | get-in [nope] 42) 42
# ints index lists along the way
assert equal ({items: [10 20 30]} | get-in [items 1] (-1)) 20
assert equal ({items: [10 20 30]} | get-in [items 9] "oob") "oob"
# empty path is the identity (a zero-step fold)
assert equal ($cfg | get-in [] null) $cfg

# ── set-in: dynamic nested write ─────────────────────────────────────────
# creates every missing level from scratch
assert equal ({} | set-in [a b c] 1) {a: {b: {c: 1}}}
# overwrites a leaf, siblings preserved
assert equal ($cfg | set-in [db port] 999) {db: {host: "localhost", port: 999}, name: "app"}
# a non-record mid-path is replaced by a fresh record (the path wins)
assert equal ({a: 1} | set-in [a b] 2) {a: {b: 2}}
# set-in does not mutate the source (records are immutable values)
assert equal $cfg {db: {host: "localhost", port: 5432}, name: "app"}

# ── update-in: in-place transform at a path ──────────────────────────────
assert equal ($cfg | update-in [db port] {|p: int| $p + 1}) {db: {host: "localhost", port: 5433}, name: "app"}
assert equal ($cfg | update-in [db host] {|h: string| $h | str uppercase}) {db: {host: "LOCALHOST", port: 5432}, name: "app"}
# missing path is a no-op
assert equal ({a: 1} | update-in [x y] {|v| $v}) {a: 1}

# ── deep-merge-all: the config stack ─────────────────────────────────────
assert equal ([{db: {host: "local", port: 1}}, {db: {host: "prod"}}, {db: {port: 2}}] | deep-merge-all) {db: {host: "prod", port: 2}}
assert equal ([] | deep-merge-all) {}
assert equal ([{a: 1}] | deep-merge-all) {a: 1}
# layers do not leak into each other
let base: record = {db: {host: "h", port: 1}}
let merged: record = ([$base, {db: {port: 2}}] | deep-merge-all)
assert equal $merged {db: {host: "h", port: 2}}
assert equal $base {db: {host: "h", port: 1}}

# ── flatten-keys ─────────────────────────────────────────────────────────
assert equal ({a: {b: 1}, c: 2} | flatten-keys) {"a.b": 1, c: 2}
assert equal ({a: {b: {c: 1}}} | flatten-keys) {"a.b.c": 1}
# lists are leaves, kept whole
assert equal ({l: [1 2]} | flatten-keys) {l: [1 2]}
assert equal ({} | flatten-keys) {}
# a bare value under a key survives as one dotted row
assert equal ({x: {y: [1 2]}, z: "s"} | flatten-keys) {"x.y": [1 2], z: "s"}

# ── unflatten-keys + the round-trip law ──────────────────────────────────
assert equal ({"a.b": 1, c: 2} | unflatten-keys) {a: {b: 1}, c: 2}
assert equal ({"a.b.c": 1} | unflatten-keys) {a: {b: {c: 1}}}
assert equal ({} | unflatten-keys) {}
# THE law: flatten . unflatten == identity (records-only values)
let deep: record = {a: {b: {c: 1}}, d: 2}
assert equal ($deep | flatten-keys | unflatten-keys) $deep
let wide: record = {bot: {token: "t", chat: 42}, fork: {model: "glm"}}
assert equal ($wide | flatten-keys | unflatten-keys) $wide

# ── lens laws over get-in/set-in (Gibbons naming: well-behaved = GetSet
#    + SetGet; "very well-behaved" adds SetSet) ───────────────────────────
let lensS: record = {db: {host: "h", port: 1}, flag: true}
# GetSet (PutGet): get (set v s) == v — reading back what you wrote
assert equal ($lensS | set-in [db port] 99 | get-in [db port] null) 99
# SetGet (GetPut): set (get s) s == s — writing what you read changes nothing
assert equal ($lensS | set-in [db host] ($lensS | get-in [db host] null)) $lensS
# SetSet (PutPut): set v2 (set v1 s) == set v2 s — the last write wins
assert equal ($lensS | set-in [db port] 1 | set-in [db port] 42) ($lensS | set-in [db port] 42)

# ── deep-merge-all is associative — grouping layers never matters, only
#    the order WITHIN a stack ──────────────────────────────────────────────
let la: record = {db: {host: "a"}}
let lb: record = {db: {host: "b", port: 2}}
let lc: record = {db: {port: 3}, extra: true}
let ab: record = ([$la $lb] | deep-merge-all)
let bc: record = ([$lb $lc] | deep-merge-all)
assert equal ([$ab $lc] | deep-merge-all) ([$la $bc] | deep-merge-all)
assert equal ([$ab $lc] | deep-merge-all) {db: {host: "b", port: 3}, extra: true}

print "test_json ok"
