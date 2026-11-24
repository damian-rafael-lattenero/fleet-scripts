# test_zcode_deploy_all.nu — the pure-core proofs for lib/zcode-deploy-all.nu:
# the POSIX quote, the leg body's parts, the wave plan (solo + chained track,
# totality guard) and the status parse.
use std/assert
use ../lib/zcode-deploy-all.nu *

# 1. the quote: single quotes are escaped, everything is wrapped.
assert equal (sh-quote "plain") "'plain'"
assert equal (sh-quote "it's") "'it'\\''s'"
assert equal (sh-quote "$HOME and space") "'$HOME and space'"
assert equal (sh-quote "") "''"

# 2. the leg body: the nu binary, the script, the args, the log tee, the
#    prefixed live stream, the SIGTTIN cure and the status write all appear,
#    quoted for the sh.
let leg: DeployLeg = {name: "bot", label: "bot", script: "/x/deploy-daemon.nu", args: ["--flag" "a b"], kind: "gradle"}
let body: string = (leg-body $leg /tmp/dl "/Users/lattenero/.local/bin/nu-nightly" "/tmp/run.log")
assert str contains $body "'/Users/lattenero/.local/bin/nu-nightly' '/x/deploy-daemon.nu' '--flag' 'a b'"
assert str contains $body "tee -a '/tmp/dl/bot.log'"
assert str contains $body "p=[bot] "
assert str contains $body "< /dev/null"
assert str contains $body "> '/tmp/dl/bot.status'"
assert equal ($body | str starts-with "(") true
assert equal ($body | str ends-with ")") true

# 3. the wave plan: each pnpm leg gets its own `&`; the gradle legs chain
#    inside ONE group that is backgrounded once.
let legs: DeployWave = [
    {name: "fork", label: "f", script: "/x/f.nu", args: [], kind: "pnpm"}
    {name: "brain", label: "b", script: "/x/b.nu", args: [], kind: "gradle"}
    {name: "bot", label: "c", script: "/x/c.nu", args: [], kind: "gradle"}
]
let plan: string = (wave-body $legs /tmp/dl "/nu" "/tmp/run.log")
let lines: list<string> = ($plan | lines)
# the chained track spans lines: solo line, "(", each gradle body, ") &"
assert equal ($lines | length) 5
assert equal ($lines.0 | str ends-with " &") true            # the solo leg, backgrounded
assert equal $lines.1 "("
assert equal $lines.4 ") &"                                   # the chained track, backgrounded once
assert str contains $lines.2 "/tmp/dl/brain.log"
assert str contains $lines.3 "/tmp/dl/bot.log"
# a pnpm-only plan keeps one line per leg, no chain group
let solo_only: string = (wave-body [$legs.0 $legs.0] /tmp/dl "/nu" "/tmp/run.log")
assert equal ($solo_only | lines | length) 2

# 4. the totality guard: an unknown kind never vanishes silently.
let bad: DeployWave = [{name: "x", label: "x", script: "/x", args: [], kind: "typo"}]
assert error { wave-body $bad /tmp/dl "/nu" "/tmp/run.log" }

# 5. the status parse: the file's own format, the sentinel otherwise.
assert equal (status-parse "0 123") {code: 0, secs: 123}
assert equal (status-parse "  12 34  ") {code: 12, secs: 34}
assert equal (status-parse "-1 0") {code: -1, secs: 0}
assert equal (status-parse "garbage") {code: -1, secs: 0}
assert equal (status-parse "") {code: -1, secs: 0}

# 6. the plumbing end to end: a fake leg (a script that exits 3) leaves its
#    log with the live-prefixed lines and its status file with the real code.
let dir: path = ($"($env.TMPDIR? | default /tmp)/dl-(random uuid)")
mkdir $dir
let fake_nu: string = ($dir | path join "fake-nu")
$"#!/bin/sh\necho fake running\nexit 3\n" | save --raw $fake_nu
^chmod +x $fake_nu
let fake: DeployLeg = {name: "drill", label: "d", script: "/x/never.nu", args: [], kind: "pnpm"}
let body: string = (wave-body [$fake] $dir $fake_nu ($dir | path join "run.log"))
^/bin/bash -c ($body + (char nl) + 'wait' + (char nl) + 'exit 0')
let status: record<code: int, secs: int> = (status-parse (open --raw ($dir | path join "drill.status")))
assert equal $status.code 3
let log: string = (open --raw ($dir | path join "drill.log"))
assert str contains $log "fake running"
let runlog: string = (open --raw ($dir | path join "run.log"))
assert str contains $runlog "[drill] fake running"
^rm -rf $dir

print "test_zcode_deploy_all ok"
