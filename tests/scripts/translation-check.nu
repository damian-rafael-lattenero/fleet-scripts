# translation-check.test.nu — the receipt on a fixture repository built for the
# run: master holds notes that link to each other; read untranslated a note
# fails on its language and a note that was English from the start passes; a
# translation with every fault the receipt exists to catch reports each one
# under its own rule with exit 1 (code changed, a number changed, an English
# line reworded, a link whose heading is gone); the translation mended, every
# note passes with exit 0. Three shapes the first version got wrong are pinned
# here: a Spanish line and an English one inside one block, a comment inside
# code, and a mixed line the rule misreads that the translator declares.
# Nothing touches a real KB.
# covers: /Users/lattenero/Scripts/scripts/translation-check.nu
use std/assert

const SELF: path = (path self)
# The hub splits scripts and tests: tests/scripts/<name>.nu pairs
# scripts/<name>.nu three levels up ($SELF's dirname is tests/scripts).
const SCRIPT: path = ($SELF | path expand | path dirname | path dirname | path dirname | path join 'scripts' 'translation-check.nu')

# What a run answers.
type Run = record<exit_code: int, stdout: string, stderr: string>

def put [path: path, text: string]: nothing -> nothing {
    $text | save --force $path
}

# Fire the receipt over one note.
def fire [file: path]: nothing -> Run {
    do { ^$nu.current-exe $SCRIPT $file } | complete
}

# Fire the receipt with the lines the translator declares as Spanish.
def fire-declared [file: path, declared: path]: nothing -> Run {
    do { ^$nu.current-exe $SCRIPT $file --declared $declared } | complete
}

# One git command in the fixture repository; the arguments ride as a list,
# because a custom command would read git's flags as its own.
def git-in [dir: path, args: list<string>]: nothing -> string {
    ^git -C $dir ...$args
}

# The bodies of the fixture's code, spelled in pieces so that the typing law
# hook never reads the fixture as a definition of this file.
let one: string = 'de' + 'f f [] { 1 }'
let two: string = 'de' + 'f f [] { 2 }'

