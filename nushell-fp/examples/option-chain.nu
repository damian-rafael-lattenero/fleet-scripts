# option-chain.nu — the Scala for-comprehension over Options, desugared
# the way Scala itself does it: flatMap chains + guards. Here the chain is
# option-bind, the filter is option-guard, and the boundary parses ONCE
# (get -o -> some/none) instead of null-checking mid-pipeline.
use std/assert
use ../mods/types.nu *

# parse-don't-validate at the boundary: a raw record becomes Options ONCE
const RAW: record = {bot: {token: "tt", chat: 42}, fork: {model: null}}

def lookup [path: list<string>]: record -> record<tag: string, value: any> {
    let rec: record = $in
    $path
    | reduce --fold (some $rec) {|k, acc| $acc | option-bind {|r| some ($r | get -o $k)}}
    | option-bind {|v| if $v == null { none } else { some $v } }
}

# the for-comprehension, Scala desugar order:
#   for { t <- bot.token; c <- bot.chat; m <- fork.model if m != "" } yield ...
let found: record<tag: string, value: any> = ($RAW
    | lookup [bot token]
    | option-bind {|t| ($RAW | lookup [bot chat]) | option-map {|c| {token: $t, chat: $c}}}
    | option-bind {|tc| ($RAW | lookup [fork model]) | option-map {|m| $tc | merge {model: $m}}}
    | option-bind {|cfg| option-guard (($cfg.model | str length) > 0) | option-map {|_| $cfg} })
assert equal $found.tag "none"    # fork.model is null -> the comprehension dies exactly there
print 'PASS short-circuit: null model kills the chain with none — no error thrown'

# the same chain over a complete config: the some carries the whole record
const GOOD: record = {bot: {token: "tt", chat: 42}, fork: {model: "glm"}}
let complete: record<tag: string, value: any> = ($GOOD
    | lookup [bot token]
    | option-bind {|t| ($GOOD | lookup [bot chat]) | option-map {|c| {token: $t, chat: $c}}}
    | option-bind {|tc| ($GOOD | lookup [fork model]) | option-map {|m| $tc | merge {model: $m}}}
    | option-bind {|cfg| option-guard (($cfg.model | str length) > 0) | option-map {|_| $cfg} })
assert equal ($complete | option-unwrap-or null) {token: tt, chat: 42, model: glm}
print 'PASS full chain: some carries the assembled record'

# kleisli form (option-compose): the second link consumes the FIRST's
# output — lookup yields the token, the validator consumes the token
let tokenOf: closure = {|rec| $rec | lookup [bot token]}
let tokenLongEnough: closure = {|tok: string| option-guard (($tok | str length) >= 2) | option-map {|_| $tok}}
assert equal (do (option-compose $tokenOf $tokenLongEnough) $GOOD) (some "tt")
# and a short token would carry the none through the composition
const SHORT: record = {bot: {token: "t", chat: 1}, fork: {model: "m"}}
assert equal (do (option-compose {|rec| $rec | lookup [bot token]} $tokenLongEnough) $SHORT) (none)
print 'PASS kleisli: option-compose chains parser -> validator, none flows through'
