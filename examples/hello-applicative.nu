# hello-applicative.nu — the concurrency theorem, live: 5 deferred hellos,
# each sleeping its own duration. Sequential pays the SUM (15s); the
# applicative pays the MAX (5s) and restores structure order.
use ../mods/async.nu *
use ../mods/currying.nu *

# the five deferred computations: values that do not exist YET
let hellos: list<closure> = ([
    {|| sleep 1sec; "hola1" }
    {|| sleep 2sec; "hola2" }
    {|| sleep 3sec; "hola3" }
    {|| sleep 4sec; "hola4" }
    {|| sleep 5sec; "hola5" }
])

print '── control: sequential each — pays the SUM of durations ──'
let t0: datetime = (date now)
let seq: list<string> = ($hellos | each {|f| do $f})
print ($seq | str join ' ')
print $"took ((date now) - $t0)"

print ''
print '── the applicative: traverse-jobs — pays the MAX, order restored ──'
let t1: datetime = (date now)
let conc: list<string> = ($hellos | traverse-jobs)
print ($conc | str join ' ')
print $"took ((date now) - $t1)"

print ''
print '── the kap .with chain: apply-async feeds a curried5 constructor ──'
let t2: datetime = (date now)
let row: string = ($hellos | apply-async (curry5 {|a, b, c, d, e| [$a $b $c $d $e] | str join ' ' }))
print $row
print $"took ((date now) - $t2)"