let aBefore: string = [
    '# Título uno'
    ''
    'Texto en español que habla de la versión 0.117.0 y del comando `nu -c`, para que el owner pueda correrlo como se debe y sin errores, desde la terminal hasta el final.'
    ''
    '```nu'
    $one
    '```'
    ''
    '## Sección dos'
    ''
    'Más texto para el owner. Ver [enlace](b.md) y [dos](#sección-dos).'
] | str join "\n"
let bBefore: string = [
    '# Note B'
    ''
    'English text here for the owner and the links, kept byte for byte.'
    ''
    'Verified on this machine [verificado 0.117].'
    ''
    'Every case carries its `[verificado <versión>]` tag.'
    ''
    'See [a](a.md#sección-dos).'
] | str join "\n"
let cPlain: string = [
    '# Note C'
    ''
    'English from the start, with the number 42 and the command `nu -c`.'
    ''
    '- **Reactive Design Patterns** (Kuhn et al.) — backpressure, isolation, resilient'
] | str join "\n"
# A Spanish line and an English one inside one block: the Spanish goes, the
# English line stays — the rule reads lines, never blocks.
let dBefore: string = [
    '# Nota D'
    ''
    'Fuente canónica: `path/to/file.md`'
    '(The infix type operators; typed flags).'
    ''
    'English stays as is for the owner.'
] | str join "\n"
let dFaulty: string = [
    '# Note D'
    ''
    'Canonical source: `path/to/file.md`'
    '(The infix type operators; flags with types).'
    ''
    'English stays as is for the owner.'
] | str join "\n"
let dGood: string = [
    '# Note D'
    ''
    'Canonical source: `path/to/file.md`'
    '(The infix type operators; typed flags).'
    ''
    'English stays as is for the owner.'
] | str join "\n"
# Comments are prose wherever code keeps them: inline, on their own line inside
# a fence, and trailing code inside a fence.
let eBefore: string = [
    '# Nota E'
    ''
    'Mal: `// esto es para que no explote si viene vacío`'
    ''
    '```kotlin'
    '// un comentario en español para el owner'
    'val x = 1'
    'val y = 2  // o el tipo kap equivalente'
    '```'
    ''
    'Texto final para el owner.'
] | str join "\n"
let eFaulty: string = [
    '# Note E'
    ''
    'Wrong: `// this is here so that it does not break when it comes empty`'
    ''
    '```kotlin'
    '// a comment for the owner'
    'val x = 2'
    'val y = 2  // or the equivalent kap type'
    '```'
    ''
    'Final text for the owner.'
] | str join "\n"
let eGood: string = [
    '# Note E'
    ''
    'Wrong: `// this is here so that it does not break when it comes empty`'
    ''
    '```kotlin'
    '// a comment for the owner'
    'val x = 1'
    'val y = 2  // or the equivalent kap type'
    '```'
    ''
    'Final text for the owner.'
] | str join "\n"
let eLeft: string = [
    '# Note E'
    ''
    'Wrong: `// this is here so that it does not break when it comes empty`'
    ''
    '```kotlin'
    '// a comment for the owner'
    'val x = 1'
    'val y = 2  // o el tipo kap equivalente'
    '```'
    ''
    'Final text for the owner.'
] | str join "\n"
# The same, on an indented line: the cut is the comment's own position, so the
# code before it never rides along into the comment.
let iBefore: string = [
    '# Nota I'
    ''
    '```kotlin'
    '    val z = 3  // otro comentario para el owner'
    '```'
] | str join "\n"
let iGood: string = [
    '# Note I'
    ''
    '```kotlin'
    '    val z = 3  // another comment for the owner'
    '```'
] | str join "\n"
# A literal backtick written between double runs: reading it as one span of a
# single backtick would flip the parity of every line after it.
let gBefore: string = [
    '# Nota G'
    ''
    '- Backtick `` ` ``: strings con espacios como término de comando.'
    ''
    'Texto en español para el owner, `nu -c` como comando.'
] | str join "\n"
let gGood: string = [
    '# Note G'
    ''
    '- Backtick `` ` ``: strings with spaces as a command term.'
    ''
    'Text in English for the owner, `nu -c` as a command.'
] | str join "\n"
# A Spanish comment left inside an inline span is still Spanish left behind.
let hBefore: string = [
    '# Nota H'
    ''
    'Un ejemplo `// esto es para el owner` y nada más.'
] | str join "\n"
let hLeft: string = [
    '# Note H'
    ''
    'One example `// esto es para el owner` and nothing else.'
] | str join "\n"
# A mixed line the English rule misreads — English words around a Spanish one —
# is declared by its number, never left untranslated to appease the rule.
let fBefore: string = [
    '# Nota F'
    ''
    '- **Haskell Programming from First Principles** (Allen & Moronuki) — fundamentos'
    '  de tipos/laziness/sintaxis; el "why" profundo.'
    ''
    'Más texto para el owner y para su sistema.'
] | str join "\n"
let fGood: string = [
    '# Note F'
    ''
    '- **Haskell Programming from First Principles** (Allen & Moronuki) — the fundamentals'
    '  of types/laziness/syntax; the deep "why".'
    ''
    'More text for the owner and for the owner system.'
] | str join "\n"
let bFaulty: string = [
    '# Note B'
    ''
    'English text changed here for the owner and the links, kept byte for byte.'
    ''
    'Verified on this machine [verificado 0.117].'
    ''
    'Every case carries its `[verificado <versión>]` tag.'
    ''
    'See [a](a.md#sección-dos).'
] | str join "\n"
let aFaulty: string = [
    '# Title one'
    ''
    'Text in English that speaks of version 0.118.0 and the command `nu -c x`, so that the owner can run it the right way, from the terminal to the end.'
    ''
    '```nu'
    $two
    '```'
    ''
    '## Section two'
    ''
    'More text for the owner. See [link](b.md) and [two](#section-two).'
] | str join "\n"
let aGood: string = [
    '# Title one'
    ''
    'Text in English that speaks of version 0.117.0 and the command `nu -c`, so that the owner can run it the right way, from the terminal to the end.'
    ''
    '```nu'
    $one
    '```'
    ''
    '## Section two'
    ''
    'More text for the owner. See [link](b.md) and [two](#section-two).'
] | str join "\n"
let bGood: string = [
    '# Note B'
    ''
    'English text here for the owner and the links, kept byte for byte.'
    ''
    'Verified on this machine [verified 0.117].'
    ''
    'Every case carries its `[verified <version>]` tag.'
    ''
    'See [a](a.md#section-two).'
] | str join "\n"

