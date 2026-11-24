# audit-fp.nu core — the U0 mechanical inventory of the FP/concurrency audit,
# pure: rg output lines in, tagged rows out, plus the markdown the report
# prints. The four categories and their patterns are DATA (one row each), so a
# new category is a new row, never a new branch.
#
# Every hit is a SUSPECT for the U1 semantic review, not a verdict.

export type Hit = record<category: string, file: string, line: int, text: string>
export type Category = record<name: string, pattern: string>

export const CATEGORIES: list<Category> = [
    {
        name: 'forbidden'
        pattern: 'while\s*\((true|1)\)|\bdo\s*\{|Thread\.sleep|runBlocking|GlobalScope|\bThread\('
    }
    {
        name: 'handrolled'
        pattern: 'synchronized\s*\(|@Volatile|AtomicLong|AtomicInteger|AtomicBoolean|AtomicReference|ReentrantLock|java\.util\.concurrent'
    }
    {
        name: 'impure'
        pattern: 'System\.currentTimeMillis|System\.nanoTime|Instant\.now\(|LocalDateTime\.now|LocalDate\.now|java\.time\.Clock|Random\(|java\.io\.[A-Z]|FileWriter|FileInputStream|FileOutputStream'
    }
    {
        name: 'errors'
        pattern: 'catch\s*\(\s*\w+\s*:\s*\w*Exception|!!|\bthrow\b'
    }
]

# rg matches `-g` globs against the path AS GIVEN; with an absolute search
# root a bare `modules/*/src/main/**` never matches (measured 24/11: 0 hits
# where the same tree had 16). Anchor it with `**/` unless the caller gave an
# absolute glob or already anchored it.
export def rg-glob [glob: string]: nothing -> string {
    if ($glob | str starts-with '/') or ($glob | str starts-with '**') {
        $glob
    } else {
        '**/' + $glob
    }
}

# rg -n --no-heading colourises nothing, but git-style paths can carry a drive
# prefix; the split is on ':' with the first two fields fixed (path, line).
export def parse-hits [stdout: string, category: string, repo: string]: nothing -> list<Hit> {
    $stdout
    | lines
    | where {|l| ($l | str trim | is-not-empty)}
    | each {|l|
        let parts: list<string> = ($l | split row ':')
        let line: int = (($parts | get 1) | into int)
        {
            category: $category
            file: (($parts | first) | str replace ($repo + '/') '')
            line: $line
            text: (($parts | skip 2) | str join ':' | str trim | str substring 0..170)
        }
    }
}

# The markdown body of one category: a count line, then the table (or none).
export def category-report [rows: list<Hit>, category: string]: nothing -> list<string> {
    let mine: list<Hit> = ($rows | where category == $category)
    let head: list<string> = [$"## ($category)" '']
    if ($mine | is-empty) {
        $head | append '(none)'
    } else {
        let table: list<string> = (
            ['| file | line | text |' '|---|---|---|']
            | append ($mine | each {|r| $"| `($r.file)` | ($r.line) | `($r.text | str replace '|' '\|')` |"})
        )
        $head | append $table
    }
}

export def counts-line [rows: list<Hit>, category: string]: nothing -> string {
    let n: int = (($rows | where category == $category) | length)
    ('- **' + $category + '**: ' + ($n | into string))
}
