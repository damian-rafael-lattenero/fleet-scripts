# test_index_brain.nu — the pure-core proofs for lib/index-brain.nu: the
# first-match classifier, the launchctl/psql parses, the four verdicts and
# the docs delta (option-match over the Prior ADT).
use std/assert
use ../lib/index-brain.nu *
use /Users/lattenero/Projects/nushell-fp/mods/types.nu *   # some/none constructors

# 1. the classifier: row order is precedence; the catch-all renders last.
let rules: list<RenderRule> = [
    {when: {|| false}, render: {|| "never"}}
    {when: {|| true}, render: {|| "second"}}
    {when: {|| true}, render: {|| "never either"}}
]
assert equal (classify $rules) "second"
assert equal (classify [{when: {|| true}, render: {|| "only"}}]) "only"

# 2. the launchctl parse: labels absent from the table are missing; an
#    unparseable capture counts as everything missing.
let listing: string = "123\t0\tcom.zcode.colima\n-\t0\tcom.zcode.stack-up\n-\t78\tcom.other.job\n"
let agents: list<string> = ["com.zcode.colima" "com.zcode.stack-up" "com.zcode.agent-brain" "com.zcode.brain-mcp"]
assert equal (missing-from $listing $agents) ["com.zcode.agent-brain" "com.zcode.brain-mcp"]
assert equal (missing-from "" $agents) $agents
assert equal (missing-from $listing ["com.zcode.colima"]) []

# 3. the containers verdict: pg present + all agent containers healthy.
let healthy: list<any> = [
    {name: "agent-brain-pg", status: "Up 2 hours (healthy)"}
    {name: "agent-brain-redpanda", status: "Up 2 hours (healthy)"}
    {name: "unrelated", status: "Up 1 minute"}
]
assert equal (containers-verdict $healthy "agent-brain-pg") {ok: true, detail: "2 running, all healthy"}
let no_pg: list<any> = [{name: "agent-brain-redpanda", status: "Up (healthy)"}]
assert equal (containers-verdict $no_pg "agent-brain-pg") {ok: false, detail: "agent-brain-pg not running"}
let sick: list<any> = [
    {name: "agent-brain-pg", status: "Up (healthy)"}
    {name: "agent-brain-redpanda", status: "Up (unhealthy)"}
]
assert equal (containers-verdict $sick "agent-brain-pg") {ok: false, detail: "unhealthy: agent-brain-redpanda"}
# non-agent names never count as running agent containers
assert equal (containers-verdict [{name: "agent-brainish-pg", status: "Up (healthy)"}] "agent-brain-pg").ok false

# 4. the pgvector verdict: a version answers, empty is MISSING.
assert equal (pgvector-verdict "0.8.0") {ok: true, detail: "vector (0.8.0)"}
assert equal (pgvector-verdict "  0.8.0\n") {ok: true, detail: "vector (0.8.0)"}
assert equal (pgvector-verdict "") {ok: false, detail: "vector extension MISSING"}
assert equal (pgvector-verdict "  ") {ok: false, detail: "vector extension MISSING"}

# 5. the ollama verdict: any tag matching the model name answers.
assert equal (ollama-verdict ["nomic-embed-text:latest"] "nomic-embed-text") {ok: true, detail: "nomic-embed-text:latest"}
assert equal (ollama-verdict ["qwen2.5:7b"] "nomic-embed-text") {ok: false, detail: "nomic-embed-text NOT loaded"}
assert equal (ollama-verdict [] "nomic-embed-text").ok false

# 6. the serve verdict: the four-row ladder in order.
let good: record = {status: "ok", checks: {db: {pending: []}, embed: {ok: true, model: "nomic-embed-text"}}}
assert equal (serve-verdict $good) {ok: true, detail: "ok — db + embed nomic-embed-text"}
let degraded: record = {status: "degraded", checks: {db: {pending: []}, embed: {ok: true}}}
assert equal (serve-verdict $degraded) {ok: false, detail: "status degraded"}
let pending: record = {status: "ok", checks: {db: {pending: ["0009_x"]}, embed: {ok: true}}}
assert equal (serve-verdict $pending) {ok: false, detail: "pending migrations: 0009_x"}
let no_embed: record = {status: "ok", checks: {db: {pending: []}, embed: {ok: false}}}
assert equal (serve-verdict $no_embed) {ok: false, detail: "embed probe failed"}
# a missing model renders "?"
let no_model: record = {status: "ok", checks: {db: {pending: []}, embed: {ok: true}}}
assert equal (serve-verdict $no_model).detail "ok — db + embed ?"

# 7. the docs parse: count|freshest, none when unusable.
let stats: Prior = (doc-stats-parse "123|2026-11-24\n")
assert equal $stats.tag "some"
assert equal $stats.value {docs: 123, freshest: "2026-11-24"}
assert equal (doc-stats-parse "") (none)
assert equal (doc-stats-parse "123") (none)

# 8. the delta line: both sides some answers; any none is "?".
assert equal (delta-line $stats (some {docs: 130, freshest: "2026-11-25"})) "+7 docs · freshest 2026-11-25"
assert equal (delta-line (none) $stats) "?"
assert equal (delta-line $stats (none)) "?"

print "test_index_brain ok"
