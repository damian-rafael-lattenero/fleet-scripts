# types.nu — Option and Result as tagged records (the ADTs nushell lacks).
#
# Nushell has no sum types, so the classic encoding: a record with a `tag`
# discriminator and a uniform shape. Both constructors fill every field
# (null where absent) so signatures stay exact:
#
#   Option a = {tag: "some", value: a} | {tag: "none", value: null}
#   Result  = {tag: "ok", value: a, error: null} | {tag: "err", value: null, error: e}
#
# The laws mirror kap's LAWS.md: functor identity/composition, monad
# left/right identity and associativity — pinned by tests, so refactorings
# are substitutable. And the kap ruling holds here too: the VALIDATED side
# (traverse-validated) is intentionally NOT a monad — error accumulation
# needs applicative semantics; short-circuit lives in traverse-option and
# fold-result.
#
# Verified live on 0.117.0: closure types in record signatures, uniform
# tagged shapes, null keeping the shape, nested tag checks.

# ── Option (Haskell Maybe) ───────────────────────────────────────────────

# Wrap a present value.
export def some [x: any]: nothing -> record<tag: string, value: any> {
    {tag: "some", value: $x}
}

# The absent value.
export def none []: nothing -> record<tag: string, value: any> {
    {tag: "none", value: null}
}

# fmap for Option: apply `f` to a present value, pass none through.
export def option-map [f: closure]: record<tag: string, value: any> -> record<tag: string, value: any> {
    let o: record<tag: string, value: any> = $in
    if $o.tag == "some" { some (do $f $o.value) } else { $o }
}

# (>>=) for Option: flat-apply a closure that itself returns an Option.
export def option-bind [f: closure]: record<tag: string, value: any> -> record<tag: string, value: any> {
    let o: record<tag: string, value: any> = $in
    if $o.tag == "some" { do $f $o.value } else { $o }
}

# (<*>) for Option (pure = some): apply an Option-wrapped closure to an
# Option-wrapped value; none in EITHER position collapses to none. With it,
# the four applicative laws (identity, composition, homomorphism,
# interchange) are test-pinned the way the functor/monad laws are.
export def option-ap [x: record<tag: string, value: any>]: record<tag: string, value: any> -> record<tag: string, value: any> {
    let f: record<tag: string, value: any> = $in
    if $f.tag == "some" and $x.tag == "some" { some (do $f.value $x.value) } else { none }
}

# The eliminator (cata): run on-some on the value, on-none otherwise.
export def option-match [onSome: closure, onNone: closure]: record<tag: string, value: any> -> any {
    let o: record<tag: string, value: any> = $in
    if $o.tag == "some" { do $onSome $o.value } else { do $onNone }
}

# Extract the value or fall back to `default`.
export def option-unwrap-or [default: any]: record<tag: string, value: any> -> any {
    let o: record<tag: string, value: any> = $in
    if $o.tag == "some" { $o.value } else { $default }
}

# (<|>) for Option (Alternative): the first some wins, none falls through.
export def option-or [other: record<tag: string, value: any>]: record<tag: string, value: any> -> record<tag: string, value: any> {
    let o: record<tag: string, value: any> = $in
    if $o.tag == "some" { $o } else { $other }
}

# guard: some null when the condition holds, none when it does not — the
# list-comprehension filter, as a branch cutter.
export def option-guard [cond: bool]: nothing -> record<tag: string, value: any> {
    if $cond { some null } else { none }
}

# join: collapse Option<Option> one level.
export def option-join []: record<tag: string, value: any> -> record<tag: string, value: any> {
    let o: record<tag: string, value: any> = $in
    if $o.tag == "some" and $o.value.tag == "some" { $o.value } else { none }
}

# (<=<) for Option: compose two closure-returning-Option into one.
export def option-compose [f: closure, g: closure]: nothing -> closure {
    {|x| (do $f $x) | option-bind $g}
}

# traverse with Maybe semantics: apply f to every element; the FIRST none
# collapses everything (later elements are never touched).
export def traverse-option [f: closure]: list<any> -> record<tag: string, value: any> {
    let xs: list<any> = $in
    $xs | reduce --fold (some []) {|x, acc|
        if $acc.tag == "none" {
            none
        } else {
            let fx: record<tag: string, value: any> = do $f $x
            if $fx.tag == "none" { none } else { some ($acc.value | append [$fx.value]) }
        }
    }
}

# sequence: flip list-of-Options into Option-of-list (traverse identity).
export def sequence-option []: list<record<tag: string, value: any>> -> record<tag: string, value: any> {
    let xs: list<record<tag: string, value: any>> = $in
    $xs | traverse-option {|o| $o}
}

# ── Result (Haskell Either, error on the right tag) ──────────────────────

