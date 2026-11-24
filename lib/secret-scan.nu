# lib/secret-scan.nu — the pure core of secret-scan.nu: the deep-path
# allowlist, the trufflehog JSON-lines parse, the verified filter, the honest
# tail message and the redacted finding lines. The script keeps the git/
# gitleaks/trufflehog effects.
use ./json-lines.nu *

export const DEEP_PATHS: list<string> = [
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

# True for vendored/test paths the deep pass must not convict.
export def deep-allowed [f: string]: nothing -> bool {
    $DEEP_PATHS | any {|p| $f =~ $p }
}

# trufflehog --json emits one JSON object per line; garbage lines are
# skipped (a scanner's noise is not a finding). The parse itself is the
# shared lib/json-lines.nu piece (0.117's from json is LENIENT).
export def json-rows [stdout: string]: nothing -> list<any> {
    record-lines $stdout
}

# THE history answer that matters: live credentials only (a fake fixture
# cannot verify; a live key does).
export def verified-signals [rows: list<any>]: nothing -> list<any> {
    $rows | where {|o| ($o.Verified? | default false) == true }
}

# The clean-history sentence: no signals, or how many unverified ones.
export def unverified-tail [rows: list<any>]: nothing -> string {
    if ($rows | is-empty) {
        "no signals"
    } else {
        $"($rows | length) unverified signals — fixtures or a local DSN, not actionable"
    }
}

# The redacted finding lines: rule and location, never the value.
export def finding-lines [findings: list<any>]: nothing -> list<string> {
    $findings | each {|f| $"· ($f.RuleID) en ($f.File):($f.StartLine)" }
}
