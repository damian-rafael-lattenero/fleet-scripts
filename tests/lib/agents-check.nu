# agents-check.nu — the core on literal texts: every code span of a line is
# read (two on one line, none from inside a fenced block, none from a line
# whose backtick is unpaired); each family is recognized by its shape and
# prose is not (a placeholder, a bare `.md` name, a quoted sample); the
# `fleet` verb is taken from a span that carries arguments; under given
# predicates a hook is found in either dir it is looked up in, a
# repo-relative path is rooted under the projects dir, a home path is
# expanded, an explicit verb needs no file, an MCP tool holds only when
# served; and the size counts lines, words, bytes, bullets, sections and
# duplicates.
use std/assert
use ../../lib/agents-check.nu *

# The text under test: every family once, prose of three kinds, a fenced block
# with a look-alike, and one bullet written twice.
const TEXT: string = (
    "# Law\n\n> Read `~/Projects/agent-brain` first: `fleet healthcheck`, then `fleet wt-done <slug>`.\n\n"
    + "## Gates\n\n- `write-guard.nu` and `kotlin-law.nu`; prose: `canon-map.md`; broken: `ghost.nu`\n"
    + "- tools `mcp__serper__scrape` and `mcp__serper__gone`\n\n"
    + "```nu\n'inside a fence `not-a-cite.nu` b'\n```\n\n"
    + "- `write-guard.nu` and `kotlin-law.nu`; prose: `canon-map.md`; broken: `ghost.nu`\n"
)

# The roots, and existence as two lists: nothing here touches the disk.
const ROOTS: Roots = {lookups: ['/first' '/second'], projects: '/projects', hub: '/hub'}
const PRESENT: list<string> = ['/second/write-guard.nu' '/first/kotlin-law.nu' '/projects/kb/notes/a.md' '/hub/wt-done.nu']
const SERVED: list<string> = ['mcp__serper__scrape']

def on-disk [p: string]: nothing -> bool {
    $p in ($PRESENT | append ($env.HOME | path join 'Projects' 'agent-brain'))
}

def served [tool: string]: nothing -> bool {
    $tool in $SERVED
}

# 1. spans: every span of a line, in order; none from a fence or an unpaired line.
assert equal (spans "a `one.nu` b `two.nu` c") ['one.nu' 'two.nu']
assert equal (spans "an `unpaired backtick") []
assert equal (spans "```\n'a `fence.nu` b'\n```\nafter `real.nu`") ['real.nu']
assert equal (spans $TEXT | where {|s| $s == 'not-a-cite.nu' }) []

# 2. cites: each family read once; prose dropped.
assert equal (cite-of 'canon-map.md') null
assert equal (cite-of 'wt <slug>') null
assert equal (cite-of '"$HOME/x"') null
assert equal (cites $TEXT | select kind ref | sort-by ref) [
    {kind: 'hook-or-script', ref: 'ghost.nu'}
    {kind: 'fleet-verb', ref: 'healthcheck'}
    {kind: 'hook-or-script', ref: 'kotlin-law.nu'}
    {kind: 'mcp-tool', ref: 'mcp__serper__gone'}
    {kind: 'mcp-tool', ref: 'mcp__serper__scrape'}
    {kind: 'hook-or-script', ref: 'write-guard.nu'}
    {kind: 'fleet-verb', ref: 'wt-done'}
    {kind: 'path', ref: '~/Projects/agent-brain'}
]

# 3. verdicts under the given predicates: the broken ones by name, eight in all.
let all: list<Verdict> = (verdicts $TEXT $ROOTS {|p| on-disk $p } {|t| served $t })
assert equal ($all | length) 8
assert equal (broken $all | get ref | sort) ['ghost.nu' 'mcp__serper__gone']

# 4. stats: lines without the closing one, words by whitespace, bytes, bullets,
#    sections, and a bullet written twice.
assert equal (stats "# T\n\n- a\n- b\n") {lines: 4, words: 6, bytes: 13, bullets: 2, sections: 0, duplicates: 0}
assert equal (stats "# T\n\n## A\n## B\n\nx" | select lines sections) {lines: 6, sections: 2}
assert equal (stats $TEXT | get duplicates) 1

print 'lib/agents-check ok — every span of a line, none from a fence, five families, prose dropped, lookup order, rooting, expansion, explicit verbs, served tools, the size'
