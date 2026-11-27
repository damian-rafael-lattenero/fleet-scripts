# bots.nu core — the bot family as DATA and the two decisions the battery makes
# about it: the VERDICT (is this bot serving its chat surface? judged by the
# bot's OWN beat, never launchd's opinion of "loaded") and the REPAIR (the least
# action that could bring it back, plus the cases where acting would be wrong).
# No effects here: the caller hands in what it probed, so every case is a
# literal fixture and every rule is proven in tests/lib/bots.nu.
#
# The census is a TABLE, not a chain: a new bot is one row, a retired bot is a
# deleted row, and neither touches the verdict logic (the predicate-table law).

# One bot of the fleet. `beat` is the file the bot writes ITSELF ("" for the
# periodic helpers, which have no loop of their own); `loops` is an aux
# heartbeat glob reported but never acted on; `deploy` is the job label whose
# in-flight run makes a repair wrong (the deploy is restarting it on purpose).
export type BotRow = record<name: string, label: string, kind: string, beat: string, beat_max_s: int, loops: string, deploy: string>

# What the world answered about one bot at one instant — the edge probes, the
# core judges. `beat_age_s` is 999999999 when the beat never existed (a bot that
# never wrote one is exactly the case this battery exists for).
export type BotProbe = record<loaded: bool, running: bool, beat_age_s: int, last_exit: int, plist: bool, stale_loops: list<string>>

# One battery row (the shape the table renders) and one repair decision.
export type Leg = record<leg: string, state: string, detail: string>
export type Repair = record<action: string, why: string>

# THE census: every chat-facing bot daemon and the helpers that keep it honest.
# Thresholds are the bots' own clocks, not invented here:
#   · bot-telegram: the channel loop's beat; the healer acts at 3 min, so 5 min
#     means even the healer failed.
#   · bot-whatsapp: the poller beat; its own watchdog exits for a launchd
#     restart at 3 min stale, so 5 min means the watchdog failed too.
#   · bot-whatsapp-sidecar: no beat file — its maintenance leg logs every
#     30 min, so 60 min of silence = two missed passes.
#   · bot-healer / bot-recorder / bot-comparator: periodic jobs, no beat; the
#     honest signal is the last exit code launchd recorded.
# The retired Python watchers (telegram-cmds/telegram-watch, Disabled=true) are
# NOT bots to check: they are intentionally off.
export const CENSUS: list<BotRow> = [
    {name: "bot-telegram", label: "com.zcode.bot-daemon", kind: "daemon", beat: "/Users/lattenero/.zcode/bot-kotlin/state/hb-channel", beat_max_s: 300, loops: "/Users/lattenero/.zcode/bot-kotlin/state/hb-*", deploy: "com.zcode.bot-deploy"}
    {name: "bot-whatsapp", label: "com.lattenero.whatsdigestkt.daemon", kind: "daemon", beat: "/Users/lattenero/.zcode/whatsdigest-kt/state/poller-beat", beat_max_s: 300, loops: "", deploy: "com.zcode.wd-deploy"}
    {name: "bot-whatsapp-sidecar", label: "com.zcode.whatsdigest-sidecar", kind: "daemon", beat: "/Users/lattenero/Library/Logs/whatsdigest-sidecar.log", beat_max_s: 3600, loops: "", deploy: ""}
    {name: "bot-healer", label: "com.zcode.bot-healer", kind: "periodic", beat: "", beat_max_s: 0, loops: "", deploy: ""}
    {name: "bot-recorder", label: "com.zcode.bot-recorder", kind: "periodic", beat: "", beat_max_s: 0, loops: "", deploy: ""}
    {name: "bot-comparator", label: "com.zcode.bot-comparator", kind: "periodic", beat: "", beat_max_s: 0, loops: "", deploy: ""}
]

# Seconds in the owner's reading units: the table column is narrow and "7 min"
# says more than "421".
export def age-words [seconds: int]: nothing -> string {
    if $seconds < 120 { return $"($seconds)s" }
    if $seconds < 7200 { return $"($seconds / 60 | math floor) min" }
    $"($seconds / 3600 | math floor) h"
}

def leg-row [row: BotRow, state: string, detail: string]: nothing -> Leg {
    {leg: $row.name, state: $state, detail: $detail}
}

# THE verdict — ordered preconditions (the bot-healer law): the happy path stays
# flat at the end, every guard speaks the world it saw, and a daemon whose beat
# is mute is DOWN even though launchd still shows a pid.
export def verdict [row: BotRow, probe: BotProbe]: nothing -> Leg {
    if not $probe.loaded {
        return (leg-row $row "fail" "not loaded — launchd has no job")
    }
    if $row.kind == "daemon" and not $probe.running {
        return (leg-row $row "fail" $"no process — beat (age-words $probe.beat_age_s)")
    }
    if $row.kind == "daemon" and $probe.beat_age_s > $row.beat_max_s {
        return (leg-row $row "fail" $"mute (age-words $probe.beat_age_s) — process alive, threshold (age-words $row.beat_max_s)")
    }
    if $row.kind == "daemon" and not ($probe.stale_loops | is-empty) {
        return (leg-row $row "warn" $"beat (age-words $probe.beat_age_s) — stale loops: ($probe.stale_loops | str join ', ')")
    }
    if $row.kind == "periodic" and $probe.last_exit != 0 {
        return (leg-row $row "fail" $"last run exited ($probe.last_exit)")
    }
    if $row.kind == "daemon" {
        return (leg-row $row "ok" $"running · beat (age-words $probe.beat_age_s)")
    }
    (leg-row $row "ok" "loaded · last run exited 0")
}

# THE repair — the least action that could restore the bot. `loaded` decides
# kickstart vs bootstrap; a missing plist is hands-work (never invented); and a
# deploy in flight silences every repair: the bot is down ON PURPOSE while its
# deploy job swaps it.
export def repair [row: BotRow, probe: BotProbe, deploy_in_flight: bool]: nothing -> Repair {
    if not $probe.loaded and not $probe.plist {
        return {action: "missing-plist", why: $"no plist for ($row.label) — hands needed"}
    }
    if $deploy_in_flight {
        return {action: "hands-off", why: $"($row.deploy) in flight — wait for it"}
    }
    if $probe.loaded {
        return {action: "kickstart", why: $"kickstart -k ($row.label)"}
    }
    {action: "bootstrap", why: $"bootstrap ($row.label) — launchd forgot the job"}
}
