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

# The lint shapes and the six rules ride lib/run-nu.nu (tested); the run
# capture is this script's own.
type Captured = record<exit_code: int, stdout: string, stderr: string>
use lib/run-nu.nu *

# ── lint rules ───────────────────────────────────────────────────────────
# The rules, the shapes and the headline extractor live in lib/run-nu.nu
# (tested: tests/test_run_nu.nu) — one source of truth, no local copy.



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
    let r: Captured = (try { job recv --tag $tag --timeout 4sec } catch {
        job kill $id
        {exit_code: 124, stdout: '', stderr: 'deadline exceeded'}
    })
    if $r.exit_code != 0 { return [] }
    let parsed: any = (try { $r.stdout | from json } catch { return [] })
    if ($parsed.hits? | is-empty) { return [] }
    $parsed.hits | each {|h| $"- ($h.uri) — ($h.title)"}
}

# The headline extractor moved below the brain block (imported from the lib).

# ── main ─────────────────────────────────────────────────────────────────

def main [
    file?: string                # a .nu file; omit to read the script from stdin
    --json                       # machine-readable report on stdout (for agents)
    --no-run                     # gate only: parse + lint + suggest, never execute
    --keep                       # always keep the temp script (default: keep only on failure)
]: nothing -> nothing {
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
    let lint: list<LintFinding> = (lint-lines $src)
    let errors: list<record> = ($lint | where severity == ERROR)
    let warns: list<record> = ($lint | where severity == WARN)
    let blocked: bool = (not $parses) or (not ($errors | is-empty))

    # layer 4 (pre-run): suggestions for gate findings — the PARSE case
    # queries the brain with the REAL error headline (re-running a
    # parse-broken script executes nothing, it only shows the caret)
    let caret: Captured = (if not $parses {
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
    let run: Captured = (if $ran {
        let t0: datetime = (date now)
        let out: Captured = (do { nu $script } | complete)
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
