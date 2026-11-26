# kb-check.nu core — a notes folder's maintenance law as predicates over text:
# the shape a template gives (headings, the denotation on top, the line cap),
# the paths a note cites, the ids its INDEX lists. Everything here answers from
# its arguments alone; the script asks the filesystem.

# A citation is a code span that starts as one of three families, each relative
# to the note that cites it: this KB's mirror (`../../official/…`), this repo's
# laws (`../laws/…`), or another KB's mirror under the projects dir.
const MINE: string = '^\.\./(.*/)?(official|laws)/'
const OTHERS: string = '^[\w-]+-kb/official/'

# What one note says about itself before the filesystem is asked.
export type Shape = record<headings: list<string>, denotes: bool, cites: list<string>>

# One broken law, readable.
export type Finding = record<note: string, problem: string>

# The `## ` headings of a text, in order.
export def headings [text: string]: nothing -> list<string> {
    $text | lines | where {|l| $l =~ '^## ' } | each {|l| $l | str substring 3.. | str trim }
}

# The lines outside fenced code blocks: a path inside an example is not a citation.
export def prose [text: string]: nothing -> list<string> {
    $text | lines | reduce --fold {fence: false, rows: []} {|line, acc|
        let edge: bool = ($line | str trim | str starts-with '```')
        let kept: list<any> = (if ($edge or $acc.fence) { $acc.rows } else { $acc.rows | append $line })
        let next: record = {fence: ($acc.fence xor $edge), rows: $kept}
        $next
    } | get rows
}

# The paths one prose line cites: its code spans of the three families, anchors dropped.
export def cites-in [line: string]: nothing -> list<string> {
    $line | split row '`' | enumerate | where {|t| ($t.index mod 2) == 1 } | get item
    | where {|span| ($span =~ $MINE) or ($span =~ $OTHERS) }
    | each {|span| $span | str replace -r '#.*$' '' }
}

# Where a cited path is rooted: another KB's mirror under the projects dir, the rest under the note's own folder.
export def rooted [cite: string, notes: path, projects: path]: nothing -> path {
    let base: path = (if ($cite =~ $OTHERS) { $projects } else { $notes })
    $base | path join $cite
}

# What one note says about itself.
export def shape [text: string]: nothing -> Shape {
    let outside: list<string> = (prose $text)
    let top: string = ($text | lines | first 6 | str join "\n")
    let cites: list<string> = ($outside | each {|l| cites-in $l } | flatten | uniq)
    let seen: Shape = {headings: (headings $text), denotes: ($top | str contains '**Denotes.**'), cites: $cites}
    $seen
}

# The laws one note breaks, given the template's headings and the line cap;
# `missing` is what the filesystem said about its cited paths. The headings
# are compared in order and in case.
export def findings [note: string, text: string, expected: list<string>, max_lines: int, missing: list<string>]: nothing -> list<Finding> {
    let seen: Shape = (shape $text)
    let count: int = ($text | lines | length)
    let found: string = ($seen.headings | str join ' / ')
    let too_long: list<Finding> = (if $count > $max_lines { [{note: $note, problem: $"($count) lines, the cap is ($max_lines)"}] } else { [] })
    let no_denotation: list<Finding> = (if not $seen.denotes { [{note: $note, problem: 'no one-sentence denotation on top'}] } else { [] })
    let drifted: list<Finding> = (if $seen.headings != $expected { [{note: $note, problem: $"headings differ from the template — ($expected | str join ' / '); found ($found)"}] } else { [] })
    let broken: list<Finding> = ($missing | each {|p| {note: $note, problem: $"cites a missing path: ($p)"} })
    [$too_long $no_denotation $drifted $broken] | flatten
}

# The ids an INDEX lists: the first cell of each table row.
export def index-ids [text: string]: nothing -> list<string> {
    $text | parse -r '(?m)^\| `(?<id>[a-z0-9-]+)` \|' | get id
}
