# json.nu — lenses over structured records (the JSON-shaped day-to-day).
#
# Gaps ONLY. Nushell 0.117 already ships the heavy machinery, so this module
# builds on it instead of wrapping it:
#   - `merge deep` IS deep-merge (recursive, right-wins leaves, adds keys)
#   - `get -o` / `upsert` cover LITERAL cell paths
#
# What builtins cannot do: paths that only exist at RUNTIME (a list of keys
# built by the script), n-fold config layering, and the dotted-key
# flattening round-trip. That is exactly this module.
#
# Verified live on 0.117.0: merge deep semantics, get -o with dynamic int
# keys on lists, def self-recursion, and `describe` returning parameterized
# shapes (dispatch with `starts-with "record"`, never `== "record"`).

# get-in: follow a runtime path (strings, or ints to index lists) and fall
# back to `default` when any step is missing. Empty path returns the record
# itself (a zero-step fold is the identity).
export def get-in [path: list<any>, default: any]: record -> any {
    let rec: record = $in
    let found: any = ($path | reduce --fold $rec {|k, acc|
        if ($acc | describe) == "nothing" { null } else { $acc | get -o $k }
    })
    if ($found | describe) == "nothing" { $default } else { $found }
}

# set-in: write `value` at a runtime path, creating every missing level.
# A non-record value sitting mid-path is replaced by a fresh record (the
# path wins). Siblings are preserved.
def set-in-rec [rec: record, path: list<string>, value: any]: nothing -> record {
    let k: string = ($path | first)
    let rest: list<string> = ($path | skip 1)
    if ($rest | is-empty) {
        $rec | upsert $k $value
    } else {
        let child: any = ($rec | get -o $k)
        let childRec: record = (if (($child | describe) starts-with "record") { $child } else { {} })
        $rec | upsert $k (set-in-rec $childRec $rest $value)
    }
}

export def set-in [path: list<string>, value: any]: record -> record {
    let rec: record = $in
    set-in-rec $rec $path $value
}

# update-in: apply `f` to the value at a runtime path; a missing path is a
# no-op (the record comes back untouched).
export def update-in [path: list<string>, f: closure]: record -> record {
    let rec: record = $in
    let current: any = ($rec | get-in $path null)
    if ($current | describe) == "nothing" { $rec } else { $rec | set-in $path (do $f $current) }
}

# deep-merge-all: the mconcat of merge-deep — fold a list of record layers,
# left to right, later layers winning. The classic config stack:
# defaults | user | env.
export def deep-merge-all []: list<record> -> record {
    let layers: list<record> = $in
    $layers | reduce --fold {} {|layer, acc| $acc | merge deep $layer}
}

# flatten-keys: nest to dotted strings — {a: {b: 1}, c: 2} -> {"a.b": 1, c: 2}.
# Records are descended; every other value (lists included) is a leaf.
# Empty nested records hold no leaves and vanish (same ruling as record walk).
def flatten-rec [rec: record, prefix: string]: nothing -> list<record<key: string, value: any>> {
    # NOTE: batches are concatenated with append, NOT flatten — `flatten`
    # expands list-valued CELLS into rows too, which would shred list leaves.
    $rec | items {|k, v|
        let dotted: string = (if $prefix == "" { $k } else { $prefix + "." + $k })
        if (($v | describe) starts-with "record") { flatten-rec $v $dotted } else { [{key: $dotted, value: $v}] }
    } | reduce --fold [] {|batch, acc| $acc | append $batch}
}

export def flatten-keys []: record -> record {
    let rec: record = $in
    let leaves: list<record<key: string, value: any>> = (flatten-rec $rec "")
    if ($leaves | is-empty) { {} } else { $leaves | transpose -r -d }
}

# unflatten-keys: the inverse — dotted keys back into nesting. String keys
# only (list indices do not round-trip; they flatten fine but unflatten as
# record keys).
export def unflatten-keys []: record -> record {
    let rec: record = $in
    $rec | items {|k, v|
        $k | split row "." | reverse | reduce --fold $v {|part, acc| {($part): $acc}}
    } | deep-merge-all
}
