# currying.nu — kap-style currying and step-by-step structure filling.
#
# Nushell has NO native currying. kap (Kotlin) doesn't either, so it builds it:
# `kap(f)` wraps a constructor, each `.with(fa)` applies ONE argument (a
# deferred Kap computation), and the type narrows until the structure is
# complete. The same design translated here with first-class closures:
#
#   curry2/curry3  — manual currying (closure returning closure), one step
#                    per argument, exactly like the per-arity code kap's KSP
#                    generates per class.
#   papply         — fix the leading arguments (kap's `.with` by value).
#   build-record   — the applicative essence: a record whose fields are
#                    0-arg closures is filled field by field until the whole
#                    structure exists (sequential).
#   build-record-par — same graph, evaluated in parallel via par-each
#                    (par-each preserves input order — verified 0.117.0).
#
# Mechanics verified live on nushell 0.117.0: closures accept rest params,
# `do $f ...$args` spreads a stored list into the call, closures nest at
# least 3 deep, closures ride record fields untouched until `do`.

# Curry a 2-argument closure: (a, b) -> r becomes a -> b -> r.
export def curry2 [fn: closure]: nothing -> closure { {|a| {|b| do $fn $a $b} } }

# Curry a 3-argument closure: a -> b -> c -> r.
export def curry3 [fn: closure]: nothing -> closure { {|a| {|b| {|c| do $fn $a $b $c} } } }

# Curry a 4-argument closure: a -> b -> c -> d -> r.
export def curry4 [fn: closure]: nothing -> closure { {|a| {|b| {|c| {|d| do $fn $a $b $c $d} } } } }

# Curry a 5-argument closure: a -> b -> c -> d -> e -> r.
export def curry5 [fn: closure]: nothing -> closure { {|a| {|b| {|c| {|d| {|e| do $fn $a $b $c $d $e} } } } } }

# Inverse of curry2: a -> b -> r becomes (a, b) -> r.
export def uncurry2 [g: closure]: nothing -> closure { {|a, b| do (do $g $a) $b} }

# Partial application: fix the leading arguments of `f`, keep a closure
# waiting for the rest (kap's `.with` with a raw value).
export def papply [f: closure, ...fixed: any]: nothing -> closure { {|...rest| do $f ...$fixed ...$rest} }

# Apply a curried chain from a LIST of arguments, one `do` per rung
# (foldl ($) in Haskell). Idiomatic shape: the args ride the pipeline, the
# curried closure rides the parameter. Works at any arity; a short list
# leaves a partially-applied closure as the result.
export def apply-args [c: closure]: list<any> -> any {
    $in | reduce --fold $c {|x, acc| do $acc $x}
}

# Applicative record building: every field of `spec` is a 0-arg closure;
# evaluate each and return the filled record. Errors surface from the field
# that fails, first to last.
export def build-record [spec: record]: nothing -> record {
    $spec | items {|k, f| {key: $k, value: (do $f)}} | transpose -r -d
}

# Same applicative building, fields evaluated in parallel. par-each keeps
# input order, so the result record matches build-record exactly.
export def build-record-par [spec: record]: nothing -> record {
    $spec | items {|k, f| {key: $k, f: $f}}
    | par-each {|row| {key: $row.key, value: (do $row.f)}}
    | transpose -r -d
}

# Left-to-right pipeline: thread x through every unary closure in `fs`
# (the >>> combinator). thread x [f, g] == do g (do f x).
export def thread [x: any, fs: list<closure>]: nothing -> any {
    $fs | reduce --fold $x {|f, acc| do $f $acc}
}

