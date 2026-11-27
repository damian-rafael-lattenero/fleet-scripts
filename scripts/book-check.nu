#!/opt/homebrew/bin/nu
# book-check.nu — the book's maintenance law, mechanically: the route sheet is
# the contract (a listed id without a card is pending, a card it does not list
# is a finding), the card template gives the eight stops and the minimum path,
# and every written card must keep them in order — under the line cap, with no
# paragraph over the word cap, in English, with no clinical language, every
# cited path on disk, and no term used before the card that introduces it.
# The answers live in G-answers.md, one `## <id>` block per written card.
#
#   nu ~/Scripts/scripts/book-check.nu <book-dir> [--max-lines 150] [--max-words 100] [--json]
use ../lib/kb-check.nu [headings prose blocks]
use ../lib/lang-detect.nu [spanish-line?]

const SHEET: string = '00-route-sheet.md'
const TEMPLATE: string = '_CARD_TEMPLATE.md'
const GLOSSARY: string = 'glossary.tsv'
const ANSWERS: string = 'G-answers.md'

# The book's own documents are not cards.
const NOT_CARDS: list<string> = ['00-route-sheet.md' '_CARD_TEMPLATE.md' 'G-answers.md' 'README.md']

# The words that would turn the book into clinical advice. The book names none of this.
const CLINICAL: string = '(?i)(?<w>\b(adhd|bipolar|hypomani[a-z]*|manic|depress[a-z]*|disorder[s]?|diagnos[a-z]*|symptom[s]?|medicat[a-z]*|clinical|psychiatr[a-z]*|therap[a-z]*|mental illness)\b)'

# A code span read as a citation: repo-relative, home-relative or absolute — never a URL, a glob or an example.
const PATHISH: string = '^(~/|/|[A-Za-z0-9_.-]+/)'

type Card = record<id: string, index: int, done: bool, title: string>
type Finding = record<card: string, problem: string>
type Term = record<term: string, card: string>

# The cards the route sheet lists, in study order. The answer key (G) is not a card.
def cards-of [text: string]: nothing -> list<Card> {
    let rows: list<record> = ($text | lines | parse -r '^- \[(?<mark>[ xX])\] (?<id>[A-Z0-9][A-Za-z0-9.]*) (?<title>.+)$')
    $rows | enumerate | each {|r|
        let mark: string = ($r.item.mark | str trim)
        {id: $r.item.id, index: $r.index, done: ($mark != ''), title: ($r.item.title | str trim)}
    } | where {|c| $c.id != 'G' }
}

# The glossary: term, tab, the card that introduces it. `#` lines are the law's own notes;
# the note `# verb-homographs: a, b, c` names the terms whose -s forms are ordinary
# English verbs, exempt from plural matching (data, not code — measured 27/11:
# 12 of 18 mechanical plural findings were verbs: allows, turns, stops, asks, traps).
def verb-terms-of [text: string]: nothing -> list<string> {
    $text | lines
    | where {|l| ($l | str trim | str starts-with '# verb-homographs:') }
    | first
    | default '# verb-homographs:'
    | str replace -a '# verb-homographs:' ''
    | split row ','
    | each {|t| $t | str trim | str lowercase }
    | where {|t| not ($t | is-empty) }
}

# The glossary: term, tab, the card that introduces it. `#` lines are the law's own notes.
def glossary-of [text: string]: nothing -> list<Term> {
    $text | lines
    | where {|l| not ($l | str trim | str starts-with '#') }
    | where {|l| not ($l | str trim | is-empty) }
    | parse -r '^(?<term>[^\t]+)\t(?<card>[A-Z0-9][A-Za-z0-9.]*)\s*$'
    | each {|r| {term: ($r.term | str trim), card: $r.card}}
}

# The lines under one `## ` heading, up to the next heading.
def section-of [text: string, name: string]: nothing -> list<string> {
    let rows: list<string> = ($text | lines)
    let heads: list<int> = ($rows | enumerate | where {|r| $r.item | str starts-with '## ' } | get index)
    let start: int = ($rows | enumerate | where {|r| ($r.item | str trim) == ('## ' + $name) } | get index | first | default (-1))
    if $start < 0 { return [] }
    let after: list<int> = ($heads | where {|i| $i > $start })
    let stop: int = ($after | first | default ($rows | length))
    $rows | skip ($start + 1) | first (($stop - $start) - 1)
}

# The words of one block, whitespace-collapsed.
def word-count [block: string]: nothing -> int {
    $block | split row -r '\s+' | where {|w| not ($w | is-empty) } | length
}

