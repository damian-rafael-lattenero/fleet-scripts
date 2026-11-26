# lang-ok: test fixtures (the asserted strings are Spanish on purpose)
# langcheck.nu — the gate end to end on a fixture tree built for the run: a
# clean file passes, an accented file and an unaccented Spanish pair are found,
# a Spanish basename is a name finding, a pragma and an allowlisted prefix are
# skipped with their reason, and the exit flips 1 -> 0 when the fixture is
# cleaned. Nothing touches a real repo.
use std/assert

const SELF: path = (path self)
const SCRIPT: path = ($SELF | path expand | path dirname | path dirname | path dirname | path join 'scripts' 'langcheck.nu')

type Run = record<exit_code: int, stdout: string, stderr: string>

def put [path: path, text: string]: nothing -> nothing {
    mkdir ($path | path dirname)
    $text | save --force $path
}

def fire [root: path, allow: path, mode: string]: nothing -> Run {
    do { ^$nu.current-exe $SCRIPT $root --allow $allow --json --mode $mode } | complete
}

let root: path = (mktemp -d -t 'langcheck.XXXXXX')
let allow: path = ($root | path join 'allow.tsv')
put ($root | path join 'clean.md') 'A pure function denotes a value.\n'
put ($root | path join 'spanish.md') 'por que chat_timeout_s no funcionaba y quien cortaba antes\n'
put ($root | path join 'accented.md') 'qué es una mónada y para qué sirve\n'
put ($root | path join 'notes.txt') 'see paragraph para. 3 of the paper\n'
put ($root | path join 'code.nu') '# este archivo devuelve la lista\nlet total: int = 1\n'
put ($root | path join 'data.json') '{"mensaje": "hola"}\n'
put ($root | path join 'hoja-de-ruta.md') 'clean text\n'
put ($root | path join 'quoted.md') '<!-- lang-ok: verbatim quote -->\nqué es una mónada\n'
put ($root | path join 'allowed' 'keep.md') 'por que no funciona el correo\n'
put $allow $"# path<TAB>reason\n($root | path join 'allowed')\tfixture: allowlisted prefix\n"

let out: Run = (fire $root $allow 'all')
assert equal ($out.stderr | str trim) '' $"the gate must answer, never error: ($out.stderr)"
assert equal $out.exit_code 1 'exit 1 on findings'
let found: list<string> = ($out.stdout | from json | select path kind | each {|f| $"($f.path | path basename): ($f.kind)" } | sort)
assert equal $found [
    'accented.md: accent'
    'code.nu: words'
    'data.json: words'
    'hoja-de-ruta.md: name'
    'spanish.md: words'
]

let named: Run = (fire $root $allow 'names')
assert equal $named.exit_code 1 'names mode still fails'
assert equal ($named.stdout | from json | get path | each {|p| $p | path basename }) ['hoja-de-ruta.md']

let content: Run = (fire $root $allow 'files')
assert equal $content.exit_code 1 'files mode still fails'
assert equal ($content.stdout | from json | get kind | uniq | sort) ['accent' 'words']

put ($root | path join '.worktrees' 'fake' 'repo' 'es.md') 'por que no funciona el correo\n'
let outside: Run = (do { ^$nu.current-exe $SCRIPT $root --allow $allow --json --mode all } | complete)
assert equal ($outside.stdout | from json | get -o path | default [] | any {|p| $p | str contains '.worktrees' }) false 'a worktree is skipped by default'
let inside: Run = (do { ^$nu.current-exe $SCRIPT $root --allow $allow --json --mode all --include-worktrees } | complete)
assert equal ($inside.stdout | from json | get -o path | default [] | any {|p| $p | str contains '.worktrees' }) true '--include-worktrees scans the branch'

rm ($root | path join 'spanish.md')
rm ($root | path join 'accented.md')
rm ($root | path join 'code.nu')
rm ($root | path join 'data.json')
rm ($root | path join 'hoja-de-ruta.md')
let clean: Run = (fire $root $allow 'all')
assert equal ($clean.stderr | str trim) '' $"clean run must answer: ($clean.stderr)"
assert equal $clean.exit_code 0 $"exit 0 when the tree is English: ($clean.stdout)"
assert equal ($clean.stdout | from json) []

rm -r -f $root
print 'scripts/langcheck ok — 5 findings with exit 1, names/files modes, pragma and allowlist skipped, exit 0 when clean'
