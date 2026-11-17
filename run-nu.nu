#!/usr/bin/env nu
# run-nu.nu — the SHARED compile gate + brain-suggest runner.
#
# One source of truth for humans (the zsh run-nu delegates here) and for
# ZCode agents (call it directly, or with --json for machine-readable
# output). Everything happens BEFORE execution when possible:
#
#   1. PARSE gate  — nu-check read BY VALUE (the process exits 0 while
#                    returning false — measured); parse traps die here.
#   2. LINT        — static rules over the source, ALL findings
#                    accumulated (never one-at-a-time):
#                      self-truncate   open X | ... | save -f X (literal X)      ERROR (data loss, measured)
#                      self-overwrite  open X | ... | save -f X same line, ANY token incl. $var — ERROR (the gate-invisible variant, audit 17/11)
#                      path-type-bug   `path type` compared to ""                WARN  (0.117 type error, measured on retire-python)
#                      midword-$       bare token like gui/$uid    WARN  (no interpolation mid-word)
#                      quoted-tilde    '~/path' strings            WARN  (no expansion inside strings; print labels exempt)
#                      blind-sleep     sleep >= 10sec              WARN  (the reactive law)
#   3. RUN         — unless blocked or --no-run; timed, stderr captured.
#   4. SUGGEST     — brain RAG (hybrid retrieval) for the fatal error and
#                    up to two lint findings; the curated KB surfaces the
#                    fix pattern. Silence when the brain is down.
#   5. RENDER      — human report on stderr, or --json on stdout (for
#                    agents); --keep retains the temp script.
#
# Usage:
#   nu ~/Scripts/run-nu.nu [file.nu] [--json] [--no-run] [--keep]
#   run-nu <<'NU' ... NU            (zsh delegate: heredoc via stdin)
#   cat script.nu | nu ~/Scripts/run-nu.nu
#
# Deliberately dependency-free (pure nu): this is infrastructure — it must
# run even if nushell-fp moves. Exit code: the script's own, or 1 on gate.

const BRAIN: path = '/Users/lattenero/Projects/agent-brain/core/build/install/agent-brain/bin/agent-brain'

# ── lint rules ───────────────────────────────────────────────────────────
# Every rule sees the source lines and ACCUMULATES its findings; findings
# never block inspection of later rules (the accumulation law).

