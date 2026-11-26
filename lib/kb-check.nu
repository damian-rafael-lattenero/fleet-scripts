# kb-check.nu core — a notes folder's maintenance law as predicates over text:
# the shape a template gives (headings, the denotation on top, the line cap),
# the paths a note cites, the quotations it puts in a mirror's mouth, the ids
# its INDEX lists. Everything here answers from its arguments alone; the
# script asks the filesystem.

# A citation is a code span that starts as one of three families, each relative
# to the note that cites it: this KB's mirror (`../../official/…`), this repo's
# laws (`../laws/…`), or another KB's mirror under the projects dir.
const MINE: string = '^\.\./(.*/)?(official|laws)/'
const OTHERS: string = '^[\w-]+-kb/official/'

# The shortest span read as a quotation: below it a quoted word is a term, not a claim.
const QUOTE_MIN: int = 20

# The line that opens a block of its own: a list item or a heading.
const OPENER: string = '^(-|\*|\d+\.|#+)\s'

# What one note says about itself before the filesystem is asked.
export type Shape = record<headings: list<string>, denotes: bool, cites: list<string>>

# One broken law, readable.
export type Finding = record<note: string, problem: string>

# One mirror: the name a note cites it by (its folder, lowercased) and its whole text, flattened.
export type Mirror = record<name: string, text: string>

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

# The prose as blocks, the unit a quotation may wrap in: a paragraph broken
# over several lines is one block; a list item and a heading are each their own.
export def blocks [text: string]: nothing -> list<string> {
    prose $text | each {|l| $l | str trim } | str join "\n"
    | split row "\n\n"
    | each {|chunk| $chunk | str trim }
    | where {|chunk| not ($chunk | is-empty) }
    | each {|chunk|
        let rows: list<string> = ($chunk | split row "\n")
        let items: bool = (($rows | first) =~ $OPENER)
        if $items { $rows | where {|r| not ($r | is-empty) } } else { [($rows | str join ' ')] }
    }
    | flatten
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

# A text as one line for comparison. What a quotation is NOT checked for —
# markup, quote marks, dashes, spacing, capitalisation — is dropped; what is
# left is its words in their order.
export def flat [text: string]: nothing -> string {
    $text
    | str replace -a -r '</?[a-zA-Z][^<>]{0,200}>' ''
    | str replace -a '`' ''
    | str replace -a '[' ''
    | str replace -a ']' ''
    | str replace -a '"' ''
    | str replace -a "'" ''
    | str replace -a '“' ''
    | str replace -a '”' ''
    | str replace -a '‘' ''
    | str replace -a '’' ''
    | str replace -a '—' ' '
    | str replace -a '–' ' '
    | str replace -a -r '\s+' ' '
    | str trim
    | str lowercase
}

# The quotations one block of prose puts in a source's mouth: its
# double-quoted spans, the long pieces only. An elision (`...`) splits a span;
# an editorial bracket (`suppl[ies]`) declares a change, so the piece it ends
# is dropped and the rest is still checked.
export def quotes-in [block: string]: nothing -> list<string> {
    $block | str replace -a '`' '' | split row '"' | enumerate | where {|t| ($t.index mod 2) == 1 } | get item
    | each {|span| $span | split row '...' } | flatten
    | each {|span|
        let pieces: list<string> = ($span | split row -r '\[[^\]]*\]')
        let kept: list<string> = (if ($pieces | length) > 1 { $pieces | skip 1 } else { $pieces })
        $kept
    }
    | flatten
    | each {|seg| flat $seg } | where {|seg| ($seg | str length) >= $QUOTE_MIN }
}

# The quotations a note puts in a mirror's mouth that the mirror does not say.
# Only a block that names a mirror is read as a claim about it.
export def misquotes [text: string, mirrors: list<Mirror>]: nothing -> list<string> {
    blocks $text
    | each {|block|
        let named: list<Mirror> = ($mirrors | where {|m| ($block | str lowercase) | str contains $m.name } )
        let unheard: list<string> = (if ($named | is-empty) { [] } else { quotes-in $block | where {|q| not ($named | any {|m| $m.text | str contains $q }) } })
        $unheard
    }
    | flatten
}

# The laws one note breaks, given the template's headings and the line cap;
# `missing` is what the filesystem said about its cited paths and `misquoted`
# what the mirrors said about its quotations. The headings are compared in
# order and in case.
export def findings [note: string, text: string, expected: list<string>, max_lines: int, missing: list<string>, misquoted: list<string>]: nothing -> list<Finding> {
    let seen: Shape = (shape $text)
    let count: int = ($text | lines | length)
    let found: string = ($seen.headings | str join ' / ')
    let too_long: list<Finding> = (if $count > $max_lines { [{note: $note, problem: $"($count) lines, the cap is ($max_lines)"}] } else { [] })
    let no_denotation: list<Finding> = (if not $seen.denotes { [{note: $note, problem: 'no one-sentence denotation on top'}] } else { [] })
    let drifted: list<Finding> = (if $seen.headings != $expected { [{note: $note, problem: $"headings differ from the template — ($expected | str join ' / '); found ($found)"}] } else { [] })
    let broken: list<Finding> = ($missing | each {|p| {note: $note, problem: $"cites a missing path: ($p)"} })
    let unheard: list<Finding> = ($misquoted | each {|q| {note: $note, problem: $"quotes what the mirror does not say: ($q | str substring 0..90)"} })
    [$too_long $no_denotation $drifted $broken $unheard] | flatten
}

# The ids an INDEX lists: the first cell of each table row.
export def index-ids [text: string]: nothing -> list<string> {
    $text | parse -r '(?m)^\| `(?<id>[a-z0-9-]+)` \|' | get id
}
