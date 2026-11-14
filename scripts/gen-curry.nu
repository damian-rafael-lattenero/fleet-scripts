#!/usr/bin/env nu
# gen-curry.nu — emits the curryN and uncurryN ladders for mods/currying.nu.
# kap generates its per-class builders with KSP; this is the same move in
# nushell: one rung per arity, mechanical, identical shape. Kotlin's function
# types cap at 23 parameters, so both ladders do too.
# Run: nu scripts/gen-curry.nu   (paste the output under the GENERATED LADDER
# mark in mods/currying.nu, or splice: the marker-to-EOF block is replaced)

const LETTERS: list<string> = [a b c d e f g h i j k l m n o p q r s t u v w x y z]

def letters [n: int]: nothing -> list<string> {
    $LETTERS | first $n
}

def gen-def [n: int]: nothing -> string {
    let ls: list<string> = (letters $n)
    let opens: string = ($ls | each {|l| "{|" + $l + "| "} | str join)
    let args: string = ($ls | each {|l| "$" + $l} | str join " ")
    let call: string = ("do $fn " + $args)
    let closes: string = ($ls | each {|_| "}"} | str join " ")
    let parts: list<string> = [
        ("export def curry" + ($n | into string) + " [fn: closure]: nothing -> closure { "),
        $opens,
        $call,
        $closes,
        "}",
    ]
    $parts | str join " "
}

# uncurryN fn = {|a, b, ...| apply the curried chain rung by rung}
# do (do (do $fn $a) $b) $c ... — one do per rung, mirroring apply-args.
# The target is `fn` (never a..w): a letter name would shadow-capture at the
# matching arity (the curry6/f lesson, hit AGAIN here as uncurry7/g).
def gen-uncurry-def [n: int]: nothing -> string {
    let ls: list<string> = (letters $n)
    let params: string = ($ls | str join ", ")
    let expr: string = ($ls
        | skip 1
        | reduce --fold ("do $fn $" + ($ls | first)) {|l, acc| "do (" + $acc + ") $" + $l})
    "export def uncurry" + ($n | into string) + " [fn: closure]: nothing -> closure { {|" + $params + "| " + $expr + "} }"
}

def main []: nothing -> nothing {
    let curried: list<string> = (2..23 | each {|n| gen-def $n})
    let uncurried: list<string> = (2..23 | each {|n| gen-uncurry-def $n})
    print "# ── GENERATED LADDER arity 2..23 by scripts/gen-curry.nu — do not hand-edit"
    print "#    Kotlin function types cap at 23 parameters; both ladders do too."
    print ($curried | str join "\n")
    print "# ── uncurry ladder: invert a curried chain back to a flat closure ──"
    print ($uncurried | str join "\n")
}
