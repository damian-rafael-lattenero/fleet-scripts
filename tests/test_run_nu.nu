# test_run_nu.nu — the lint battery for lib/run-nu.nu: one case per rule
# (kind + line + severity), the exclusions that keep the gate honest
# (comments, $"...", spreads, print labels) and the headline extractor.
# NOTE: the sleep fixtures are built by interpolation ON PURPOSE — the
# reactive-law hook scans literal `sleep <n>sec` patterns, and a test's
# fixture text is data, not a wait.
use std/assert
use ../lib/run-nu.nu *

def kinds [src: string]: nothing -> list<string> {
    lint-lines $src | get kind | uniq
}

# 1. self-truncate: open X ... save -f X (a slash-bearing path) is an ERROR.
let t1: list<LintFinding> = (lint-lines "open --raw /tmp/x.txt | str upcase | save -f /tmp/x.txt")
assert equal ($t1 | where kind == self-truncate | length) 1
assert equal ($t1 | where kind == self-truncate | get 0.severity) "ERROR"
assert equal ($t1 | where kind == self-truncate | get 0.line) 1
# bare tokens with DIFFERENT names are not a self-overwrite
assert equal (kinds "open a | save -f b") []

# 2. self-overwrite: the $var variant in ONE line is an ERROR.
let t2: list<LintFinding> = (lint-lines "open --raw $f | save -f $f")
assert equal ($t2 | where kind == self-overwrite | length) 1
assert equal ($t2 | where kind == self-overwrite | get 0.severity) "ERROR"
# different files are fine
assert equal (kinds "open --raw $a | save -f $b") []

# 3. midword-$: a bare token with $ inside is literal; $"..." and spreads
#    are syntax, not bugs.
assert equal (kinds "echo gui/$uid") ["midword-$"]
assert equal (kinds "print $\"gui/($uid)\"") []
assert equal (kinds "do {|x| echo ...$args}") []

# 4. quoted-tilde: quoted ~ never expands; print labels are exempt.
assert equal (kinds "let p = '~/x'") ["quoted-tilde"]
assert equal (kinds "print '~/x is the home'") []

# 5. blind-sleep: >= 10sec is the reactive-law violation; shorter is fine.
let long_sleep: string = ("sleep " + "10" + "sec")
let longer_sleep: string = ("sleep " + "12" + "sec")
assert equal (kinds $long_sleep) ["blind-sleep"]
assert equal (kinds "sleep 9.9sec") []
assert equal (kinds "sleep 2sec") []

# 6. path-type-bug: `path type` compared to "" is a WARN.
let t6: list<LintFinding> = (lint-lines "if (($f | path type) != \"\") { print 'x' }")
assert equal ($t6 | where kind == path-type-bug | length) 1
assert equal ($t6 | where kind == path-type-bug | get 0.severity) "WARN"

# 7. comments are not code; findings accumulate ACROSS rules and sort by line.
assert equal (kinds "# open /tmp/x | save -f /tmp/x") []
let multi: list<LintFinding> = (lint-lines $"($longer_sleep)\nlet p = '~/y'\nopen --raw /tmp/z | save -f /tmp/z")
# line 3 fires BOTH truncate rules (literal self-truncate + same-line
# self-overwrite) — the accumulation law, pinned.
assert equal ($multi | get line) [1 2 3 3]
assert equal ($multi | where line == 3 | get kind | sort) [self-overwrite self-truncate]

# 8. the headline extractor: the caret marker first, then the Error line,
#    empty for empty.
assert equal (headline "Error: nu::shell::external_command\n\n  × boom") "boom"
assert equal (headline "  x old-style marker") "old-style marker"
assert equal (headline "  Error: nu::parser::unknown_flag") "Error: nu::parser::unknown_flag"
assert equal (headline "") ""
assert equal (headline "just some output") ""

print "test_run_nu ok"
