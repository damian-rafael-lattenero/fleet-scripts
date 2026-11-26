# kb-check.nu — the core of the notes check on literal texts: headings in
# order and case, the lines outside code fences, the three families of a
# citation (and only as code spans), where each is rooted, every finding the
# law produces, the INDEX ids (the first cell only), the quotations a note puts
# in a mirror's mouth.
use std/assert
use ../../lib/kb-check.nu *

const TEMPLATE: list<string> = ['The shape' 'It comes down to Haskell' 'The trap' 'Sources']

# A note that keeps the law: thirteen lines, both citation families, four sections.
const CLEAN: string = (
    "# Functor — `functor`\n\n> **Denotes.** A container mapped without changing what is inside.\n\n"
    + "## The shape\n`fmap id == id`\nReads `../official/lyah/source_md/ch02.md` and `haskell-kb/official/typeclassopedia/typeclassopedia.md`.\n"
    + "## It comes down to Haskell\n`fmap :: Functor f => (a -> b) -> f a -> f b`\n## The trap\nA function is not a functor.\n## Sources\n- LYAH\n"
)

# The same note, with one law broken at a time.
const SWAPPED: string = ($CLEAN | str replace -a 'The shape' '§1' | str replace -a 'It comes down to Haskell' 'The shape' | str replace -a '§1' 'It comes down to Haskell')
const LOWER: string = ($CLEAN | str replace '## The trap' '## the trap')
const NO_DENOTES: string = ($CLEAN | str replace '> **Denotes.**' 'Denotes.')

# 1. headings: the `## ` lines in order; deeper levels are not sections.
assert equal (headings $CLEAN) $TEMPLATE
assert equal (headings "# T\n### deep\n") []

# 2. prose: a fenced block leaves, fences included; the rest keeps its order.
const FENCED: string = "a\n```haskell\nb `../official/x/y.md`\n```\nc\n"
assert equal (prose $FENCED) [a c]

# 3. citations: the three families, as code spans, anchors dropped; the rest is not a citation.
assert equal (cites-in "see `../official/lyah/a.md#fmap`, `../../official/lyah/c.md`, `laws/test/Canon/F.hs`, `../laws/test/Canon/Functor.hs`, `haskell-kb/official/lyah/b.md` and `T?`, `fmap`, official/x.md, /commands/docs/x.md, `<mirror>/x.md`") [../official/lyah/a.md ../../official/lyah/c.md ../laws/test/Canon/Functor.hs haskell-kb/official/lyah/b.md]
assert equal (shape $FENCED).cites []
assert equal (shape $CLEAN).cites [../official/lyah/source_md/ch02.md haskell-kb/official/typeclassopedia/typeclassopedia.md]

# 4. rooted: another KB's mirror under the projects dir, the rest under the note's own folder.
assert equal (rooted 'haskell-kb/official/lyah/b.md' '/n/concepts' '/p') '/p/haskell-kb/official/lyah/b.md'
assert equal (rooted '../../official/lyah/c.md' '/n/notes/concepts' '/p') '/n/notes/concepts/../../official/lyah/c.md'
assert equal (rooted '../laws/test/Canon/F.hs' '/n/notes/concepts' '/p') '/n/notes/concepts/../laws/test/Canon/F.hs'

# 5. findings: a clean note breaks nothing; each law breaks on its own.
assert equal (findings 'functor.md' $CLEAN $TEMPLATE 120 [] []) []
let problems: list<string> = (findings 'functor.md' $CLEAN $TEMPLATE 3 ['../official/lyah/source_md/ch02.md'] [] | get problem)
assert equal $problems ["13 lines, the cap is 3" 'cites a missing path: ../official/lyah/source_md/ch02.md']
assert equal (findings 'f.md' $SWAPPED $TEMPLATE 120 [] [] | get problem) ['headings differ from the template — The shape / It comes down to Haskell / The trap / Sources; found It comes down to Haskell / The shape / The trap / Sources']
# the case of a heading is law too
assert equal (findings 'f.md' $LOWER $TEMPLATE 120 [] [] | get problem | length) 1
assert equal (findings 'f.md' $NO_DENOTES $TEMPLATE 120 [] [] | get problem) ['no one-sentence denotation on top']
assert equal (findings 'f.md' $CLEAN $TEMPLATE 120 [] ['the lazy brown fox jumps'] | get problem) ['quotes what the mirror does not say: the lazy brown fox jumps']

# 6. INDEX ids: the first cell of a row, never the Canon column beside it.
const INDEX: string = "| `category` | Category | H01 | `composition` | q |\n| `functor` | Functor | H02 | `functor` | q |\n\nFile names: `<id>.md` in this directory.\n"
assert equal (index-ids $INDEX) [category functor]
assert equal (index-ids '') []

# 7. quotations: the words of the long double-quoted spans of a line — markup,
# quote marks, dashes and capitalisation are not what a quotation is checked
# for; only a line that names a mirror makes a claim.
assert equal (flat "<b>Solid</b> arrows—it’s “here”") 'solid arrows its here'
# only a tag goes: an arrow or an operator between angle brackets is the manual's text
assert equal (flat "a -> b (<*>) and x < y > z") 'a -> b (<*>) and x < y > z'
assert equal (quotes-in "LYAH says \"the quick brown fox jumps\" and \"it *decides* what’s next: `f x`\".") ['the quick brown fox jumps' "it *decides* whats next: f x"]
assert equal (quotes-in "a gap seed: \"a term, not a claim\" and `code \"inside\" here`") []
assert equal (quotes-in "LYAH: \"the quick brown fox jumps ... over the very lazy dog now\".") ['the quick brown fox jumps' 'over the very lazy dog now']
# an editorial bracket declares a change: the piece it ends is dropped, the rest is checked
assert equal (quotes-in "LYAH: \"to section a function, only suppl[ies] a parameter on one side\".") ['a parameter on one side']
let mirrors: list<Mirror> = [{name: 'lyah', text: (flat "The quick brown fox jumps.\nIt *decides* what’s next: `f x`.")}]
assert equal (misquotes "LYAH says \"the quick brown fox jumps\" and \"it *decides* what’s next: `f x`\"." $mirrors) []
assert equal (misquotes "LYAH says \"the lazy brown fox jumps\" and \"the quick brown fox jumps\"." $mirrors) ['the lazy brown fox jumps']
assert equal (misquotes "No mirror is named: \"the lazy brown fox jumps\"." $mirrors) []

print 'lib/kb-check ok — headings, prose, three citation families, rooting, the findings, INDEX ids, quotations'
