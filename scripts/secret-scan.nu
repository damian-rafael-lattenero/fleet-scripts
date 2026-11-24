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

use /Users/lattenero/Scripts/nushell-fp/mods/proc.nu *
use ../lib/secret-scan.nu *

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
        print $"✓ no staged files to scan: ($dir)"
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
        die $"staged: findings in ($bad | str join ', ') — values redacted above"
    }
    print $"✓ no secrets in ($files | length) staged files: ($dir)"
}

# THE HISTORY DEFAULT: trufflehog's own walker, VERIFIED findings only — the
# only history answer that matters (a fake fixture cannot verify; a live key
# does). No --only-verified flag exists in this build: the JSON's Verified
# field is the filter, applied here.
def scan-history [dir: string]: nothing -> nothing {
    if not ($TRUFFLEHOG | path exists) { die "trufflehog is not installed — brew install trufflehog" }
    let r: record = (^$TRUFFLEHOG git $"file://($dir)" --json --no-update | complete)
    if $r.exit_code != 0 {
        die $"trufflehog exit ($r.exit_code): (fold-stderr $r | str trim | str substring 0..300)"
    }
    # the JSON-lines parse and the Verified filter ride lib/secret-scan.nu
    # (tested): 0.117's `from json` is lenient, so the record filter is what
    # keeps a scanner's noise out of the rows.
    let rows: list<any> = (json-rows $r.stdout)
    let verified: list<any> = (verified-signals $rows)
    if ($verified | is-empty) {
        print $"✓ history holds no LIVE credentials: ($dir) — (unverified-tail $rows)"
        return
    }
    for o in $verified {
        print -e $"· ($o.DetectorName) LIVE in ($o.SourceMetadata.Data.Git.file):($o.SourceMetadata.Data.Git.line)"
    }
    die $"history: ($verified | length) LIVE credential(s) in the history of ($dir) — INCIDENT"
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
            print $"  ($h | str substring 0..7): ($found | length) findings in non-test files"
        }
    }
    if $hits > 0 { die $"history-deep: ($hits) finding(s) in ($dir)" }
    print $"✓ deep history clean (outside tests/vendor): ($dir)"
}

def main [repo: path, --staged, --history, --deep]: nothing -> nothing {
    if not ($GITLEAKS | path exists) { die "gitleaks is not installed — brew install gitleaks" }
    if not ($CONFIG | path exists) { die $"missing the config: ($CONFIG)" }
    let dir: string = ($repo | path expand)
    if (($dir | path type) != "dir") { die $"not a directory: ($dir)" }
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
        print $"✓ no secrets in the working tree: ($dir)"
        return
    }
    let findings: list<any> = (try { $r.stdout | from json } catch { [] })
    for line in (finding-lines $findings) { print -e $line }
    die $"tree: ($findings | length) findings in ($dir) — values redacted"
}