# A successful value.
export def ok [x: any]: nothing -> record<tag: string, value: any, error: any> {
    {tag: "ok", value: $x, error: null}
}

# A failure carrying `e`.
export def err [e: any]: nothing -> record<tag: string, value: any, error: any> {
    {tag: "err", value: null, error: $e}
}

# fmap for Result on the success channel.
export def result-map [f: closure]: record<tag: string, value: any, error: any> -> record<tag: string, value: any, error: any> {
    let r: record<tag: string, value: any, error: any> = $in
    if $r.tag == "ok" { ok (do $f $r.value) } else { $r }
}

# fmap on the failure channel (mapErr).
export def result-map-err [f: closure]: record<tag: string, value: any, error: any> -> record<tag: string, value: any, error: any> {
    let r: record<tag: string, value: any, error: any> = $in
    if $r.tag == "err" { err (do $f $r.error) } else { $r }
}

# bimap: map both channels at once (ok side first arg, err side second).
export def result-bimap [onOk: closure, onErr: closure]: record<tag: string, value: any, error: any> -> record<tag: string, value: any, error: any> {
    let r: record<tag: string, value: any, error: any> = $in
    if $r.tag == "ok" { ok (do $onOk $r.value) } else { err (do $onErr $r.error) }
}

# (>>=) for Result: chain a closure returning Result; err short-circuits.
export def result-bind [f: closure]: record<tag: string, value: any, error: any> -> record<tag: string, value: any, error: any> {
    let r: record<tag: string, value: any, error: any> = $in
    if $r.tag == "ok" { do $f $r.value } else { $r }
}

# (<*>) for Result (pure = ok): apply a Result-wrapped closure to a
# Result-wrapped value. The FUNCTION position's error wins first — the
# applicative evaluation order the laws assume.
export def result-ap [x: record<tag: string, value: any, error: any>]: record<tag: string, value: any, error: any> -> record<tag: string, value: any, error: any> {
    let f: record<tag: string, value: any, error: any> = $in
    if $f.tag == "err" { $f } else if $x.tag == "err" { $x } else { ok (do $f.value $x.value) }
}

# The eliminator: on-ok on the value, on-err on the error.
export def result-match [onOk: closure, onErr: closure]: record<tag: string, value: any, error: any> -> any {
    let r: record<tag: string, value: any, error: any> = $in
    if $r.tag == "ok" { do $onOk $r.value } else { do $onErr $r.error }
}

# Extract the value or fall back to `default` (the error is discarded).
export def result-unwrap-or [default: any]: record<tag: string, value: any, error: any> -> any {
    let r: record<tag: string, value: any, error: any> = $in
    if $r.tag == "ok" { $r.value } else { $default }
}

# (<|>) for Result: the first ok wins, err falls through to `other`.
export def result-or [other: record<tag: string, value: any, error: any>]: record<tag: string, value: any, error: any> -> record<tag: string, value: any, error: any> {
    let r: record<tag: string, value: any, error: any> = $in
    if $r.tag == "ok" { $r } else { $other }
}

# join: collapse Result<Result> one level (inner failure wins on err.err).
export def result-join []: record<tag: string, value: any, error: any> -> record<tag: string, value: any, error: any> {
    let r: record<tag: string, value: any, error: any> = $in
    if $r.tag == "ok" and $r.value.tag == "ok" { $r.value } else if $r.tag == "ok" { $r.value } else { $r }
}

# (<=<) for Result: compose two closure-returning-Result into one.
export def result-compose [f: closure, g: closure]: nothing -> closure {
    {|x| (do $f $x) | result-bind $g}
}

# foldM: a left fold whose step returns Result; the first err stops the fold
# (later steps never run).
export def fold-result [f: closure, init: any]: list<any> -> record<tag: string, value: any, error: any> {
    let xs: list<any> = $in
    $xs | reduce --fold (ok $init) {|x, acc|
        if $acc.tag == "err" { $acc } else { do $f $acc.value $x }
    }
}

# ── Validated (kap's error ACCUMULATION applicative) ─────────────────────
# traverse-validated runs f on EVERY element, collects ALL errors in input
# order, and only fails after the whole list has been inspected. Intentional
# non-monad, per the kap ruling: accumulation vs short-circuit is the choice
# of traverse, not of the type.

# Applicative traverse that accumulates every error (as a list).
export def traverse-validated [f: closure]: list<any> -> record<tag: string, value: any, error: any> {
    let xs: list<any> = $in
    let results: list<record<tag: string, value: any, error: any>> = ($xs | each {|x| do $f $x})
    let errs: list<any> = ($results | where {|r| $r.tag == "err"} | get error)
    if ($errs | is-empty) { ok ($results | get value) } else { err $errs }
}
