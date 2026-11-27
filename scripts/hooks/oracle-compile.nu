#!/opt/homebrew/bin/nu
# oracle-compile.nu — U9's ORACLE: the compiler speaks right after a write.
#
# PostToolUse (advisory only — a hook of this class CANNOT block, the fork's
# law): after a .kt or .hs file lands, the oracle runs the language's own
# truth — the project's gradle compile for Kotlin, ghc -fno-code for
# Haskell — and speaks the errors the writer would otherwise meet only at
# deploy or CI time. The live receipt it exists for: a compile failure
# caught seconds after the write that caused it.
#
# LAWS:
#  · ADVISORY: exit 0 always; the errors ride as additionalContext, never a
#    refusal. The oracle measures, it never blocks (the plan's own wording).
#  · TIME-CAPPED: gradle ≤ 45 s, ghc ≤ 20 s; a cap is said, not hidden.
#  · COUNTED: every run lands one row in ~/.zcode/hooks/state/oracles.tsv —
#    spoke | clean | timeout | error — the oracle ledger beside denials.tsv.
#  · DEDUPED: the same file is judged at most once per COOLDOWN, so an
#    Edit-Write pair costs one compile, not two.
#  · CLASSIFY ONCE, DISPATCH BY TABLE: the extension picks the leg from a
#    record; the legs return verdict VALUES; main is the single voice.

use std/assert

const LEDGER: string = '/Users/lattenero/.zcode/hooks/state/oracles.tsv'
const GRADLE_CAP: duration = 45sec
const GHC_CAP: duration = 20sec
const COOLDOWN_SEC: int = 60
const ERROR_LINES: int = 6

# The extension → leg map (a record IS the table; '' means off duty).
const EXTENSIONS: record = {kt: 'kt', hs: 'hs'}

# The language an extension hands the oracle.
def file-kind [path: string]: nothing -> string {
    let ext: string = ($path | path parse | get extension | default '' | str lowercase)
    $EXTENSIONS | get -o $ext | default ''
}

# The gradle project root above a file (settings.gradle or .kts), else ''.
def gradle-root [path: string]: nothing -> string {
    mut dir: string = ($path | path dirname)
    # 12 levels: a Kotlin file in this fleet sits up to nine directories deep
    # (modules/<m>/src/main/kotlin/<pkg>/…), and the cap must never be the
    # reason an oracle goes quiet.
    for _ in 1..12 {
        if (($dir | path join 'settings.gradle.kts') | path exists) or (($dir | path join 'settings.gradle') | path exists) {
            return $dir
        }
        let parent: string = ($dir | path dirname)
        if $parent == $dir { break }
        $dir = $parent
    }
    ''
}

# The module task prefix for a file under modules/<name>/src: ':modules:daemon'.
# Anything outside that layout is the root project's own compileKotlin.
def module-of [path: string, root: string]: nothing -> string {
    let rest: string = ($path | str substring (($root | str length) + 1)..)
    let parts: list<string> = ($rest | split row '/' | where {|p| $p != '' })
    if (($parts | length) >= 2) and ($parts.0 == 'modules') { $':modules:($parts.1)' } else { '' }
}

# The Kotlin compiler's error lines from gradle output.
def error-lines [out: string]: nothing -> list<string> {
    $out | lines | where {|l| ($l | str trim | str starts-with 'e: ') } | first $ERROR_LINES
}

# The ghc error lines from stderr.
def ghc-lines [out: string]: nothing -> list<string> {
    $out | lines | where {|l| $l | str contains 'error:' } | first $ERROR_LINES
}

# One tsv row, clipped, NEWLINE-TERMINATED (save -a appends no newline —
# measured: unfused rows are the whole point of a tsv).
def ledger-row [hook: string, file: string, status: string, detail: string]: nothing -> nothing {
    mkdir ($LEDGER | path dirname)
    let clipped: string = ($detail | str replace -a "\n" ' ' | str substring 0..160)
    let row: string = ([$"(date now | format date '%Y-%m-%dT%H:%M:%S')", $hook, $"($file | path basename)", $status, $clipped]
        | str join "\t")
    $"($row)\n" | save -a $LEDGER
}

# The cooldown CHECK is read-only; the stamp is written by the caller AFTER
# a real judgment — a crashed leg must not consume the file's judgment.
def cooled? [file: string]: nothing -> bool {
    let stamp: string = ('/Users/lattenero/.zcode/hooks/state/oracle-last-' + ($file | hash md5))
    let now: int = (date now | format date '%s' | into int)
    let last: int = (try { open --raw $stamp | into int } catch { 0 })
    ($now - $last) >= $COOLDOWN_SEC
}

