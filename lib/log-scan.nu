# lib/log-scan.nu — the one log sweep both log triage scripts share: a deploy
# log carries older runs in the same file, only the CURRENT run speaks
# (everything after the last run-start marker). Pure: lines in, lines out.
export def current-run [lines: list<string>, start: string]: nothing -> list<string> {
    let starts: list<int> = ($lines | enumerate | where {|it| $it.item =~ $start } | get index)
    if ($starts | is-empty) { $lines } else { $lines | skip ($starts | last) }
}
