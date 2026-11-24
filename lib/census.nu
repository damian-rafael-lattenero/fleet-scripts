# census.nu core — the owner's law (24/11) as data: every operational .nu on
# this machine has a test. A test claims its scripts two ways:
#   - `# covers: <absolute glob>` (explicit, any scope, any family size), or
#   - by NAME: a `<name>.nu` inside a tests/ directory of the SAME root — the
#     mirror convention, which for the hub means scripts/brain.nu and
#     lib/brain.nu are both proven by tests/lib/brain.nu.
# Exemptions are PATTERNS — generated (venv), archived, vendored, our own fp
# subtree (which has its own gate) — never a list of files: a new archive or a
# new venv is covered the day it appears.

export const EXEMPT: list<string> = [
    '/venv/'
    '/archive/'
    '/build/'
    '/node_modules/'
    '/.git/'
    '/.worktrees/'
    '/nushell-fp/'
    '/official/'
    '/.nu-orphans-archive/'
    '/disabled-graveyard/'
]

export def exempt? [path: string]: nothing -> bool {
    ($EXEMPT | any {|pattern| $path | str contains $pattern})
}

# Every `# covers: <glob>` a test file declares (one per line, any number).
export def declared-covers [test_file: string]: nothing -> list<string> {
    open --raw $test_file
    | lines
    | where {|l| $l =~ '^# covers: '}
    | each {|l| $l | str replace --regex '^# covers: ' '' | str trim}
}

export def expanded-covers [test_file: string]: nothing -> list<string> {
    declared-covers $test_file | each {|g| glob $g } | flatten | path expand | uniq
}

# The machine's map: one line per place where scripts live. Adding a repo adds
# its root — never a file. The hub itself is last on purpose (its own gate
# runs first in test.nu).
export const ROOTS: list<string> = [
    '/Users/lattenero/Scripts'
    '/Users/lattenero/Projects/agent-brain'
    '/Users/lattenero/Projects/zcode-bot-kotlin'
    '/Users/lattenero/Projects/ZCode'
    '/Users/lattenero/Projects/whatsdigest-kt'
    '/Users/lattenero/Projects/kap'
    '/Users/lattenero/Projects/cv'
    '/Users/lattenero/Projects/nushell-kb'
    '/Users/lattenero/Projects/bot'
    '/Users/lattenero/Projects/pg-base'
    '/Users/lattenero/.zcode/hooks'
    '/Users/lattenero/.agents'
]

export def scripts-under [roots: list<string>]: nothing -> list<string> {
    $roots
    | each {|r| glob ($r | path join '**' '*.nu') }
    | flatten
    | where {|f| not (exempt? $f)}
    | path expand
    | sort
    | uniq
}

# Test files are the .nu of a tests/ directory under any root (any depth); the
# hub's own tests/ is reached by the same glob.
export def tests-under [roots: list<string>]: nothing -> list<string> {
    $roots
    | each {|r| glob ($r | path join '**' '*.nu') }
    | flatten
    | where {|f| ($f | path expand) =~ '/tests/'}
    | path expand
    | sort
    | uniq
}

# The owning root of a path: the LONGEST root that prefixes it, so a nested
# repo never borrows the outer one. TOTAL: a path outside every root falls
# back to its own directory, where the classic `<dir>/tests/<name>.nu` mirror
# still claims it.
export def root-of [path: string, roots: list<string>]: nothing -> string {
    let hits: list<string> = ($roots | where {|r| $path | str starts-with $r})
    let best: any = ($hits | sort-by {|r| $r | str length} | last)
    $best | default ($path | path dirname)
}

# Name-based coverage: a test with the same basename inside the same root.
export def name-matches [script: string, test_files: list<string>, roots: list<string>]: nothing -> list<string> {
    let name: string = ($script | path basename)
    let root: string = (root-of $script $roots)
    $test_files | where {|t| (($t | path basename) == $name) and ($t | str starts-with $root)}
}

# A script is covered when a `# covers:` glob matched IT, or when a test with
# its name exists in the same root. The answer is the covered SCRIPTS (that is
# what the census asks about), never the tests.
export def covered-set [scripts: list<string>, test_files: list<string>, roots: list<string>]: nothing -> list<string> {
    let declared: list<string> = ($test_files | each {|t| expanded-covers $t } | flatten | path expand | uniq)
    let by_decl: list<string> = ($scripts | where {|s| $s in $declared})
    let by_name: list<string> = ($scripts | where {|s| not ((name-matches $s $test_files $roots) | is-empty)})
    (($by_decl | append $by_name) | path expand | uniq)
}

export def uncovered [scripts: list<string>, covered: list<string>]: nothing -> list<string> {
    let cov: list<string> = ($covered | path expand | uniq)
    $scripts | where {|s| not ($s in $cov)}
}