# The paths one card cites: its code spans outside fences, filtered to the path families.
def cites-of [text: string]: nothing -> list<string> {
    prose $text
    | each {|l| $l | split row '`' | enumerate | where {|t| ($t.index mod 2) == 1 } | get item }
    | flatten
    | where {|span| ($span =~ $PATHISH) and (not ($span =~ '^https?:')) and (not ($span =~ '[*<>{}]')) }
    | uniq
}

# Where a cited path is rooted: `~/` at home, `Scripts/…` at home, anything else under the projects dir.
def resolve-cite [cite: string, projects: string, home: string]: nothing -> string {
    if ($cite | str starts-with '~/') { return ($home + ($cite | str substring 1..)) }
    if ($cite | str starts-with '/') { return $cite }
    if ($cite | str starts-with 'Scripts/') { return ($home + '/' + $cite) }
    ($projects + '/' + $cite)
}

# Whether a term appears in the card's prose (code spans and quotes are not read).
# The PLURAL LAW (27/11, closing U3's documented hole): a plural slips the
# singular's boundary check — `hook` never matches inside `hooks` — so the
# term's mechanical plurals (s, es, y→ies) count as the term too. Bounded on
# purpose: compounds like `tooling` or `gatekeeper` still never match.
def term-used? [text: string, term: string, exempt: list<string>]: nothing -> bool {
    let plain: string = ($text
        | str replace -a -r '`[^`]*`' ''
        | str replace -a -r '"[^"]*"' ''
        | str replace -a -r "(?<![A-Za-z0-9])'[^']*'(?![A-Za-z0-9])" '')
    # The verb-homograph terms never plural-match: their -s forms are ordinary
    # English verbs (the turn stops, which allows, the question asks, it never
    # traps), not the concept. The list is DATA in the glossary file, not code.
    let forms: list<string> = (
        [$term, ($term + 's'), ($term + 'es')]
        | append (if ($term | str ends-with 'y') { ($term | str substring 0..(($term | str length) - 2)) + 'ies' } else { '' })
        | where {|f| $f != '' }
        | uniq
    )
    let checked: list<string> = (if ($term | str lowercase) in $exempt { [$term] } else { $forms })
    $checked | any {|form|
        let pattern: string = ('(?i)(?<![A-Za-z0-9_-])' + ($form | str replace -a ' ' '\\s+') + '(?![A-Za-z0-9_-])')
        ($plain =~ $pattern)
    }
}

# The laws one card breaks. `missing` is what the filesystem said about its paths.
def findings-of [file: string, text: string, card: Card, expected: list<string>, order: record, terms: list<Term>, verb_terms: list<string>, maxLines: int, maxWords: int, missing: list<string>]: nothing -> list<Finding> {
    let note: string = ($file | path basename)
    let seen: list<string> = (headings $text)
    let top: string = ($text | lines | first 6 | str join "\n")
    let lines: int = ($text | lines | length)
    let long: list<string> = (blocks $text | where {|b| (word-count $b) > $maxWords } | each {|b| $b | str substring 0..60 })
    let spanish: list<string> = (prose $text | each {|l| $l | str replace -a -r '`[^`]*`' '' | str replace -a -r '"[^"]*"' '' } | where {|l| spanish-line? $l } | each {|l| $l | str trim | str substring 0..60 })
    let clinical: list<string> = ($text | str lowercase | parse -r $CLINICAL | get -o w | default [] | uniq)
    # The term law reads the card's PROSE: fenced examples and the template's own
    # headings are furniture, not teaching (the mandatory "Retrieval questions"
    # heading must not push a card past the glossary that introduces `retrieval`).
    let body: string = (prose $text | where {|l| not ($l | str starts-with '#') } | str join "\n")
    let later: list<string> = ($terms | where {|t| (($order | get -o $t.card | default 9999) > $card.index) and (term-used? $body $t.term $verb_terms) } | each {|t| $t.term })
    let minimum: string = (section-of $text 'Minimum path' | str join ' ' | str lowercase)
    let stops: list<string> = (['aha' 'signature' 'checkpoint'] | where {|w| not ($minimum | str contains $w) })
    let questions: int = (section-of $text '7 · Retrieval questions' | each {|l| $l | str trim } | where {|t| ($t =~ '^[123]\. ') } | length)
    let shape: list<Finding> = (if $seen == $expected { [] } else { [{card: $note, problem: ($"headings differ from the template — ($expected | str join ' / '); found ($seen | str join ' / ')")}] })
    let cap: list<Finding> = (if $lines > $maxLines { [{card: $note, problem: ($"($lines) lines, the cap is ($maxLines)")}] } else { [] })
    let denotes: list<Finding> = (if ($top | str contains '**Denotes.**') { [] } else { [{card: $note, problem: 'no one-sentence denotation on top'}] })
    let paragraphs: list<Finding> = ($long | each {|b| {card: $note, problem: ($"a paragraph over ($maxWords) words: ($b)")} })
    let language: list<Finding> = ($spanish | each {|l| {card: $note, problem: ($"reads Spanish: ($l)")} })
    let advice: list<Finding> = ($clinical | each {|w| {card: $note, problem: ($"clinical language: ($w)")} })
    let cites: list<Finding> = ($missing | each {|p| {card: $note, problem: ($"cites a missing path: ($p)")} })
    let early: list<Finding> = ($later | each {|t| {card: $note, problem: ($"uses a term before its card: ($t)")} })
    let path: list<Finding> = (if ($stops | is-empty) { [] } else { [{card: $note, problem: ($"the minimum path does not name: ($stops | str join ' / ')")}] })
    let ask: list<Finding> = (if $questions == 3 { [] } else { [{card: $note, problem: ($"($questions) retrieval questions, the law wants 3")}] })
    [$shape $cap $denotes $paragraphs $language $advice $cites $early $path $ask] | flatten
}

