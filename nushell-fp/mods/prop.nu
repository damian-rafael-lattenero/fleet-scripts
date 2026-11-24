# prop.nu — a tiny property-based testing harness.
#
# The PBT recipe (fp-kb/notes/pbt-metamorphic-recipe.md) made mechanical:
#   1. state the INVARIANT (a closure over a generated sample),
#   2. generators define the input space (biased to edges: empty and
#      singleton lists occur by construction),
#   3. DETERMINISM BY SEED — nushell's `random` is NOT seedable (verified
#      0.117.0: no `random seed` subcommand), so generators are PURE
#      functions of an explicit int seed (splitmix-flavored mixing). Every
#      run derives its seed from the root; a failure replays exactly,
#   4. SHRINK-LITE — on failure, try smaller candidates (empty, halves,
#      tail) and keep the first one that still fails: a counterexample
#      reported as [] is a diagnosis, one reported as 12 noisy ints is not.
#
# Results ride the types.nu tagged shape (ok/err) so they compose with
# result-bind / result-match like everything else.
#
# Verified on 0.117.0: `for` + plain `mut` in a def body is legal (the
# anti-capture law forbids mut in CLOSURES, not in defs); int division
# needs `//` (`/` always floats).

use types.nu ok
use types.nu err

# A deterministic int from a seed (classic LCG mixing; int64-safe: the
# product stays well under 2^63 for any sane seed).
export def gen-int [seed: int, --min: int = -100, --max: int = 100]: nothing -> int {
    let span: int = ($max - $min + 1)
    let mixed: int = (($seed * 1103515245 + 12345) mod 2147483648)
    $min + ($mixed mod (if $span <= 0 { 1 } else { $span }))
}

# A deterministic random-length int list from one seed (length 0..max-len,
# so empty and singleton lists occur — the edge cases ARE in the space).
export def gen-list-int [seed: int, --max-len: int = 12]: nothing -> list<int> {
    let len: int = (gen-int ($seed + 1) --min 0 --max $max_len)
    if $len == 0 { [] } else {
        1..$len | each {|i| gen-int ($seed + 31 * $i) }
    }
}

# Shrink candidates for a failing list, smallest-first.
export def shrink-list [xs: list<int>]: nothing -> list<list<int>> {
    let n: int = ($xs | length)
    if $n <= 1 { return [[]] }
    let half: int = ($n // 2)
    [ [] ($xs | first $half) ($xs | skip $half) ($xs | skip 1) ]
}

# for-all: run the property over `runs` seeded samples. The gen closure
# RECEIVES the run seed and returns a sample deterministically. ok {runs}
# on success; err {seed, sample, shrunk} on the first failure — the
# reported sample is shrunk to the first smaller candidate that still fails.
export def for-all [
    gen: closure
    prop: closure
    --runs: int = 100
    --seed: int = 20261114
]: nothing -> record<tag: string, value: any, error: any> {
    mut failure: any = null
    for ix in 1..$runs {
        let runSeed: int = ($seed + ($ix * 7919))
        let sample: any = (do $gen $runSeed)
        if not (do $prop $sample) {
            $failure = {i: $ix, seed: $runSeed, sample: $sample}
            break
        }
    }
    if $failure == null {
        ok {runs: $runs, seed: $seed}
    } else {
        # shrink-lite: one pass over the candidates, keep the first failing
        let shrunken: list<any> = (if (($failure.sample | describe) starts-with "list") {
            shrink-list $failure.sample | each {|cand|
                if (do $prop $cand) { null } else { $cand }
            } | where {|c| $c != null} 
        } else {
            []
        })
        err {seed: $failure.seed, sample: $failure.sample, shrunk: ($shrunken | first)}
    }
}
