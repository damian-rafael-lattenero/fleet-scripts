#!/opt/homebrew/bin/nu
# kb-check.nu — a notes folder against its maintenance law, mechanically: the
# father's half of a subagent review, and the check a mirror update owes. For
# every note: the template's headings in order, the one-sentence denotation on
# top, the line cap — and every cited path ON DISK, each one relative to the
# note that cites it (a citation nobody can open is how a KB written by a model
# fails). With --mirror: every quotation in a block that names a mirror must be
# in that mirror — a sentence the manual never said is the other way to fail.
# The INDEX is the contract: an id it lists without a note is pending, a note
# it does not list is a finding.
#
#   nu ~/Scripts/scripts/kb-check.nu <notes-dir> [--max-lines 120] [--mirror <dir>] [--json]
#
# A worktree sits away from the mirror, so `../../official/` resolves nowhere
# from it: --as-if <real notes dir> reads the notes as if they were merged.
use ../lib/kb-check.nu *

const PROJECTS: path = '/Users/lattenero/Projects'

# The folder's own documents — the shape, the map, the law — are not notes.
const NOT_NOTES: list<string> = [_TEMPLATE.md INDEX.md README.md]

# The mirrors under a folder: each the name a note cites it by and its whole text.
def mirrors-under [root: path]: nothing -> list<Mirror> {
    glob ($root | path join '*') | where {|p| ($p | path type) == 'dir' } | each {|p|
        let files: list<string> = (glob ($p | path join '**' '*.md'))
        let mirror: Mirror = {name: ($p | path basename | str lowercase), text: (flat ($files | each {|f| open --raw $f } | str join "\n"))}
        $mirror
    }
}

def main [
    dir: path                       # the folder of <id>.md and _TEMPLATE.md
    --max-lines: int = 120          # the cap the maintenance law states
    --projects: path = $PROJECTS    # where the other KBs live (haskell-kb/official/…)
    --mirror: path = ''             # the mirrors' folder — a block that names one must quote it
    --as-if: path = ''              # the folder the notes will live in once merged
    --json                          # the findings as JSON for a test or another script
]: nothing -> nothing {
    let template: path = ($dir | path join '_TEMPLATE.md')
    if not ($template | path exists) {
        print -e $"kb-check: no _TEMPLATE.md in ($dir)"
        exit 2
    }
    let home: path = (if ($as_if | is-empty) { $dir } else { $as_if })
    let expected: list<string> = (headings (open --raw $template))
    let notes: list<string> = (glob ($dir | path join '*.md') | where {|f| not (($f | path basename) in $NOT_NOTES) } | sort)
    let indexPath: path = ($dir | path join 'INDEX.md')
    let index: string = (if ($indexPath | path exists) { open --raw $indexPath } else { '' })
    let listed: list<string> = (index-ids $index)
    let stems: list<string> = ($notes | each {|f| $f | path parse | get stem })
    let mirrors: list<Mirror> = (if ($mirror | is-empty) { [] } else { mirrors-under $mirror })

    let found: list<Finding> = ($notes | each {|file|
        let text: string = (open --raw $file)
        let seen: Shape = (shape $text)
        let missing: list<string> = ($seen.cites | where {|c| not (rooted $c $home $projects | path exists) })
        let misquoted: list<string> = (misquotes $text $mirrors)
        findings ($file | path basename) $text $expected $max_lines $missing $misquoted
    } | flatten)
    let unlisted: list<Finding> = ($notes | where {|f| not ((($f | path parse | get stem)) in $listed) } | each {|f| {note: ($f | path basename), problem: 'a note the INDEX does not list'} })
    let pending: list<string> = ($listed | where {|id| not ($id in $stems) })
    let all: list<Finding> = ($found | append $unlisted)

    if $json {
        $all | to json -r | print
    } else {
        $all | each {|f| print $"✗ ($f.note): ($f.problem)" }
        print $"kb-check ($dir): ($notes | length) notes · ($all | length) findings · INDEX ($listed | length) ids, ($pending | length) pending"
        if not ($pending | is-empty) { print $"   pending: ($pending | str join ', ')" }
        if ($all | is-empty) { print '✓ every note keeps its law' }
    }
    if not ($all | is-empty) { exit 1 }
}
