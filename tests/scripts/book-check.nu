# book-check.nu — the script end to end on a book fixture built for the run: a
# clean card passes; each break shows as its own finding and the exit is 1 —
# the cap, a paragraph over the word cap, Spanish prose, clinical language, a
# cited path that is not on disk, a term used before its card, a minimum path
# missing a stop, two questions instead of three, drifted headings, a card the
# route sheet does not list, an answer key without the card's block, no key at
# all, and an id listed twice. A listed id without a card is pending, not a
# finding. Nothing touches the real book. Two clean cases pin the term law's
# boundary: the template's own heading and a fenced example are not prose.
# covers: /Users/lattenero/Scripts/scripts/book-check.nu
use std/assert

const SELF: path = (path self)
const SCRIPT: path = ($SELF | path expand | path dirname | path dirname | path dirname | path join 'scripts' 'book-check.nu')
const TEMPLATE: string = "# <id> · <title>\n\n**Denotes.** <one sentence.>\n\n## 1 · The aha\n## 2 · What it denotes\n## 3 · In your languages\n## 4 · In your system\n## 5 · Paper sheet\n## 6 · Drill\n## 7 · Retrieval questions\n## 8 · Close-out\n## Minimum path\n"
const SHEET: string = "# Route sheet\n\n- [ ] A0.1 First card\n- [ ] A0.2 Second card\n- [ ] B01 A concept\n- [ ] G The key\n"

# What a run answers.
type Run = record<exit_code: int, stdout: string, stderr: string>

# A file with its text.
def put [path: path, text: string]: nothing -> nothing {
    mkdir ($path | path dirname)
    $text | save --force $path
}

# A card with its head and its body.
def card [body: string]: nothing -> string {
    $"# A0.1 · First card\n\n**Denotes.** one sentence.\n\n($body)\n"
}

# The eight stops, in order, with the two variables a mutant changes.
def body [stop4: string, questions: string, minimum: string]: nothing -> string {
    $"## 1 · The aha\none line.\n\n## 2 · What it denotes\none line.\n\n## 3 · In your languages\none line.\n\n## 4 · In your system\n($stop4)\n\n## 5 · Paper sheet\none line.\n\n## 6 · Drill\none line.\n\n## 7 · Retrieval questions\n($questions)\n\n## 8 · Close-out\none line.\n\n## Minimum path\n($minimum)\n"
}

# Fire the script over the book fixture.
def fire [dir: path, projects: path, lines: int, words: int, json: bool]: nothing -> Run {
    let args: list<string> = [$dir --projects $projects --home $projects --max-lines ($lines | into string) --max-words ($words | into string)]
    let full: list<string> = (if $json { $args | append '--json' } else { $args })
    do { ^$nu.current-exe $SCRIPT ...$full } | complete
}

# The findings of a run, as "card: problem" lines.
def findings [out: Run]: nothing -> list<string> {
    $out.stdout | from json | each {|f| $"($f.card): ($f.problem)" }
}

let root: path = (mktemp -d -t 'book-check.XXXXXX')
let book: path = ($root | path join 'book')
let projects: path = ($root | path join 'projects')
let goodQuestions: string = "1. a\n2. b\n3. c"
let goodMinimum: string = 'the aha, the signature, the checkpoint'
put ($projects | path join 'thing' 'file.txt') 'x'
put ($book | path join '_CARD_TEMPLATE.md') $TEMPLATE
put ($book | path join '00-route-sheet.md') $SHEET
put ($book | path join 'glossary.tsv') "# verb-homographs: trap\nmonad\tB13\nretrieval\tC6\n"
put ($book | path join 'G-answers.md') "## A0.1\nanswers\n"

# 1. A clean card passes, and the three unwritten cards are pending.
put ($book | path join 'A0.1.md') (card (body 'Reads `thing/file.txt`.' $goodQuestions $goodMinimum))
let clean: Run = (fire $book $projects 150 100 false)
assert equal $clean.exit_code 0 $"a clean card must pass: ($clean.stdout)($clean.stderr)"
assert ($clean.stdout | str contains '1 written') 'the summary counts the written cards'
assert ($clean.stdout | str contains '2 pending') 'ids without a card are pending'
# The template's own heading carries a term (`retrieval`, C6): a heading is
# furniture, not the card teaching the term, so the clean card still exits 0.
# A fenced example is code, not prose: it does not put a term in the card's mouth.
put ($book | path join 'A0.1.md') (card ((body 'Reads `thing/file.txt`.' $goodQuestions $goodMinimum) + "\n```nu\nmonad\n```\n"))
let fenced: Run = (fire $book $projects 150 100 true)
assert equal $fenced.exit_code 0 $"a fenced example is not prose: ($fenced.stdout)"

# 2. The line cap.
put ($book | path join 'A0.1.md') (card ((body 'Reads `thing/file.txt`.' $goodQuestions $goodMinimum) + ((0..29) | each {|i| '- filler' } | str join "\n")))
let long: Run = (fire $book $projects 20 100 true)
assert equal $long.exit_code 1 'over the line cap is a finding'
assert (findings $long | any {|f| $f | str contains 'lines, the cap is 20' }) 'the cap names its number'

# 3. A paragraph over the word cap.
put ($book | path join 'A0.1.md') (card (body 'Reads `thing/file.txt`. one two three four five six seven eight nine ten eleven twelve.' $goodQuestions $goodMinimum))
let fat: Run = (fire $book $projects 150 10 true)
assert equal $fat.exit_code 1 'a paragraph over the cap is a finding'
assert (findings $fat | any {|f| $f | str contains 'a paragraph over' }) 'the paragraph finding names the cap'

