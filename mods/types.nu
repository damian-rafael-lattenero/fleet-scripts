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
#
# The type aliases (the owner's 22/11 law): the shapes read once —
# `Opt` and `Res` spell the ADT in every signature (45 inline repetitions
# retired in the 22/11 self-audit). Composable like any type alias:
# `list<Opt>` is `sequence-option`'s input.

# The Option ADT: {tag: "some"|"none", value: a|null}.
type Opt = record<tag: string, value: any>
# The Result ADT: {tag: "ok"|"err", value: a|null, error: null|e}.
type Res = record<tag: string, value: any, error: any>

# ── Option (Haskell Maybe) ───────────────────────────────────────────────

# Wrap a present value.
export def some [x: any]: nothing -> Opt {
    {tag: "some", value: $x}
}

# The absent value.
export def none []: nothing -> Opt {
    {tag: "none", value: null}
}

# fmap for Option: apply `f` to a present value, pass none through.
export def option-map [f: closure]: Opt -> Opt {
    let o: Opt = $in
    if $o.tag == "some" { some (do $f $o.value) } else { $o }
}

# (>>=) for Option: flat-apply a closure that itself returns an Option.
export def option-bind [f: closure]: Opt -> Opt {
    let o: Opt = $in
    if $o.tag == "some" { do $f $o.value } else { $o }
}

# (<*>) for Option (pure = some): apply an Option-wrapped closure to an
# Option-wrapped value; none in EITHER position collapses to none. With it,
# the four applicative laws (identity, composition, homomorphism,
# interchange) are test-pinned the way the functor/monad laws are.
export def option-ap [x: Opt]: Opt -> Opt {
    let f: Opt = $in
    if $f.tag == "some" and $x.tag == "some" { some (do $f.value $x.value) } else { none }
}

# The eliminator (cata): run on-some on the value, on-none otherwise.
export def option-match [onSome: closure, onNone: closure]: Opt -> any {
    let o: Opt = $in
    if $o.tag == "some" { do $onSome $o.value } else { do $onNone }
}

# Extract the value or fall back to `default`.
export def option-unwrap-or [default: any]: Opt -> any {
    let o: Opt = $in
    if $o.tag == "some" { $o.value } else { $default }
}

# (<|>) for Option (Alternative): the first some wins, none falls through.
export def option-or [other: Opt]: Opt -> Opt {
    let o: Opt = $in
    if $o.tag == "some" { $o } else { $other }
}

# guard: some null when the condition holds, none when it does not — the
# list-comprehension filter, as a branch cutter.
export def option-guard [cond: bool]: nothing -> Opt {
    if $cond { some null } else { none }
}

# join: collapse Option<Option> one level.
export def option-join []: Opt -> Opt {
    let o: Opt = $in
    if $o.tag == "some" and $o.value.tag == "some" { $o.value } else { none }
}

# (<=<) for Option: compose two closure-returning-Option into one.
export def option-compose [f: closure, g: closure]: nothing -> closure {
    {|x| (do $f $x) | option-bind $g}
}

# traverse with Maybe semantics: apply f to every element; the FIRST none
# collapses everything (later elements are never touched).
export def traverse-option [f: closure]: list<any> -> Opt {
    let xs: list<any> = $in
    $xs | reduce --fold (some []) {|x, acc|
        if $acc.tag == "none" {
            none
        } else {
            let fx: Opt = do $f $x
            if $fx.tag == "none" { none } else { some ($acc.value | append [$fx.value]) }
        }
    }
}

# sequence: flip list-of-Options into Option-of-list (traverse identity).
export def sequence-option []: list<Opt> -> Opt {
    let xs: list<Opt> = $in
    $xs | traverse-option {|o| $o}
}

# ── Result (Haskell Either, error on the right tag) ──────────────────────

# A successful value.
export def ok [x: any]: nothing -> Res {
    {tag: "ok", value: $x, error: null}
}

# A failure carrying `e`.
export def err [e: any]: nothing -> Res {
    {tag: "err", value: null, error: $e}
}

# The bridge from the impure world: run an UNSAFE closure and catch ANY error
# into the Result ADT. This is the one place try/catch is allowed — after it,
# the value is a plain Result and every step composes with result-map/bind/
# match (no more `if (path exists)` guards or inline try/catch around effects).
#
#   attempt {|| rm -r $target }   # => ok(null) | err("External command had a
#                                 #    non-zero exit code")
export def attempt [body: closure]: nothing -> Res {
    try { ok (do $body) } catch {|e| err $e.msg }
}

