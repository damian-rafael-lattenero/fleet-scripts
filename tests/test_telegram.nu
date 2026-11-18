# test_telegram.nu — the deploy announce rung: the TYPED signature the three
# deploy scripts call (nothing → text: string, --html: switch → nothing).
# The network path is NOT exercised here on purpose: a test that posted would
# ping the owner's real chat.
use std/assert
use ../mods/telegram.nu send-telegram

let sig: list<any> = (scope commands | where name == "send-telegram")
assert equal ($sig | length) 1

let params: list<any> = ($sig.0.signatures | get "nothing")
assert equal ($params | get parameter_type) ["input" "positional" "switch" "output"]
assert equal ($params | get parameter_name | where {|n| $n != null}) ["text" "html"]
assert equal ($params | get syntax_shape | where {|s| $s != null}) ["nothing" "string" "nothing"]

# the flag is OPTIONAL: the plain announce (no --html) parses and runs
assert equal ($params | get is_optional | first 3) [false false true]

print "test_telegram ok"
