# agents-check.nu core — an instruction file's citations as predicates over
# its text. A citation is a code span outside a fenced block; its shape alone
# names its family — a hook or hub script, an absolute or home-rooted path, a
# path relative to the projects dir, a `fleet` verb, an MCP tool — and the
# family says what would satisfy it. Nothing here asks the disk or the client:
# the script hands in two predicates, so the core is proven on literals.
#
# Born 27/11 on the owner's AGENTS.md: a throwaway checker had read ONE code
# span per line (`parse --regex` stops at the first match) and called the file
# proven. This core reads every span, and tests/lib/agents-check.nu pins it.

# One citation: the family it was read as, and what it names.
export type Cite = record<kind: string, ref: string>

# A citation with its verdict.
export type Verdict = record<kind: string, ref: string, ok: bool>

# The size of a file — the budget every session pays to read it.
export type Stats = record<lines: int, words: int, bytes: int, bullets: int, sections: int, duplicates: int>

# Where the file families resolve: the dirs a hook or script name is looked
# up in, the dir a repo-relative path is rooted at, and the dir the `fleet`
# verbs are scripts in.
export type Roots = record<lookups: list<string>, projects: string, hub: string>

# The `fleet` verbs that are not a script in the hub: fleet.nu answers them.
export const EXPLICIT_VERBS: list<string> = ['healthcheck' 'list' 'help']

# The MCP tools an instruction file may name — DATA, kept by hand in step with
# the client's servers. A tool the file names and the client no longer serves
# is exactly what the check must catch.
export const MCP_TOOLS: list<string> = [
    'mcp__plugin_brain-mcp_brain__rag_query'
    'mcp__plugin_brain-mcp_brain__memory_search'
    'mcp__serper__search_web'
    'mcp__serper__search_many'
    'mcp__serper__scrape'
    'mcp__serper__search_news'
]

# How a code span names a file: each family by its shape. A bare `.md` name is
# not a citation — `canon-map.md` is named for the reader and lives under two
# KBs at once.
type Family = record<kind: string, shape: string>

# One candidate reading of a span: whether it applies, and to what.
type Reading = record<applies: bool, kind: string, ref: string>

const FAMILIES: list<Family> = [
    {kind: 'hook-or-script', shape: '^[a-z0-9-]+\.nu$'}
    {kind: 'path', shape: '^(/.+/.+|/.+\.[a-z]+|~/.*)$'}
    {kind: 'repo-relative', shape: '^[a-z0-9-]+(/[A-Za-z0-9._-]+)+$'}
]

# A span carrying one of these is prose around a citation, never one.
const PLACEHOLDER: string = '[<>…* ]'

const VERB: string = '^fleet (?P<verb>[a-z-]+)'

# The fence fold: whether the line being read is inside a block, and the lines kept.
type Fence = record<inside: bool, kept: list<string>>

# The text without its fenced blocks: a line of code is never a citation.
export def unfenced [text: string]: nothing -> string {
    let state: Fence = ($text | split row "\n" | reduce --fold {inside: false, kept: []} {|line, acc|
        if ($line =~ '^\s*(```|~~~)') {
            {inside: (not $acc.inside), kept: $acc.kept}
        } else {
            {inside: $acc.inside, kept: ($acc.kept | append (if $acc.inside { '' } else { $line }))}
        }
    })
    $state.kept | str join "\n"
}

# Every code span of a text, in order: the odd parts of each line split on
# the backtick, only where the backticks pair up.
export def spans [text: string]: nothing -> list<string> {
    unfenced $text
    | split row "\n"
    | each {|line|
        let parts: list<string> = ($line | split row '`')
        if (($parts | length) mod 2) == 1 {
            $parts | enumerate | where {|part| ($part.index mod 2) == 1 } | get item
        } else {
            []
        }
    }
    | flatten
}

# The file family a span's shape names, or an empty string when it names none.
def family-of [span: string]: nothing -> string {
    $FAMILIES | where {|family| $span =~ $family.shape } | get -o kind.0 | default ''
}

# The `fleet` verb a span opens with, or an empty string.
def verb-of [span: string]: nothing -> string {
    $span | parse --regex $VERB | get -o verb.0 | default ''
}

# A span read as a citation, or null when it is prose: the first reading that
# applies wins.
export def cite-of [span: string]: nothing -> any {
    let verb: string = (verb-of $span)
    let family: string = (family-of $span)
    let readings: list<Reading> = [
        {applies: ($span | str starts-with 'mcp__'), kind: 'mcp-tool', ref: $span}
        {applies: ($verb | is-not-empty), kind: 'fleet-verb', ref: $verb}
        {applies: (($family | is-not-empty) and (not ($span =~ $PLACEHOLDER))), kind: $family, ref: $span}
    ]
    $readings | where applies | select kind ref | first | default null
}

# Every citation of a text, each named once.
export def cites [text: string]: nothing -> list<Cite> {
    spans $text | each {|span| cite-of $span } | where {|cite| $cite != null } | uniq
}

# The paths that would satisfy a file citation, in lookup order.
def file-targets [cite: Cite, roots: Roots]: nothing -> list<string> {
    match $cite.kind {
        'hook-or-script' => ($roots.lookups | each {|dir| $dir | path join $cite.ref })
        'path' => [($cite.ref | path expand --no-symlink)]
        'repo-relative' => [($roots.projects | path join $cite.ref)]
        _ => []
    }
}

# Whether one citation holds, under the two predicates the caller supplies:
# `onDisk` for a path, `served` for an MCP tool name.
export def holds [cite: Cite, roots: Roots, onDisk: closure, served: closure]: nothing -> bool {
    match $cite.kind {
        'fleet-verb' => (($cite.ref in $EXPLICIT_VERBS) or (do $onDisk ($roots.hub | path join ($cite.ref + '.nu'))))
        'mcp-tool' => (do $served $cite.ref)
        _ => (file-targets $cite $roots | any {|p| do $onDisk $p })
    }
}

# Every citation of a text with its verdict.
export def verdicts [text: string, roots: Roots, onDisk: closure, served: closure]: nothing -> list<Verdict> {
    cites $text | each {|cite| {kind: $cite.kind, ref: $cite.ref, ok: (holds $cite $roots $onDisk $served)} }
}

# The citations that do not hold, in order.
export def broken [all: list<Verdict>]: nothing -> list<Verdict> {
    $all | where {|one| not $one.ok }
}

# The size of a text: lines, words and bytes; the bullets a reader must follow,
# the sections they sit in, and the bullets written twice.
export def stats [text: string]: nothing -> Stats {
    let rows: list<string> = ($text | split row "\n")
    let last: string = ($rows | last | default '')
    let lines: int = (if $last == '' { ($rows | length) - 1 } else { $rows | length })
    let bullets: list<string> = ($rows | where {|row| $row =~ '^\s*- ' })
    {
        lines: $lines
        words: ($text | split row --regex '\s+' | where {|word| ($word | str length) > 0 } | length)
        bytes: ($text | into binary | bytes length)
        bullets: ($bullets | length)
        sections: ($rows | where {|row| $row =~ '^## ' } | length)
        duplicates: ($bullets | each {|bullet| $bullet | str trim } | uniq -d | length)
    }
}