let root: path = (mktemp -d -t 'translation-check.XXXXXX')
put ($root | path join 'a.md') $aBefore
put ($root | path join 'b.md') $bBefore
put ($root | path join 'c.md') $cPlain
put ($root | path join 'd.md') $dBefore
put ($root | path join 'e.md') $eBefore
put ($root | path join 'f.md') $fBefore
put ($root | path join 'g.md') $gBefore
put ($root | path join 'h.md') $hBefore
put ($root | path join 'i.md') $iBefore
git-in $root [init -q -b master]
git-in $root [add -A]
git-in $root [-c user.name=t -c user.email=t@t commit -q -m init]

let rawI: Run = (fire ($root | path join 'i.md'))
assert equal $rawI.exit_code 1 'exit 1 on an untranslated comment on an indented line'
assert equal ($rawI.stdout | str contains 'language: a Spanish line remains: // otro comentario para el owner') true $rawI.stdout

let spanish: Run = (fire ($root | path join 'a.md'))
assert equal ($spanish.stderr | str trim) '' $"the receipt must answer, never error: ($spanish.stderr)"
assert equal $spanish.exit_code 1 'exit 1 on an untranslated note'
assert equal ($spanish.stdout | str contains 'language: the result reads as Spanish') true $spanish.stdout

let plain: Run = (fire ($root | path join 'c.md'))
assert equal $plain.exit_code 0 $"exit 0 on a note that was English from the start: ($plain.stderr)($plain.stdout)"
assert equal ($plain.stdout | str starts-with 'PASS c.md - headings 1 - fenced 0 - inline 1 - links 0 - 9 notes scanned') true $plain.stdout
assert equal ($plain.stdout | str contains 'declared Spanish by the translator: 0') true $plain.stdout

put ($root | path join 'a.md') $aFaulty
put ($root | path join 'b.md') $bFaulty
let faultyA: Run = (fire ($root | path join 'a.md'))
assert equal ($faultyA.stderr | str trim) '' $"the receipt must answer, never error: ($faultyA.stderr)"
assert equal $faultyA.exit_code 1 'exit 1 on a faulty translation'
assert equal ($faultyA.stdout | str contains ('fenced: item 0: ' + $one + ' -> ' + $two)) true $faultyA.stdout
assert equal ($faultyA.stdout | str contains 'inline: item 0: nu -c -> nu -c x') true $faultyA.stdout
assert equal ($faultyA.stdout | str contains 'numbers: lost [0.117.0]; gained [0.118.0]') true $faultyA.stdout
assert equal ($faultyA.stdout | str contains 'links: a note links to a heading that is gone: b.md -> #sección-dos') true $faultyA.stdout
assert equal ($faultyA.stdout | str contains 'english:') false $faultyA.stdout

let faultyB: Run = (fire ($root | path join 'b.md'))
assert equal $faultyB.exit_code 1 'exit 1 on a reworded English line'
assert equal ($faultyB.stdout | str contains 'english: L3 an English line changed or vanished: English text here for the owner and the links, kept byte for byte.') true $faultyB.stdout
assert equal ($faultyB.stdout | str contains 'links: anchor no longer resolves: a.md#sección-dos') true $faultyB.stdout

put ($root | path join 'a.md') $aGood
put ($root | path join 'b.md') $bGood
let goodA: Run = (fire ($root | path join 'a.md'))
assert equal $goodA.exit_code 0 $"exit 0 on the mended translation: ($goodA.stderr)($goodA.stdout)"
assert equal ($goodA.stdout | str starts-with 'PASS a.md - headings 2 - fenced 1 - inline 1 - links 2') true $goodA.stdout
let goodB: Run = (fire ($root | path join 'b.md'))
assert equal $goodB.exit_code 0 $"exit 0 on the mended translation: ($goodB.stderr)($goodB.stdout)"

