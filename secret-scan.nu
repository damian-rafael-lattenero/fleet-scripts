#!/Users/lattenero/.local/bin/nu-nightly
# secret-scan.nu — THE HOUSE'S SECRETS GATE (audit item 4).
#
# MEASURED 18/11 on gitleaks 8.30.1 + git 2.56 (do not "fix" this back):
#   · `gitleaks git …` (history commits) scans 0 COMMITS on this pair — the
#     flag set is advertised but the parse yields nothing. NEVER trust it.
#   · `gitleaks dir <path>` works on a directory AND on a single file.
#   · `gitleaks stdin` works on raw content and on a `git log -p` patch.
# So:
#   secret-scan.nu <repo>             gitleaks dir over the working tree
#   secret-scan.nu <repo> --staged    gitleaks dir over EACH staged file (the
#                                     pre-commit hook's mode — exact)
#   secret-scan.nu <repo> --history   the whole `git log -p --all` patch piped
#                                     through gitleaks stdin (the one-shot sweep)
#
# Values are ALWAYS redacted (gitleaks --redact): a finding names the file and
# the rule, never the secret. Exit 0 = clean, 1 = findings or a broken tool — a
# hook that cannot run must NEVER pass silently.
const GITLEAKS: string = "/opt/homebrew/bin/gitleaks"
const CONFIG: string = "/Users/lattenero/.config/gitleaks/gitleaks.toml"

def die [msg: string]: nothing -> nothing {
    print -e $"✗ ($msg)"
    exit 1
}

def staged-files [dir: string]: nothing -> list<string> {
    (^git -C $dir diff --cached --name-only --diff-filter=ACMR | complete | get stdout | lines
        | each {|l| $l | str trim }
        | where {|l| ($l | is-not-empty) })
}

def scan-one [abs: string]: nothing -> record {
    (^$GITLEAKS dir $abs --config $CONFIG --redact --no-banner --report-format json --report-path - | complete)
}

def scan-staged [dir: string]: nothing -> nothing {
    let files: list<string> = (staged-files $dir)
    if ($files | is-empty) {
        print $"✓ sin archivos staged que escanear: ($dir)"
        return
    }
    mut bad: list<string> = []
    for rel in $files {
        let abs: string = ($dir | path join $rel)
        if (($abs | path type) != "file") { continue }
        let r: record = (scan-one $abs)
        if $r.exit_code != 0 {
            $bad = ($bad | append $rel)
            let findings: list<any> = (try { $r.stdout | from json } catch { [] })
            for f in $findings {
                print -e $"· ($rel) — ($f.RuleID):($f.StartLine)"
            }
        }
    }
    if ($bad | is-not-empty) {
        die $"staged: hallazgos en ($bad | str join ', ') — valores redactados arriba"
    }
    print $"✓ sin secretos en ($files | length) archivos staged: ($dir)"
}

def scan-history [dir: string]: nothing -> nothing {
    # the patch streams git → gitleaks natively: some commits carry binary
    # blobs and capturing them in a nu variable would poison the pipeline
    let r: record = (^git -C $dir log -p --all
        | ^$GITLEAKS stdin --config $CONFIG --redact --no-banner --report-format json --report-path -
        | complete)
    if $r.exit_code == 0 {
        print $"✓ sin secretos en la historia: ($dir)"
        return
    }
    let findings: list<any> = (try { $r.stdout | from json } catch { [] })
    for f in $findings {
        print -e $"· ($f.RuleID) en ($f.File):($f.StartLine)"
    }
    die $"history: ($findings | length) hallazgos en ($dir) — valores redactados"
}

def main [repo: path, --staged, --history]: nothing -> nothing {
    if not ($GITLEAKS | path exists) { die "gitleaks no está instalado — brew install gitleaks" }
    if not ($CONFIG | path exists) { die $"falta la config: ($CONFIG)" }
    let dir: string = ($repo | path expand)
    if (($dir | path type) != "dir") { die $"no es un directorio: ($dir)" }
    if $staged {
        scan-staged $dir
        return
    }
    if $history {
        scan-history $dir
        return
    }
    let r: record = (scan-one $dir)
    if $r.exit_code == 0 {
        print $"✓ sin secretos en el working tree: ($dir)"
        return
    }
    let findings: list<any> = (try { $r.stdout | from json } catch { [] })
    for f in $findings {
        print -e $"· ($f.RuleID) en ($f.File):($f.StartLine)"
    }
    die $"tree: ($findings | length) hallazgos en ($dir) — valores redactados"
}
