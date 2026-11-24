# lib/json-lines.nu — the one JSON-lines parse both the ledger and the
# scanner need: one JSON object per line, garbage dropped. 0.117's `from
# json` is LENIENT — a non-JSON line comes back as the string itself, so
# the record filter is what makes the parse honest (measured 24/11 twice:
# secret-scan's trufflehog output and ram-clean's ledger).
export def record-lines [text: string]: nothing -> list<any> {
    $text
    | lines
    | where {|l| ($l | str trim | is-not-empty) }
    | each {|l| try { $l | from json } catch { null } }
    | where {|o| ($o | describe) =~ '^record' }
}
