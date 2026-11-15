# fibonacci-unfold.nu — the Haskell unfoldr classic (HaskellWiki exercises,
# Data.List docs): fibonacci as an ANAMORPHISM. The seed is a {a, b} pair;
# each step emits a and moves to {b, a+b}; the stop condition lives IN the
# step (null), so the same shape serves "first 10" and "all below 100".
use std/assert
use ../mods/list.nu unfold

# the anamorphism: emit the pair head, slide the window
let fibs: list<int> = (unfold {a: 0, b: 1} {|s|
    if $s.a > 100 { null } else { {emit: $s.a, next: {a: $s.b, b: ($s.a + $s.b)} } }
})
assert equal $fibs [0 1 1 2 3 5 8 13 21 34 55 89]
print $"PASS anamorphism: fib below 100 = ($fibs | str join ' ')"

# same shape, different stop: exactly 10 fibs (counter rides the seed)
let fibs10: list<int> = (unfold {a: 0, b: 1, n: 0} {|s|
    if $s.n >= 10 { null } else { {emit: $s.a, next: {a: $s.b, b: ($s.a + $s.b), n: ($s.n + 1)} } }
})
assert equal ($fibs10 | last) 34
print $"PASS bounded: 10th fib row ends ($fibs10 | last), row = ($fibs10 | str join ' ')"

# the recurrence law: every triple (a, b, a+b) holds along the row
let lawHolds: bool = ($fibs | window 3 | all {|w| ($w.0 + $w.1) == $w.2})
assert equal $lawHolds true
print 'PASS recurrence: a + b == next along the whole row'
