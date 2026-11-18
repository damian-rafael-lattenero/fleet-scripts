#!/Users/lattenero/.local/bin/nu-nightly
# secret-scan.nu — THE HOUSE'S SECRETS GATE (audit item 4).
#
# THREE ENGINES, each doing what it does best (measured 18/11):
#   · `gitleaks dir <path>` — works on a directory AND a single file: the TREE
#     and STAGED gates (the pre-commit hook's mode).
#   · `gitleaks git …` — BROKEN on gitleaks 8.30 + git 2.56: it scans 0
#     COMMITS and exits 0 (upstream #1464/#2129: git-log stderr aborts the
#     walk silently). NEVER trust it.
#   · `trufflehog git file://…` — its OWN walker (no git-log parsing), file
#     attribution, and live credential VERIFICATION: the HISTORY engine.
# The deep attributed gitleaks sweep (per commit, path allowlists applied) is
# `--deep`; the history default asks the question that matters: is
# there a LIVE leaked credential?
#
#   secret-scan.nu <repo>                  gitleaks dir over the working tree
#   secret-scan.nu <repo> --staged         gitleaks dir over EACH staged file
#   secret-scan.nu <repo> --history        trufflehog, VERIFIED findings only
#   secret-scan.nu <repo> --deep           gitleaks per commit, non-test paths
#
# Values are ALWAYS redacted: a finding names the file and the rule, never the
# secret. Exit 0 = clean, 1 = findings or a broken tool — a hook that cannot
# run must NEVER pass silently.
const GITLEAKS: string = "/opt/homebrew/bin/gitleaks"
const TRUFFLEHOG: string = "/opt/homebrew/bin/trufflehog"
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

# THE HISTORY DEFAULT: trufflehog's own walker, VERIFIED findings only — the
# only history answer that matters (a fake fixture cannot verify; a live key
# does). No --only-verified flag exists in this build: the JSON's Verified
# field is the filter, applied here.
def scan-history [dir: string]: nothing -> nothing {
    if not ($TRUFFLEHOG | path exists) { die "trufflehog no está instalado — brew install trufflehog" }
    let r: record = (^$TRUFFLEHOG git $"file://($dir)" --json --no-update | complete)
    if $r.exit_code != 0 {
        die $"trufflehog exit ($r.exit_code): ($r.stderr | str trim | str substring 0..300)"
    }
    let rows: list<any> = ($r.stdout | lines | where {|l| ($l | str trim | is-not-empty) }
        | each {|l| try { $l | from json } catch { null } } | where {|o| $o != null })
    let verified: list<any> = ($rows | where {|o| ($o.Verified? | default false) == true })
    if ($verified | is-empty) {
        let tail: string = (if ($rows | is-empty) {
            "sin señales"
        } else {
            $"($rows | length) señales sin verificar — fixtures o DSN local, no accionables"
        })
        print $"✓ historia sin credenciales VIVAS: ($dir) — ($tail)"
        return
    }
    for o in $verified {
        print -e $"· ($o.DetectorName) VIVO en ($o.SourceMetadata.Data.Git.file):($o.SourceMetadata.Data.Git.line)"
    }
    die $"history: ($verified | length) credencial VIVA en la historia de ($dir) — INCIDENTE"
}

def deep-allowed [f: string]: nothing -> bool {
    let pats: list<string> = [
        '(^|/)node_modules/'
        '(^|/)\.gradle/'
        '(^|/)\.kotlin/'
        '(^|/)build/'
        '(^|/)dist/'
        '(^|/)out/'
        '(^|/)\.worktrees/'
        '(^|/)third-party/'
        '(^|/)bundled-agents/'
        '(^|/)test/'
        '(^|/)tests/'
        '\.test\.[tj]sx?$'
        '\.spec\.[tj]sx?$'
        '\.e2e\.[tj]s$'
        'wdio\.conf\.ts$'
        '(^|/)fixtures?/'
        '(^|/)scripts/test-'
    ]
    ($pats | any {|p| $f =~ $p })
}

# THE DEEP PASS: gitleaks per commit over the NON-test/vendor files, so the
# path allowlists actually apply (stdin has no paths). Unverified shapes land
# here; the verified question lives in scan-history.
def scan-history-deep [dir: string]: nothing -> nothing {
    let commits: list<string> = (^git -C $dir rev-list --all | complete | get stdout | lines)
    print $"($dir): ($commits | length) commits"
    mut hits: int = 0
    for h in $commits {
        let files: list<string> = (^git -C $dir show --format= --name-only $h | complete | get stdout | lines
            | where {|f| ($f | str trim | is-not-empty) })
        let kept: list<string> = ($files | where {|f| not (deep-allowed $f) })
        if ($kept | is-empty) { continue }
        let r: record = (^git -C $dir show $h -- ...$kept
            | ^$GITLEAKS stdin --config $CONFIG --redact --no-banner --report-format json --report-path -
            | complete)
        if $r.exit_code != 0 {
            let found: list<any> = (try { $r.stdout | from json } catch { [] })
            $hits = ($hits + ($found | length))
            print $"  ($h | str substring 0..7): ($found | length) hallazgos en archivos no-test"
        }
    }
    if $hits > 0 { die $"history-deep: ($hits) hallazgo(s) en ($dir)" }
    print $"✓ historia profunda limpia (fuera de tests/vendor): ($dir)"
}

def main [repo: path, --staged, --history, --deep]: nothing -> nothing {
    if not ($GITLEAKS | path exists) { die "gitleaks no está instalado — brew install gitleaks" }
    if not ($CONFIG | path exists) { die $"falta la config: ($CONFIG)" }
    let dir: string = ($repo | path expand)
    if (($dir | path type) != "dir") { die $"no es un directorio: ($dir)" }
    if $staged {
        scan-staged $dir
        return
    }
    if $deep {
        scan-history-deep $dir
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
