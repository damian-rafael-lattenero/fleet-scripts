# lib/run-nu.nu — the pure core of run-nu.nu: the six static lint rules
# (accumulating, never one-at-a-time) and the stderr headline extractor. The
# script keeps nu-check, execution, the brain suggestion and the render.
export type LintFinding = record<line: int, kind: string, severity: string, msg: string, hint: string>
export type CodeLine = record<line: int, text: string>
export type PathHit = record<line: int, path: string>

# Every rule sees the source lines and ACCUMULATES its findings; findings
# never block inspection of later rules (the accumulation law).
export def lint-lines [src: string]: nothing -> list<LintFinding> {
    let lines: list<string> = ($src | lines)
    let findings: list<LintFinding> = ([])

    # strip obvious comment lines once (comment $vars are not code)
    let codeLines: list<CodeLine> = ($lines
        | enumerate
        | each {|row| {line: ($row.index + 1), text: $row.item}}
        | where {|row| not ($row.text | str trim | str starts-with '#')})

    # rule: self-truncate — open X ... save -f X truncates before the lazy
    # read finishes (measured 15/11: a whole file was lost this way)
    let opened: list<PathHit> = ($codeLines
        | each {|row| {line: $row.line, m: ($row.text | parse --regex 'open\s+(?:--raw\s+)?[{(]?([\w./~-]+)')} }
        | where {|r| not ($r.m | is-empty)}
        | each {|r| {line: $r.line, path: ($r.m | first).capture0}})
    let saved: list<PathHit> = ($codeLines
        | each {|row| {line: $row.line, m: ($row.text | parse --regex 'save\s+(?:-f\s+)?([\w./~-]+)')} }
        | where {|r| not ($r.m | is-empty)}
        | each {|r| {line: $r.line, path: ($r.m | first).capture0}})
    # post-filters: flags captured as paths (--raw) are not paths; only
    # slash-bearing or tilde-prefixed captures count
    let opened2: list<PathHit> = ($opened | where {|o| (not ($o.path | str starts-with '-')) and (($o.path | str contains '/') or ($o.path | str starts-with '~'))})
    let saved2: list<PathHit> = ($saved | where {|o| (not ($o.path | str starts-with '-')) and (($o.path | str contains '/') or ($o.path | str starts-with '~'))})
    let truncates2: list<PathHit> = ($saved2 | where {|s| ($opened2 | where {|o| $o.path == $s.path} | length) > 0})
    let f1: list<LintFinding> = ($truncates2 | each {|t|
        {line: $t.line, kind: "self-truncate", severity: "ERROR",
         msg: $"save -f overwrites '($t.path)' which this script also opens",
         hint: "save truncates before the lazy open read completes — write to a temp path then move"}})

    # rule: midword-$ — a bare token with $ INSIDE (gui/$uid) is literal
    # text; interpolation only happens inside $"..." strings
    let f2: list<LintFinding> = ($codeLines
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
    # not a path (contains, not starts-with — audit 17/11).
    let f3: list<LintFinding> = ($codeLines
        | where {|row| ($row.text | parse --regex "'([^']*~[^']*)'" | length) > 0}
        | where {|row| not ($row.text | str trim | str contains 'print')}
        | each {|row|
            {line: $row.line, kind: "quoted-tilde", severity: "WARN",
             msg: "single-quoted string contains ~ — it will NOT expand",
             hint: "expand first (path expand / $env.HOME join) or drop the quotes"}})

    # rule: blind-sleep — sleeps >= 10sec violate the reactive law
    let f4: list<LintFinding> = ($codeLines
        | each {|row|
            {line: $row.line, secs: ($row.text | parse --regex 'sleep\s+([\d.]+)\s*sec' | each {|p| $p.capture0 | into float})}
        }
        | where {|r| ($r.secs | length) > 0 and (($r.secs | first) >= 10)}
        | each {|r|
            {line: $r.line, kind: "blind-sleep", severity: "WARN",
             msg: $"sleep of (($r.secs | first))sec — a blind long wait",
             hint: "reactive law: job send/recv with --timeout, watch, or an event — never blind sleep"}})

    # rule: self-overwrite — open X | ... | save -f X in the SAME pipeline line
    # where X is ANY token (literal path OR $var): the $var variant ducked
    # under the literal-only self-truncate rule (audit 17/11).
    let f5: list<LintFinding> = ($codeLines
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
    let f6: list<LintFinding> = ($codeLines
        | where {|row| ($row.text | parse --regex 'path type\) != ""' | length) > 0}
        | each {|row|
            {line: $row.line, kind: "path-type-bug", severity: "WARN",
             msg: "`path type` compared against \"\" — it returns null or a type name, never an empty string",
             hint: "compare == \"file\" or wrap in try — on 0.117 this comparison is a type-mismatch error"}
        })

    $findings | append $f1 | append $f2 | append $f3 | append $f4 | append $f5 | append $f6 | sort-by line
}

# Extract the error headline from a stderr capture: nu's own errors carry
# an "  x <message>" / "  × <message>" marker line; external command
# failures start with "Error:" — take whichever exists, guarded for empty
# captures. The 0.117 marker is the MULTIPLICATION sign (×), not ASCII x:
# the headline rule matched neither for months until the test pinned it.
export def headline [text: string]: nothing -> string {
    let ls: list<string> = ($text | lines)
    let marked: list<string> = ($ls | where {|l|
        let t: string = ($l | str trim)
        ($t | str starts-with 'x ') or ($t | str starts-with '× ')
    })
    if not ($marked | is-empty) {
        return ($marked | first | str trim | str replace --regex '^[x×] ' '')
    }
    let errLines: list<string> = ($ls | where {|l| ($l | str trim | str starts-with 'Error')})
    if not ($errLines | is-empty) {
        return ($errLines | first | str trim)
    }
    ''
}

# ── ide-check: the static oracle (28/11, verified 0.117.0) ────────────────
# `nu -n --ide-check 100 file` parses a file and returns EVERY diagnostic as
# JSON Lines — a plain `nu` run reports only the first before exiting.
# Parse-only (it never executes the file — proven with a side-effect file);
# 12–36 ms on the fleet's files; exit 0 even with errors, so the JSON is the
# verdict, never the exit code. It sees statically: undefined variables (top
# level and inside defs), extra positionals, operator type mismatches,
# unknown flags on builtins, missing modules, unclosed delimiters. It cannot
# see: parse-legal unknown externals, pipeline input-type mismatches,
# runtime errors (missing files, failed externals).

# Diagnostics → located error lines. PURE: no process spawn, so tests pin
# the math without nu. Sorted by position, duplicates collapsed, non-Error
# rows dropped.
export def locate-diags [diags: list<any>, src: string]: nothing -> list<string> {
    $diags
    | where {|d| ($d | get -o type) == 'diagnostic' and ($d | get -o severity) == 'Error' }
    | sort-by {|d| $d.span?.start? | default 0 }
    | each {|d|
        let st: int = ($d | get -o span | default {} | get -o start | default 0)
        let upto: string = ($src | str substring 0..$st)
        $"line ($upto | lines | length), col (($upto | lines | last | str length) + 1): ($d.message)"
    }
    | uniq
}

# The EDGE: ide-check a file for real; its located errors, [] when clean.
export def ide-errors [file: string]: nothing -> list<string> {
    let run: record = (do { ^nu -n --ide-check 100 $file } | complete)
    if $run.exit_code != 0 {
        return [$"ide-check failed: ($run.stderr | str substring 0..120)"]
    }
    let diags: list<any> = ($run.stdout | lines | each {|l|
        try { $l | from json } catch { null }
    } | compact)
    locate-diags $diags (open --raw $file)
}
