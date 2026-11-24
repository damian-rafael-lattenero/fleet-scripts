# combinators.nu — classic higher-order functions over first-class closures.
# Nushell closures ARE values: stored in variables, passed as args, returned
# from other closures (verified live on nushell 0.117.0). Currying is manual
# (closure-returning closures); there is no auto-currying.

# The identity function.
export def identity []: any -> any { $in }

# Constant function factory: returns a closure that always yields `x`.
export def konst [x: any]: nothing -> closure { {|_ignored| $x} }

# Right-to-left composition: (compose f g) x = g (f x).
export def compose [f: closure, g: closure]: nothing -> closure { {|x| do $g (do $f $x)} }

# Flip the first two arguments of `f`.
export def flip [f: closure]: nothing -> closure { {|a, b| do $f $b $a} }
