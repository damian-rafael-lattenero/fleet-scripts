# lib/day.nu — the pure core of day.nu: the per-repo commit brief, the
# memory window filter (unparseable createdAt is epoch, never "now") and the
# capped memory brief. The script keeps git, the CLI and the log voice.
export type RepoBrief = record<repo: string, n: int, last: string>
export type MemoryBrief = record<kind: string, learned: string>

# One repo's brief from its oneline log: [] when quiet, one row otherwise.
export def repo-briefs [repo: string, lines: list<string>]: nothing -> list<RepoBrief> {
    let clean: list<string> = ($lines | where {|l| ($l | str trim) != "" })
    if ($clean | is-empty) { [] } else {
        [{repo: ($repo | path basename), n: ($clean | length), last: ($clean | first | str substring 0..59)}]
    }
}

# Only memories the window covers: an unparseable createdAt falls back to
# epoch (excluded), never to "now" (a silent include).
export def in-window [memories: list<any>, cutoff: datetime]: nothing -> list<any> {
    $memories | where {|m|
        ((try { $m.createdAt | into datetime } catch { null }) | default (0 | into datetime)) > $cutoff
    }
}

# The BRIEF: newest first (the CLI's own order), content cut at 90, cap 10.
export def memory-briefs [memories: list<any>]: nothing -> list<MemoryBrief> {
    $memories | each {|m| {kind: $m.kind, learned: ($m.content | str substring 0..89)} } | first 10
}