def lint-lines [src: string]: nothing -> list<record<line: int, kind: string, severity: string, msg: string, hint: string>> {
    let lines: list<string> = ($src | lines)
    let findings: list<record<line: int, kind: string, severity: string, msg: string, hint: string>> = ([])

    # strip obvious comment lines once (comment $vars are not code)
    let codeLines: list<record<line: int, text: string>> = ($lines
        | enumerate
        | each {|row| {line: ($row.index + 1), text: $row.item}}
        | where {|row| not ($row.text | str trim | str starts-with '#')})

    # rule: self-truncate — open X ... save -f X truncates before the lazy
    # read finishes (measured 15/11: a whole file was lost this way)
    let opened: list<record<line: int, path: string>> = ($codeLines
        | each {|row| {line: $row.line, m: ($row.text | parse --regex 'open\s+(?:--raw\s+)?[{(]?([\w./~-]+)')} }
        | where {|r| not ($r.m | is-empty)}
        | each {|r| {line: $r.line, path: ($r.m | first).capture0}})
    let saved: list<record<line: int, path: string>> = ($codeLines
        | each {|row| {line: $row.line, m: ($row.text | parse --regex 'save\s+(?:-f\s+)?([\w./~-]+)')} }
        | where {|r| not ($r.m | is-empty)}
        | each {|r| {line: $r.line, path: ($r.m | first).capture0}})
    let truncates: list<record> = ($saved | where {|s| ($opened | where {|o| $o.path == $s.path} | length) > 0})
    # post-filters: flags captured as paths (--raw) are not paths; only
    # slash-bearing or tilde-prefixed captures count
    let opened2: list<record<line: int, path: string>> = ($opened | where {|o| (not ($o.path | str starts-with '-')) and (($o.path | str contains '/') or ($o.path | str starts-with '~'))})
    let saved2: list<record<line: int, path: string>> = ($saved | where {|o| (not ($o.path | str starts-with '-')) and (($o.path | str contains '/') or ($o.path | str starts-with '~'))})
    let truncates2: list<record> = ($saved2 | where {|s| ($opened2 | where {|o| $o.path == $s.path} | length) > 0})
    let f1: list<record<line: int, kind: string, severity: string, msg: string, hint: string>> = ($truncates2 | each {|t|
        {line: $t.line, kind: "self-truncate", severity: "ERROR",
         msg: $"save -f overwrites '($t.path)' which this script also opens",
         hint: "save truncates before the lazy open read completes — write to a temp path then move"}})

    # rule: midword-$ — a bare token with $ INSIDE (gui/$uid) is literal
    # text; interpolation only happens inside $"..." strings
    let f2: list<record<line: int, kind: string, severity: string, msg: string, hint: string>> = ($codeLines
        | where {|row| not ($row.text | str contains '$"')}
        | each {|row|
            let hits: list<string> = ($row.text | parse --regex '([\w./=-]+\$[a-zA-Z_][\w]*)' | each {|p| $p.capture0})
            {line: $row.line, hits: $hits}
        }
        | where {|r| not ($r.hits | is-empty)}
        # spreads (...$args) are syntax, not literal-text bugs
        | each {|r| {line: $r.line, hits: ($r.hits | where {|h| ($h | parse --regex '^\.{3}\$' | is-empty)})}}
        | where {|r| not ($r.hits | is-empty)}
        | each {|r|
            {line: $r.line, kind: "midword-$", severity: "WARN",
             msg: $"bare token contains $ but is LITERAL: ($r.hits | str join ', ')",
             hint: "variables do not interpolate mid-word — build the string with $\"...\" interpolation"}})

    # rule: quoted-tilde — '~...' never expands inside quotes. Print LABELS
    # are exempt: a literal tilde in human-readable output is documentation,
    # not a path (measured on the bot deploy scripts; audit 17/11 noted the
    # exemption missed mid-line prints — contains, not starts-with).
    let f3: list<record<line: int, kind: string, severity: string, msg: string, hint: string>> = ($codeLines
        | where {|row| ($row.text | parse --regex "'([^']*~[^']*)'" | length) > 0}
        | where {|row| not ($row.text | str trim | str contains 'print')}
        | each {|row|
            {line: $row.line, kind: "quoted-tilde", severity: "WARN",
             msg: "single-quoted string contains ~ — it will NOT expand",
             hint: "expand first (path expand / $env.HOME join) or drop the quotes"}})

    # rule: blind-sleep — sleeps >= 10sec violate the reactive law
    let f4: list<record<line: int, kind: string, severity: string, msg: string, hint: string>> = ($codeLines
        | each {|row|
            {line: $row.line, secs: ($row.text | parse --regex 'sleep\s+([\d.]+)\s*sec' | each {|p| $p.capture0 | into float})}
        }
        | where {|r| ($r.secs | length) > 0 and (($r.secs | first) >= 10)}
        | each {|r|
            {line: $r.line, kind: "blind-sleep", severity: "WARN",
             msg: $"sleep of (($r.secs | first))sec — a blind long wait",
             hint: "reactive law: job send/recv with --timeout, watch, or an event — never blind sleep"}})

    # rule: self-overwrite — open X | ... | save -f X in the SAME pipeline line
    # where X is ANY token (literal path OR $var): save -f truncates before the
    # lazy open read completes (measured data loss 15/11); the $var variant
    # ducked under the literal-only self-truncate rule (audit 17/11: the
    # "gate-invisible variant").
    let f5: list<record<line: int, kind: string, severity: string, msg: string, hint: string>> = ($codeLines
        | each {|row|
            let opens: list<string> = ($row.text | parse --regex 'open\s+(?:--raw\s+)?(\$?[\w./~-]+)' | each {|p| $p.capture0 })
            let saves: list<string> = ($row.text | parse --regex 'save\s+(?:--raw\s+)?(?:-f\s+)?(\$?[\w./~-]+)' | each {|p| $p.capture0 })
            let overlap: list<string> = ($opens | where {|o| $o in $saves})
            if ($overlap | is-empty) {
                null
            } else {
                {line: $row.line, kind: "self-overwrite", severity: "ERROR",
                 msg: $"same pipeline opens and saves \(save -f) '($overlap | str join ", ")' — non-atomic self-overwrite",
                 hint: "write to a temp file then mv — save -f truncates before the lazy open read completes (measured data loss)"}
            }
        }
        | where {|f| $f != null})

    # rule: path-type-bug — `path type` compared against an empty string: it
    # returns null or a type name, never "" (on 0.117 the comparison is a
    # type-mismatch error — measured on the bot's retire-python).
    let f6: list<record<line: int, kind: string, severity: string, msg: string, hint: string>> = ($codeLines
        | where {|row| ($row.text | parse --regex 'path type\) != ""' | length) > 0}
        | each {|row|
            {line: $row.line, kind: "path-type-bug", severity: "WARN",
             msg: "`path type` compared against \"\" — it returns null or a type name, never an empty string",
             hint: "compare == \"file\" or wrap in try — on 0.117 this comparison is a type-mismatch error"}
        })

    $findings | append $f1 | append $f2 | append $f3 | append $f4 | append $f5 | append $f6 | sort-by line
}