# fmap for Result on the success channel.
export def result-map [f: closure]: Res -> Res {
    let r: Res = $in
    if $r.tag == "ok" { ok (do $f $r.value) } else { $r }
}

# fmap on the failure channel (mapErr).
export def result-map-err [f: closure]: Res -> Res {
    let r: Res = $in
    if $r.tag == "err" { err (do $f $r.error) } else { $r }
}

# bimap: map both channels at once (ok side first arg, err side second).
export def result-bimap [onOk: closure, onErr: closure]: Res -> Res {
    let r: Res = $in
    if $r.tag == "ok" { ok (do $onOk $r.value) } else { err (do $onErr $r.error) }
}

# (>>=) for Result: chain a closure returning Result; err short-circuits.
export def result-bind [f: closure]: Res -> Res {
    let r: Res = $in
    if $r.tag == "ok" { do $f $r.value } else { $r }
}

# (<*>) for Result (pure = ok): apply a Result-wrapped closure to a
# Result-wrapped value. The FUNCTION position's error wins first — the
# applicative evaluation order the laws assume. The precedence table: the
# function's err row first, then the value's, then the catch-all apply.
# THE DEFER LAW LIVE (measured by the gate 22/11): a row's `keep` payload
# is a THUNK — an eager `ok (do $f.value $x.value)` in the catch-all row
# would apply null as a closure whenever $f is err. Rows pick the branch,
# only the winner is forced.
export def result-ap [x: Res]: Res -> Res {
    let f: Res = $in
    let rows: list<record<when: closure, keep: closure>> = [
        {when: {|_ff: Res| $f.tag == "err"}, keep: {|| $f}}
        {when: {|_ff: Res| $x.tag == "err"}, keep: {|| $x}}
        {when: {|_ff: Res| true}, keep: {|| ok (do $f.value $x.value)}}
    ]
    ($rows | where {|row| do $row.when $f } | first | get keep | do $in)
}

# The eliminator: on-ok on the value, on-err on the error.
export def result-match [onOk: closure, onErr: closure]: Res -> any {
    let r: Res = $in
    if $r.tag == "ok" { do $onOk $r.value } else { do $onErr $r.error }
}

# Extract the value or fall back to `default` (the error is discarded).
export def result-unwrap-or [default: any]: Res -> any {
    let r: Res = $in
    if $r.tag == "ok" { $r.value } else { $default }
}

# (<|>) for Result: the first ok wins, err falls through to `other`.
export def result-or [other: Res]: Res -> Res {
    let r: Res = $in
    if $r.tag == "ok" { $r } else { $other }
}

# join: collapse Result<Result> one level (inner failure wins on err.err).
# The precedence table: fully-ok collapses, ok-with-err-inner collapses to
# the inner, catch-all returns the outer (the mode-table law).
export def result-join []: Res -> Res {
    let r: Res = $in
    # the checker infers the rows' table type (keep is a nullable Res union
    # across rows) — an explicit list<record<keep: Res, ...>> annotation
    # rejects that union, so this binding stays inference-typed
    let rows = [
        {keep: $r.value, when: {|rr: Res| ($rr.tag == "ok") and ($rr.value.tag == "ok")}}
        {keep: $r.value, when: {|rr: Res| $rr.tag == "ok"}}
        {keep: $r, when: {|rr: Res| true}}
    ]
    ($rows | where {|row| do $row.when $r } | first | get keep)
}

# (<=<) for Result: compose two closure-returning-Result into one.
export def result-compose [f: closure, g: closure]: nothing -> closure {
    {|x| (do $f $x) | result-bind $g}
}

# foldM: a left fold whose step returns Result; the first err stops the fold
# (later steps never run).
export def fold-result [f: closure, init: any]: list<any> -> Res {
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
export def traverse-validated [f: closure]: list<any> -> Res {
    let xs: list<any> = $in
    let results: list<Res> = ($xs | each {|x| do $f $x})
    let errs: list<any> = ($results | where {|r| $r.tag == "err"} | get error)
    if ($errs | is-empty) { ok ($results | get value) } else { err $errs }
}