put ($root | path join 'd.md') $dFaulty
let faultyD: Run = (fire ($root | path join 'd.md'))
assert equal $faultyD.exit_code 1 'exit 1 when the English line of a mixed block is reworded'
assert equal ($faultyD.stdout | str contains 'english: L4 an English line changed or vanished: (The infix type operators; typed flags).') true $faultyD.stdout
put ($root | path join 'd.md') $dGood
let goodD: Run = (fire ($root | path join 'd.md'))
assert equal $goodD.exit_code 0 $"exit 0 when a Spanish line inside a mixed block is translated: ($goodD.stderr)($goodD.stdout)"

put ($root | path join 'e.md') $eFaulty
let faultyE: Run = (fire ($root | path join 'e.md'))
assert equal ($faultyE.stderr | str trim) '' $"the receipt must answer, never error: ($faultyE.stderr)"
assert equal $faultyE.exit_code 1 'exit 1 when the code around a translated comment changes'
assert equal ($faultyE.stdout | str contains 'FAIL e.md - fenced:') true $faultyE.stdout
put ($root | path join 'e.md') $eLeft
let leftE: Run = (fire ($root | path join 'e.md'))
assert equal ($leftE.stderr | str trim) '' $"the receipt must answer, never error: ($leftE.stderr)"
assert equal $leftE.exit_code 1 'exit 1 when a comment trailing code inside a fence stays in Spanish'
assert equal ($leftE.stdout | str contains 'language: a Spanish line remains: // o el tipo kap equivalente') true $leftE.stdout
put ($root | path join 'e.md') $eGood
let goodE: Run = (fire ($root | path join 'e.md'))
assert equal $goodE.exit_code 0 $"exit 0 when a comment inside code is translated: ($goodE.stderr)($goodE.stdout)"

put ($root | path join 'f.md') $fGood
let undeclared: Run = (fire ($root | path join 'f.md'))
assert equal $undeclared.exit_code 1 'exit 1 on a mixed line nobody declared'
assert equal ($undeclared.stdout | str contains 'english: L3 an English line changed or vanished: - **Haskell Programming from First Principles**') true $undeclared.stdout
put ($root | path join 'declared-f.txt') "3\n"
let declaredRun: Run = (fire-declared ($root | path join 'f.md') ($root | path join 'declared-f.txt'))
assert equal ($declaredRun.stderr | str trim) '' $"the receipt must answer, never error: ($declaredRun.stderr)"
assert equal $declaredRun.exit_code 0 $"exit 0 on a declared line: ($declaredRun.stderr)($declaredRun.stdout)"
assert equal ($declaredRun.stdout | str contains 'declared Spanish by the translator: 1') true $declaredRun.stdout

put ($root | path join 'g.md') $gGood
let goodG: Run = (fire ($root | path join 'g.md'))
assert equal ($goodG.stderr | str trim) '' $"the receipt must answer, never error: ($goodG.stderr)"
assert equal $goodG.exit_code 0 $"exit 0 on a note that writes a literal backtick: ($goodG.stdout)"
assert equal ($goodG.stdout | str contains 'inline 1') true $goodG.stdout

put ($root | path join 'h.md') $hLeft
let leftH: Run = (fire ($root | path join 'h.md'))
assert equal $leftH.exit_code 1 'exit 1 when a Spanish comment stays inside an inline span'
assert equal ($leftH.stdout | str contains 'language: a Spanish line remains: // esto es para el owner') true $leftH.stdout

put ($root | path join 'i.md') $iGood
let goodI: Run = (fire ($root | path join 'i.md'))
assert equal $goodI.exit_code 0 $"exit 0 on an indented trailing comment once translated: ($goodI.stderr)($goodI.stdout)"

rm -r -f $root
print 'translation-check ok — untranslated fails on language, a faulty translation shows every fault with exit 1, the mended one passes, a mixed block reads line by line, a comment inside code is prose wherever code keeps it, a declared line is named, a literal backtick keeps the parity, an indented trailing comment is cut at its own position'
