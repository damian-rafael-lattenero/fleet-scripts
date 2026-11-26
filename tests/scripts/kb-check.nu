# kb-check.nu — the script end to end on a fixture folder built for the run:
# the template is read as the law, a clean note passes, each break shows as its
# own finding (the cap, the headings, a citation that is not on disk, a note
# outside the INDEX) and the exit is 1; an INDEX id without a note is pending,
# not a finding. Nothing touches a real KB.
# covers: /Users/lattenero/Scripts/scripts/kb-check.nu
use std/assert

const SELF: path = (path self)
const SCRIPT: path = ($SELF | path expand | path dirname | path dirname | path dirname | path join 'scripts' 'kb-check.nu')
const TEMPLATE: string = "# <Title>\n\n> **Denotes.** <One sentence.>\n\n## The shape\n## Sources\n"

# Five filler lines: with them `late` is thirteen lines, one past the cap.
const FILLER: string = "- filler\n- filler\n- filler\n- filler\n- filler\n"

# What a run answers.
type Run = record<exit_code: int, stdout: string, stderr: string>

# A file with its text.
def put [path: path, text: string]: nothing -> nothing {
    mkdir ($path | path dirname)
    $text | save --force $path
}

# Fire the script over a folder, with or without the JSON switch.
def fire [dir: path, projects: path, cap: int, json: bool]: nothing -> Run {
    let cap_arg: string = ($cap | into string)
    let args: list<string> = (if $json { [$dir --json --projects $projects --max-lines $cap_arg] } else { [$dir --projects $projects --max-lines $cap_arg] })
    do { ^$nu.current-exe $SCRIPT ...$args } | complete
}

# A note's head — the title and the denotation the law wants on top — and its sections.
def note [id: string, rest: string]: nothing -> string {
    $"# ($id) — `($id)`\n\n> **Denotes.** a note\n\n($rest)\n"
}

let root: path = (mktemp -d -t 'kb-check.XXXXXX')
let notes: path = ($root | path join 'kb' 'notes')
let projects: path = ($root | path join 'projects')
put ($notes | path join '_TEMPLATE.md') $TEMPLATE
put ($notes | path join 'INDEX.md') "| `good` | Good | H01 |\n| `late` | Late | H02 |\n| `ghost` | Ghost | H03 |\n"
put ($notes | path join 'README.md') 'the law itself, never a note'
put ($root | path join 'kb' 'official' 'lyah' 'a.md') 'mirror'
put ($projects | path join 'other-kb' 'official' 'b.md') 'mirror'
put ($notes | path join 'good.md') (note 'good' "## The shape\nReads `../official/lyah/a.md` and `other-kb/official/b.md`.\n\n## Sources\n- x")
put ($notes | path join 'late.md') (note 'late' $"## Sources\n- x\n($FILLER)## The shape\nReads `../official/lyah/none.md` and `laws/test/Canon/Late.hs`.")
put ($notes | path join 'stray.md') (note 'stray' "## The shape\nNo citation here.\n\n## Sources\n- x")

let out: Run = (fire $notes $projects 12 true)
assert equal ($out.stderr | str trim) '' $"the script must answer, never error: ($out.stderr)"
assert equal $out.exit_code 1 'exit 1 on findings'
let found: list<string> = ($out.stdout | from json | select note problem | each {|f| $"($f.note): ($f.problem)" } | sort)
assert equal $found [
    'late.md: 13 lines, the cap is 12'
    'late.md: cites a missing path: ../official/lyah/none.md'
    'late.md: cites a missing path: laws/test/Canon/Late.hs'
    'late.md: headings differ from the template — The shape / Sources; found Sources / The shape'
    'stray.md: a note the INDEX does not list'
]

let text: Run = (fire $notes $projects 12 false)
assert equal ($text.stderr | str trim) ''
assert equal ($text.stdout | str contains '3 notes · 5 findings · INDEX 3 ids, 1 pending') true
assert equal ($text.stdout | str contains 'pending: ghost') true

put ($notes | path join 'late.md') (note 'late' "## The shape\nReads `../official/lyah/a.md`.\n\n## Sources\n- x")
rm ($notes | path join 'stray.md')
let clean: Run = (fire $notes $projects 12 false)
assert equal ($clean.stderr | str trim) ''
assert equal $clean.exit_code 0 $"exit 0 when every note keeps its law: ($clean.stdout)"
assert equal ($clean.stdout | str contains '2 notes · 0 findings') true
assert equal ($clean.stdout | str contains 'every note keeps its law') true

rm -r -f $root
print 'scripts/kb-check ok — the template as law, five findings with exit 1, pending ≠ finding, exit 0 when clean'
