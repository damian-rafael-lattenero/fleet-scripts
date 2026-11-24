# lib/fleet-errors.nu — the pure core of fleet-errors.nu: the error predicate,
# the stamp parse, the freshness rule and the per-log scan. The script keeps
# the file reads (tail) and the log voice.
use /Users/lattenero/Projects/nushell-fp/mods/fmt.nu *
use ./log-scan.nu *

export type LogScan = record<log: string, errors: int, fresh: int, last: string>

# Level tokens + failure markers, never bare words: "error"/"failed" inside
# English prose (reconcile sentences, live-card pings naming a file) are not
# errors — measured false positives 21/11.
export const ERROR_MARKER: string = '\sERROR\s|Exception|BUILD FAILED|(?i)fatal|✗'

export def trim100 [s: string]: nothing -> string {
    if ($s | str length) > 100 { $s | str substring 0..99 } else { $s }
}

# A leading stamp parses to a datetime; date-less stamps (brain log) parse as
# TODAY at that time, anything else is null.
export def line-stamp [line: string]: nothing -> oneof<datetime, nothing> {
    try { ($line | split row " " | get 0) | into datetime } catch { null }
}

# Fresh = inside the window AND not in the future: a stamp in the future is
# YESTERDAY's late line, never fresh.
export def is-fresh [line: string, cutoff: datetime, now: datetime]: nothing -> bool {
    let stamp: oneof<datetime, nothing> = (line-stamp $line)
    ($stamp != null) and ($stamp > $cutoff) and ($stamp <= $now)
}

# The whole per-log answer, pure from the already-read lines.
export def scan-lines [name: string, lines: list<string>, cutoff: datetime, now: datetime]: nothing -> LogScan {
    let errors: list<string> = ($lines | where {|l| $l =~ $ERROR_MARKER})
    let fresh: int = ($errors | where {|l| is-fresh $l $cutoff $now } | length)
    let last: string = (if ($errors | is-empty) { "" } else { hard-wrap (trim100 ($errors | last)) 35 })
    {log: $name, errors: ($errors | length), fresh: $fresh, last: $last}
}