# ── brain suggestions (hybrid retrieval, JSON parsed natively) ───────────
# Returns [] on any failure — suggestions are a bonus, never a blocker.

def brain-suggest [sig: string]: nothing -> list<string> {
    if ($sig | str trim | is-empty) { return [] }
    if not ($BRAIN | path exists) { return [] }
    # hard deadline (fleet audit 17/11): suggestions are a bonus — a wedged
    # brain must never stall the shared gate. Tagged mailbox + job kill
    # (stale-mailbox law: the tag isolates this call's message).
    let tag: int = (random int 1..100000)
    let id: int = (job spawn --description 'run-nu brain suggest' {
        ^$BRAIN query $"nushell: ($sig)" --k 2 | complete | job send 0 --tag $tag
    })
    let r: record = (try { job recv --tag $tag --timeout 4sec } catch {
        job kill $id
        {exit_code: 124, stdout: '', stderr: 'deadline exceeded'}
    })
    if $r.exit_code != 0 { return [] }
    let parsed: any = (try { $r.stdout | from json } catch { return [] })
    if ($parsed.hits? | is-empty) { return [] }
    $parsed.hits | each {|h| $"- ($h.uri) — ($h.title)"}
}

# Extract the error headline from a stderr capture: nu's own errors carry
# an "  x <message>" marker line; external command failures start with
# "Error:" — take whichever exists, guarded for empty captures.

def headline [text: string]: nothing -> string {
    let ls: list<string> = ($text | lines)
    let marked: list<string> = ($ls | where {|l| ($l | str trim | str starts-with 'x ')})
    if not ($marked | is-empty) {
        $marked | first | str trim | str replace --regex '^x ' ''
    } else {
        let errLines: list<string> = ($ls | where {|l| ($l | str trim | str starts-with 'Error')})
        if not ($errLines | is-empty) { $errLines | first | str trim } else { '' }
    }
}

# ── main ─────────────────────────────────────────────────────────────────