# ── GENERATED LADDER arity 6..23 by scripts/gen-curry.nu — do not hand-edit
#    Kotlin function types cap at 23 parameters; the ladder does too.
export def curry6 [fn: closure]: nothing -> closure {  {|a| {|b| {|c| {|d| {|e| {|f|  do $fn $a $b $c $d $e $f } } } } } } }
export def curry7 [fn: closure]: nothing -> closure {  {|a| {|b| {|c| {|d| {|e| {|f| {|g|  do $fn $a $b $c $d $e $f $g } } } } } } } }
export def curry8 [fn: closure]: nothing -> closure {  {|a| {|b| {|c| {|d| {|e| {|f| {|g| {|h|  do $fn $a $b $c $d $e $f $g $h } } } } } } } } }
export def curry9 [fn: closure]: nothing -> closure {  {|a| {|b| {|c| {|d| {|e| {|f| {|g| {|h| {|i|  do $fn $a $b $c $d $e $f $g $h $i } } } } } } } } } }
export def curry10 [fn: closure]: nothing -> closure {  {|a| {|b| {|c| {|d| {|e| {|f| {|g| {|h| {|i| {|j|  do $fn $a $b $c $d $e $f $g $h $i $j } } } } } } } } } } }
export def curry11 [fn: closure]: nothing -> closure {  {|a| {|b| {|c| {|d| {|e| {|f| {|g| {|h| {|i| {|j| {|k|  do $fn $a $b $c $d $e $f $g $h $i $j $k } } } } } } } } } } } }
export def curry12 [fn: closure]: nothing -> closure {  {|a| {|b| {|c| {|d| {|e| {|f| {|g| {|h| {|i| {|j| {|k| {|l|  do $fn $a $b $c $d $e $f $g $h $i $j $k $l } } } } } } } } } } } } }
export def curry13 [fn: closure]: nothing -> closure {  {|a| {|b| {|c| {|d| {|e| {|f| {|g| {|h| {|i| {|j| {|k| {|l| {|m|  do $fn $a $b $c $d $e $f $g $h $i $j $k $l $m } } } } } } } } } } } } } }
export def curry14 [fn: closure]: nothing -> closure {  {|a| {|b| {|c| {|d| {|e| {|f| {|g| {|h| {|i| {|j| {|k| {|l| {|m| {|n|  do $fn $a $b $c $d $e $f $g $h $i $j $k $l $m $n } } } } } } } } } } } } } } }
export def curry15 [fn: closure]: nothing -> closure {  {|a| {|b| {|c| {|d| {|e| {|f| {|g| {|h| {|i| {|j| {|k| {|l| {|m| {|n| {|o|  do $fn $a $b $c $d $e $f $g $h $i $j $k $l $m $n $o } } } } } } } } } } } } } } } }
export def curry16 [fn: closure]: nothing -> closure {  {|a| {|b| {|c| {|d| {|e| {|f| {|g| {|h| {|i| {|j| {|k| {|l| {|m| {|n| {|o| {|p|  do $fn $a $b $c $d $e $f $g $h $i $j $k $l $m $n $o $p } } } } } } } } } } } } } } } } }
export def curry17 [fn: closure]: nothing -> closure {  {|a| {|b| {|c| {|d| {|e| {|f| {|g| {|h| {|i| {|j| {|k| {|l| {|m| {|n| {|o| {|p| {|q|  do $fn $a $b $c $d $e $f $g $h $i $j $k $l $m $n $o $p $q } } } } } } } } } } } } } } } } } }
export def curry18 [fn: closure]: nothing -> closure {  {|a| {|b| {|c| {|d| {|e| {|f| {|g| {|h| {|i| {|j| {|k| {|l| {|m| {|n| {|o| {|p| {|q| {|r|  do $fn $a $b $c $d $e $f $g $h $i $j $k $l $m $n $o $p $q $r } } } } } } } } } } } } } } } } } } }
export def curry19 [fn: closure]: nothing -> closure {  {|a| {|b| {|c| {|d| {|e| {|f| {|g| {|h| {|i| {|j| {|k| {|l| {|m| {|n| {|o| {|p| {|q| {|r| {|s|  do $fn $a $b $c $d $e $f $g $h $i $j $k $l $m $n $o $p $q $r $s } } } } } } } } } } } } } } } } } } } }
export def curry20 [fn: closure]: nothing -> closure {  {|a| {|b| {|c| {|d| {|e| {|f| {|g| {|h| {|i| {|j| {|k| {|l| {|m| {|n| {|o| {|p| {|q| {|r| {|s| {|t|  do $fn $a $b $c $d $e $f $g $h $i $j $k $l $m $n $o $p $q $r $s $t } } } } } } } } } } } } } } } } } } } } }
export def curry21 [fn: closure]: nothing -> closure {  {|a| {|b| {|c| {|d| {|e| {|f| {|g| {|h| {|i| {|j| {|k| {|l| {|m| {|n| {|o| {|p| {|q| {|r| {|s| {|t| {|u|  do $fn $a $b $c $d $e $f $g $h $i $j $k $l $m $n $o $p $q $r $s $t $u } } } } } } } } } } } } } } } } } } } } } }
export def curry22 [fn: closure]: nothing -> closure {  {|a| {|b| {|c| {|d| {|e| {|f| {|g| {|h| {|i| {|j| {|k| {|l| {|m| {|n| {|o| {|p| {|q| {|r| {|s| {|t| {|u| {|v|  do $fn $a $b $c $d $e $f $g $h $i $j $k $l $m $n $o $p $q $r $s $t $u $v } } } } } } } } } } } } } } } } } } } } } } }
export def curry23 [fn: closure]: nothing -> closure {  {|a| {|b| {|c| {|d| {|e| {|f| {|g| {|h| {|i| {|j| {|k| {|l| {|m| {|n| {|o| {|p| {|q| {|r| {|s| {|t| {|u| {|v| {|w|  do $fn $a $b $c $d $e $f $g $h $i $j $k $l $m $n $o $p $q $r $s $t $u $v $w } } } } } } } } } } } } } } } } } } } } } } } }