def stamp [file: string]: nothing -> nothing {
    let stamp: string = ('/Users/lattenero/.zcode/hooks/state/oracle-last-' + ($file | hash md5))
    try { date now | format date '%s' | save -f $stamp }
}

# The HASKELL leg: ghc -fno-code on the file, capped. A verdict VALUE.
def hs-leg [file: string]: nothing -> record {
    let started: datetime = (date now)
    let ghc: string = (if ('/Users/lattenero/.ghcup/bin/ghc' | path exists) { '/Users/lattenero/.ghcup/bin/ghc' } else { 'ghc' })
    let outdir: string = ('/tmp/ghc-oracle-' + ($file | hash md5))
    let run: record = (do { ^$ghc -fno-code -outputdir $outdir $file } | complete)
    if $run.exit_code == 0 { return {status: 'clean', detail: ''} }
    let errs: list<string> = (ghc-lines $run.stderr)
    if (($errs | is-empty) and (((date now) - $started) > $GHC_CAP)) {
        return {status: 'timeout', detail: 'ghc hit the 20 s cap'}
    }
    {status: 'spoke', detail: ($errs | default [$'ghc failed: ($run.exit_code)'] | str join ' ')}
}

# The KOTLIN leg: the project's own compiler, module-aware, capped.
def kt-leg [file: string]: nothing -> record {
    let started: datetime = (date now)
    let root: string = (gradle-root $file)
    if ($root | is-empty) { return {status: 'error', detail: 'no gradle project above the file'} }
    let mod: string = (module-of $file $root)
    let task: string = (if ($mod | is-empty) { 'compileKotlin' } else { ($mod + ':compileKotlin') })
    let run: record = (do {
        cd $root
        ^./gradlew -q --offline $task
    } | complete)
    if $run.exit_code == 0 { return {status: 'clean', detail: ''} }
    let errs: list<string> = (error-lines ($run.stdout + "\n" + $run.stderr))
    if (($errs | is-empty) and (((date now) - $started) > $GRADLE_CAP)) {
        return {status: 'timeout', detail: $"gradle hit the 45 s cap on ($task)"}
    }
    {status: 'spoke', detail: ($errs | default [$'gradle failed: ($run.exit_code) — ($task)'] | str join ' ')}
}

def main []: string -> nothing {
    let input: record = (try { $in | from json } catch { {} })
    let file: string = ($input.tool_input?.file_path? | default '')
    let kind: string = (if ($file | is-empty) { '' } else { file-kind $file })
    if ($kind | is-empty) { exit 0 }
    if not (cooled? $file) { exit 0 }

    let legs: record = {hs: {|f| hs-leg $f }, kt: {|f| kt-leg $f }}
    let verdict: record = (do ($legs | get $kind) $file)
    stamp $file
    ledger-row $"oracle-($kind)" $file $verdict.status $verdict.detail
    if $verdict.status == 'spoke' {
        {
            hookSpecificOutput: {
                hookEventName: 'PostToolUse'
                additionalContext: $"[oracle-($kind)] ($file | path basename) does not compile — fix before moving on:
($verdict.detail)"
            }
        } | to json -r | print
    }
    exit 0
}

# The hook's own laws, runnable: nu scripts/hooks/oracle-compile.nu --selftest
def selftest []: nothing -> nothing {
    assert equal (file-kind 'a/B.kt') 'kt'
    assert equal (file-kind 'a/B.hs') 'hs'
    assert equal (file-kind 'a/B.kts') ''
    assert equal (file-kind 'a/B.ts') ''
    assert equal (gradle-root '/tmp/nowhere/x.kt') ''
    assert equal (module-of '/r/modules/daemon/src/main/kotlin/A.kt' '/r') ':modules:daemon'
    assert equal (module-of '/r/app/src/A.kt' '/r') ''
    let errs: list<string> = (error-lines "e: a.kt:1:1 x
w: warn
e: b.kt:2:2 y
plain")
    assert equal ($errs | length) 2
    assert equal ($errs.0) 'e: a.kt:1:1 x'
    let gerrs: list<string> = (ghc-lines "a.hs:3:1 error: [GHC-87087] x
a.hs:1:1 warning: [GHC-0000] w")
    assert equal ($gerrs | length) 1
    print 'oracle-compile selftest: every law holds'
}