def main [
    file?: string                # a .nu file; omit to read the script from stdin
    --json                       # machine-readable report on stdout (for agents)
    --no-run                     # gate only: parse + lint + suggest, never execute
    --keep                       # always keep the temp script (default: keep only on failure)
]: nothing -> any {
    let src: string = (if $file != null {
        if not ($file | path exists) { error make {msg: $"run-nu: file not found: ($file)"} }
        open --raw $file
    } else {
        open --raw /dev/stdin
    })
    if ($src | str trim | is-empty) { error make {msg: 'run-nu: empty script (pass a file or pipe code via stdin)'} }

    let dir: path = (mktemp -d --tmpdir run-nu.XXXXXX)
    let script: path = ($dir | path join 'script.nu')
    $src | save --raw $script

    # layer 1: parse gate (nu-check BY VALUE — inside nu it IS a value).
    # File mode gates the ORIGINAL file: relative use/source imports break
    # once copied to a temp dir (measured on the agent-brain drills).
    let gateFile: path = (if $file != null { $file } else { $script })
    let parses: bool = (nu-check $gateFile)

    # layer 2: lint (always runs, accumulates everything)
    let lint: list<record> = (lint-lines $src)
    let errors: list<record> = ($lint | where severity == ERROR)
    let warns: list<record> = ($lint | where severity == WARN)
    let blocked: bool = (not $parses) or (not ($errors | is-empty))

    # layer 4 (pre-run): suggestions for gate findings — the PARSE case
    # queries the brain with the REAL error headline (re-running a
    # parse-broken script executes nothing, it only shows the caret)
    let caret: record<exit_code: int, stdout: string, stderr: string> = (if not $parses {
        do { nu $script } | complete
    } else {
        {exit_code: 0, stdout: '', stderr: ''}
    })
    let gateSig: string = (if not $parses {
        headline $caret.stderr
    } else if not ($errors | is-empty) { ($errors | first).kind } else { '' })
    let gateHits: list<string> = (brain-suggest $gateSig)

    # layer 3: run unless blocked / --no-run
    let ran: bool = (not $blocked) and (not $no_run)
    let run: record<exit_code: int, stdout: string, stderr: string> = (if $ran {
        let t0: datetime = (date now)
        let out: record<exit_code: int, stdout: string, stderr: string> = (do { nu $script } | complete)
        $out | insert duration ((date now) - $t0)
    } else {
        {exit_code: -1, stdout: '', stderr: ''}
    })
    let failed: bool = ($ran and ($run.exit_code != 0))

    # runtime suggestions (the error headline, external errors included)
    let runtimeSig: string = (if $failed { headline $run.stderr } else { '' })
    let runtimeHits: list<string> = (brain-suggest $runtimeSig)

    let kept: path = (if (not $parses) or $failed or $keep { $script } else { '' })
    if $kept == '' { rm -rf $dir }

    # layer 5: render
    let report: record = {
        ok: (not $blocked and (not $failed))
        parse_ok: $parses
        lint: $lint
        ran: $ran
        exit: (if $ran { $run.exit_code } else { null })
        duration: (if $ran { ($run.duration | into string) } else { '' })
        runtime_error: $runtimeSig
        suggestions: {
            gate: $gateHits
            runtime: $runtimeHits
        }
        script: $kept
        stdout: (if $ran { $run.stdout } else { '' })
        stderr: (if $ran { $run.stderr } else { '' })
    }
    if $json {
        print ($report | to json)
    } else {
        if not $parses {
            print -e '── PARSE GATE FAILED ──'
            print -e ($caret.stderr | str trim)
        }
        if not ($lint | is-empty) {
            print -e '── lint ──'
            $lint | each {|f| print -e $"  ($f.severity) line ($f.line) [($f.kind)] ($f.msg)\n      fix: ($f.hint)"}
        }
        if not ($gateHits | is-empty) {
            print -e '── brain suggests (gate) ──'
            $gateHits | each {|h| print -e $"  ($h)"}
        }
        if $ran {
            print -e '── output ──'
            print -e ($run.stdout | str trim)
        }
        if $failed {
            print -e '── runtime error ──'
            print -e ($run.stderr | str trim)
            if not ($runtimeHits | is-empty) {
                print -e '── brain suggests (runtime) ──'
                $runtimeHits | each {|h| print -e $"  ($h)"}
            }
        }
        if $kept != '' {
            print -e $"── kept: ($kept) — re-run: nu ($kept) ──"
        } else if $ran and not $failed {
            print -e '── ok — temp cleaned ──'
        } else if $no_run {
            print -e '── gate ok — nothing ran (--no-run) ──'
        }
    }
    if $blocked or $failed { exit 1 }
}