# 4. Spanish prose.
put ($book | path join 'A0.1.md') (card (body 'Reads `thing/file.txt`. Esta línea está escrita en español y el control la tiene que ver.' $goodQuestions $goodMinimum))
let spanish: Run = (fire $book $projects 150 100 true)
assert equal $spanish.exit_code 1 'Spanish prose is a finding'
assert (findings $spanish | any {|f| $f | str contains 'reads Spanish' }) 'the finding says reads Spanish'

# 5. Clinical language.
put ($book | path join 'A0.1.md') (card (body 'Reads `thing/file.txt`. This card is about adhd and medication.' $goodQuestions $goodMinimum))
let clinical: Run = (fire $book $projects 150 100 true)
assert equal $clinical.exit_code 1 'clinical language is a finding'
assert (findings $clinical | any {|f| $f | str contains 'clinical language' }) 'the finding names the clinical word'

# 6. A cited path that is not on disk.
put ($book | path join 'A0.1.md') (card (body 'Reads `thing/absent.txt`.' $goodQuestions $goodMinimum))
let missing: Run = (fire $book $projects 150 100 true)
assert equal $missing.exit_code 1 'a missing citation is a finding'
assert (findings $missing | any {|f| $f | str contains 'cites a missing path: thing/absent.txt' }) 'the finding names the path'

# 7. A term used before its card (monad belongs to B13).
put ($book | path join 'A0.1.md') (card (body 'Reads `thing/file.txt`. A monad is not this card.' $goodQuestions $goodMinimum))
let early: Run = (fire $book $projects 150 100 true)
assert equal $early.exit_code 1 'a term before its card is a finding'
assert (findings $early | any {|f| $f | str contains 'uses a term before its card: monad' }) 'the finding names the term'

# 7b. The PLURAL LAW (27/11): a plural carries the term early too — `monads`
# before B13 flags — but a verb-homograph term's -s form is an ordinary verb
# (it traps nothing) and never matches, exactly as the glossary's note says.
put ($book | path join 'A0.1.md') (card (body 'Reads `thing/file.txt`. Monads everywhere in this prose.' $goodQuestions $goodMinimum))
let plural: Run = (fire $book $projects 150 100 true)
assert equal $plural.exit_code 1 'a plural term before its card is a finding'
assert (findings $plural | any {|f| $f | str contains 'uses a term before its card: monad' }) 'the plural finding names the singular term'
put ($book | path join 'A0.1.md') (card (body 'Reads `thing/file.txt`. The check traps nothing and harms no one.' $goodQuestions $goodMinimum))
let verb: Run = (fire $book $projects 150 100 true)
assert equal $verb.exit_code 0 $"a verb-homograph plural is not the term: ($verb.stdout)($verb.stderr)"

# 8. The minimum path missing a stop.
put ($book | path join 'A0.1.md') (card (body 'Reads `thing/file.txt`.' $goodQuestions 'the aha and the signature'))
let path: Run = (fire $book $projects 150 100 true)
assert equal $path.exit_code 1 'a minimum path without the checkpoint is a finding'
assert (findings $path | any {|f| $f | str contains 'does not name: checkpoint' }) 'the finding names the missing stop'

# 9. Two questions instead of three.
put ($book | path join 'A0.1.md') (card (body 'Reads `thing/file.txt`.' "1. a\n2. b" $goodMinimum))
let ask: Run = (fire $book $projects 150 100 true)
assert equal $ask.exit_code 1 'two questions are a finding'
assert (findings $ask | any {|f| $f | str contains '2 retrieval questions' }) 'the finding counts the questions'

# 10. Headings out of order.
put ($book | path join 'A0.1.md') (card ((body 'Reads `thing/file.txt`.' $goodQuestions $goodMinimum) | str replace '## 5 · Paper sheet' '## 5 · Something else'))
let drift: Run = (fire $book $projects 150 100 true)
assert equal $drift.exit_code 1 'drifted headings are a finding'
assert (findings $drift | any {|f| $f | str contains 'headings differ from the template' }) 'the finding compares with the template'

# 11. A card the route sheet does not list.
put ($book | path join 'A0.1.md') (card (body 'Reads `thing/file.txt`.' $goodQuestions $goodMinimum))
put ($book | path join 'Z99.md') (card (body 'Reads `thing/file.txt`.' $goodQuestions $goodMinimum))
let stray: Run = (fire $book $projects 150 100 true)
assert equal $stray.exit_code 1 'an unlisted card is a finding'
assert (findings $stray | any {|f| $f | str contains 'a card the route sheet does not list' }) 'the finding says unlisted'
rm ($book | path join 'Z99.md')

# 12. The answer key without this card, and no key at all.
put ($book | path join 'G-answers.md') "## A0.2\nanswers\n"
let unkeyed: Run = (fire $book $projects 150 100 true)
assert equal $unkeyed.exit_code 1 'an answer key without the card is a finding'
assert (findings $unkeyed | any {|f| $f | str contains 'no answers for A0.1' }) 'the finding names the card'
rm ($book | path join 'G-answers.md')
let keyless: Run = (fire $book $projects 150 100 true)
assert equal $keyless.exit_code 1 'cards without a key are a finding'
assert (findings $keyless | any {|f| $f | str contains 'no answer key' }) 'the finding says no key'

# 13. An id listed twice.
put ($book | path join 'G-answers.md') "## A0.1\nanswers\n"
put ($book | path join '00-route-sheet.md') ($SHEET + "- [ ] A0.1 First card again\n")
let twice: Run = (fire $book $projects 150 100 true)
assert equal $twice.exit_code 1 'a duplicate id is a finding'
assert (findings $twice | any {|f| $f | str contains 'A0.1 is listed twice' }) 'the finding names the id'

print 'book-check: every law and both outcomes verified.'