def main [
    dir: path                          # the book folder
    --max-lines: int = 150             # the line cap the maintenance law states
    --max-words: int = 100             # the paragraph cap the maintenance law states
    --projects: string = '/Users/lattenero/Projects'
    --home: string = '/Users/lattenero'
    --json                             # the findings as JSON for a test
]: nothing -> nothing {
    let sheet: path = ($dir | path join $SHEET)
    let template: path = ($dir | path join $TEMPLATE)
    for p in [$sheet $template] {
        if not ($p | path exists) { print -e $"book-check: missing ($p)"; exit 2 }
    }
    let cards: list<Card> = (cards-of (open --raw $sheet))
    let expected: list<string> = (headings (open --raw $template))
    let terms: list<Term> = (if (($dir | path join $GLOSSARY) | path exists) { glossary-of (open --raw ($dir | path join $GLOSSARY)) } else { [] })
    let verb_terms: list<string> = (if (($dir | path join $GLOSSARY) | path exists) { verb-terms-of (open --raw ($dir | path join $GLOSSARY)) } else { [] })
    let order: record = ($cards | reduce --fold {} {|c, acc| $acc | upsert $c.id $c.index })
    let duplicates: list<Finding> = ($cards | group-by id --to-table | where {|g| ($g.items | length) > 1 } | each {|g| {card: $SHEET, problem: ($"($g.id) is listed twice")} })
    let files: list<string> = (glob ($dir | path join '*.md') | where {|f| not (($f | path basename) in $NOT_CARDS) } | sort)
    let written: list<record> = ($files | each {|f|
        let stem: string = ($f | path parse | get stem)
        let text: string = (open --raw $f)
        let missing: list<string> = (cites-of $text | where {|c| not ((resolve-cite $c $projects $home) | path exists) })
        {file: $f, stem: $stem, text: $text, missing: $missing}
    })
    let unlisted: list<Finding> = ($written | where {|w| not ($w.stem in ($cards | get id)) } | each {|w| {card: ($w.file | path basename), problem: 'a card the route sheet does not list'} })
    let found: list<Finding> = ($written | where {|w| $w.stem in ($cards | get id) } | each {|w|
        findings-of $w.file $w.text ($cards | where {|c| $c.id == $w.stem } | first) $expected $order $terms $verb_terms $max_lines $max_words $w.missing
    } | flatten)
    let ids: list<string> = ($written | where {|w| $w.stem in ($cards | get id) } | get stem)
    let answersPath: path = ($dir | path join $ANSWERS)
    let answers: string = (if ($answersPath | path exists) { open --raw $answersPath } else { '' })
    let noKey: list<Finding> = (if (($ids | is-not-empty) and (not ($answersPath | path exists))) { [{card: $ANSWERS, problem: 'the book has cards and no answer key'}] } else { [] })
    let unanswered: list<Finding> = (if ($answersPath | path exists) {
        $ids | where {|id| not ($answers =~ ('(?m)^#{2,3} ' + ($id | str replace -a '.' '\.') + '\b')) } | each {|id| {card: $ANSWERS, problem: ($"no answers for ($id)")} }
    } else { [] })
    let all: list<Finding> = ([$duplicates $unlisted $found $noKey $unanswered] | flatten)
    let pending: list<string> = ($cards | get id | where {|id| not ($id in $ids) })
    if $json {
        $all | to json -r | print
    } else {
        $all | each {|f| print $"✗ ($f.card): ($f.problem)" }
        print $"book-check ($dir): ($cards | length) cards listed · ($ids | length) written · ($all | length) findings · ($pending | length) pending"
        if not ($pending | is-empty) { print $"   pending: ($pending | str join ', ')" }
        if ($all | is-empty) { print '✓ every written card keeps its law' }
    }
    if not ($all | is-empty) { exit 1 }
}
