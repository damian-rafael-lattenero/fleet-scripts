# test_secret_scan.nu — the pure-core proofs for lib/secret-scan.nu: the
# deep-path allowlist matrix, the JSON-lines parse, the verified filter, the
# honest tail and the redacted finding lines.
use std/assert
use ../lib/secret-scan.nu *

# 1. the allowlist: vendored/test paths are allowed, source paths are not.
for p in [
    "node_modules/react/index.js"
    "packages/app/node_modules/x/y.js"
    ".gradle/caches/x.bin"
    "pkg/build/out.js"
    "docs/build/index.md"
    "pkg/dist/a.js"
    "out/x"
    "a/.worktrees/w/f.nu"
    "third-party/lib.c"
    "bundled-agents/agent.js"
    "test/x.ts"
    "tests/a.nu"
    "src/app.test.ts"
    "src/app.test.tsx"
    "src/app.spec.js"
    "src/x.e2e.ts"
    "wdio.conf.ts"
    "fixtures/a.env"
    "fixture/x"
    "scripts/test-scan.nu"
] {
    assert equal (deep-allowed $p) true $p
}
for p in [
    "src/main.ts"
    "README.md"
    "build.md"
    "builder/x.ts"
    "src/latest.ts"
    "scripts/deploy.nu"
    "app.testing.ts"
] {
    assert equal (deep-allowed $p) false $p
}

# 2. the JSON-lines parse: objects survive, garbage and blanks vanish.
let stdout: string = '{"Verified": true, "DetectorName": "AWS"}
not json at all

{"Verified": false, "DetectorName": "Generic"}
'
let rows: list<any> = (json-rows $stdout)
assert equal ($rows | length) 2
assert equal (verified-signals $rows | length) 1
assert equal (verified-signals $rows | get 0.DetectorName) "AWS"
assert equal (verified-signals [{DetectorName: "no field"}] | length) 0

# 3. the honest tail: empty vs unverified counts.
assert equal (unverified-tail []) "no signals"
assert equal (unverified-tail $rows) "2 unverified signals — fixtures or a local DSN, not actionable"
# the tail counts EVERY row, not just the unverified ones (the CLI's own order)
assert equal (unverified-tail [{Verified: true}]) "1 unverified signals — fixtures or a local DSN, not actionable"

# 4. the finding lines: rule + location, redacted by construction.
assert equal (finding-lines [{RuleID: "aws-key", File: "a.env", StartLine: 3}]) ["· aws-key en a.env:3"]
assert equal (finding-lines []) []

print "test_secret_scan ok"
