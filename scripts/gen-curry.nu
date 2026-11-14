#!/usr/bin/env nu
# gen-curry.nu — emits the curryN ladder for mods/currying.nu.
# kap generates its per-class builders with KSP; this is the same move in
# nushell: one rung per arity, mechanical, identical shape. Kotlin's function
# types cap at 23 parameters, so the ladder does too.
# Run: nu scripts/gen-curry.nu   (paste the output under the GENERATED LADDER
# mark in mods/currying.nu)

const LETTERS: list<string> = [a b c d e f g h i j k l m n o p q r s t u v w x y z]

def gen-def [n: int]: nothing -> string {
    let ls: list<string> = ($LETTERS | first $n)
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

def main []: nothing -> nothing {
    let rungs: list<string> = (6..23 | each {|n| gen-def $n})
    print "# ── GENERATED LADDER arity 6..23 by scripts/gen-curry.nu — do not hand-edit"
    print "#    Kotlin function types cap at 23 parameters; the ladder does too."
    print ($rungs | str join "\n")
}
