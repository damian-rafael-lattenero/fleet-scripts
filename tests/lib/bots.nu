# bots.nu — the census and the two decisions, proven as laws: every bot row is
# well-formed, a mute daemon is DOWN with a pid alive, the aux loops degrade to
# a warn instead of a restart, and the repair never invents work (missing plist
# = hands; deploy in flight = hands-off).
use std/assert
use ../../lib/bots.nu *

# ---- the census -------------------------------------------------------------

assert equal ($CENSUS | length) 6 "the family: two bots, a sidecar, three helpers"
assert equal ($CENSUS | get name | uniq | length) 6 "the leg names are unique"
assert equal ($CENSUS | get label | uniq | length) 6 "one label per row, never a double kick"
assert equal ($CENSUS | get name | where {|n| not ($n | str starts-with 'bot-')}) [] "leg names carry the family word"

let daemons: list<BotRow> = ($CENSUS | where kind == "daemon")
let periodic: list<BotRow> = ($CENSUS | where kind == "periodic")
assert equal (($daemons | length) + ($periodic | length)) 6 "every row is a daemon or a periodic job"
# a daemon proves itself with its own beat; a threshold without a beat is a rule
# that can never fire, and a beat without a threshold can never fail.
assert equal ($daemons | where {|r| ($r.beat | is-empty) or $r.beat_max_s <= 0}) [] "every daemon has a beat + window"
assert equal ($periodic | where {|r| not ($r.beat | is-empty)}) [] "a periodic job has no beat of its own"

# ---- the verdict ------------------------------------------------------------

let telegram: BotRow = ($CENSUS | where name == "bot-telegram" | get 0)
let healer: BotRow = ($CENSUS | where name == "bot-healer" | get 0)
let dead: BotProbe = {loaded: false, running: false, beat_age_s: 999999999, last_exit: -1, plist: true, stale_loops: []}
let healthy: BotProbe = {loaded: true, running: true, beat_age_s: 4, last_exit: -1, plist: true, stale_loops: []}

# not loaded = the whole job is gone: fail, whatever the beat says.
assert equal (verdict $telegram $dead).state "fail"
assert equal (verdict $telegram $dead).detail "not loaded — launchd has no job"
assert equal (verdict $telegram $dead).leg "bot-telegram"

# loaded but silent: the process is a zombie, the phone gets nothing.
let mute: BotProbe = {loaded: true, running: false, beat_age_s: 999999999, last_exit: -1, plist: true, stale_loops: []}
assert equal (verdict $telegram $mute).state "fail"
assert str contains (verdict $telegram $mute).detail "no process"

# a pid alive and a mute beat is still DOWN — launchd's opinion is not liveness.
let wedged: BotProbe = {loaded: true, running: true, beat_age_s: 421, last_exit: -1, plist: true, stale_loops: []}
assert equal (verdict $telegram $wedged).state "fail"
assert str contains (verdict $telegram $wedged).detail "mute 7 min"
assert str contains (verdict $telegram $wedged).detail "process alive"

# the happy path, and the aux loops: stale ones warn, they never restart a bot
# that is serving the phone.
assert equal (verdict $telegram $healthy).state "ok"
assert str contains (verdict $telegram $healthy).detail "running"
let degraded: BotProbe = ($healthy | update stale_loops ["hb-palette" "hb-spectator"])
assert equal (verdict $telegram $degraded).state "warn"
assert str contains (verdict $telegram $degraded).detail "hb-palette, hb-spectator"
assert equal (verdict $telegram ($healthy | update beat_age_s 20_000)).state "fail" "the hit of the first battery run"

# periodic helpers: launchd's own last exit code is the honest signal.
let ran: BotProbe = {loaded: true, running: false, beat_age_s: 0, last_exit: 0, plist: true, stale_loops: []}
assert equal (verdict $healer $ran).state "ok"
assert equal (verdict $healer ($ran | update last_exit 75)).state "fail"
assert str contains (verdict $healer ($ran | update last_exit 75)).detail "75"
# a not-loaded periodic job is as dead as a not-loaded daemon.
assert equal (verdict $healer $dead).state "fail"

# ---- the repair -------------------------------------------------------------

# loaded = kickstart (re-run it now); a forgotten job = bootstrap the plist.
assert equal (repair $telegram $healthy false) {action: "kickstart", why: "kickstart -k com.zcode.bot-daemon"}
let forgotten: BotProbe = ($healthy | update loaded false)
assert equal (repair $telegram $forgotten false).action "bootstrap"
# no plist: nothing launchd could ever load — hands, never an invented file.
assert equal ((repair $telegram ($forgotten | update plist false) false).action) "missing-plist"
# the deploy is restarting the bot ON PURPOSE: repair would fight it.
assert equal (repair $telegram $wedged true).action "hands-off"
assert str contains (repair $telegram $wedged true).why "com.zcode.bot-deploy"
# the deploy guard outranks every action, even a kickstart that would work.
assert equal (repair $telegram $healthy true).action "hands-off"

# ---- the words --------------------------------------------------------------

assert equal (age-words 42) "42s"
assert equal (age-words 119) "119s"
assert equal (age-words 120) "2 min"
assert equal (age-words 421) "7 min"
assert equal (age-words 7199) "119 min"
assert equal (age-words 7200) "2 h"

print "bots core ok — 6 bots census, verdict + repair laws held"
