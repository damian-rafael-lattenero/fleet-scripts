#!/opt/homebrew/bin/nu
# index-brain.nu — the brain's rebuild as ONE command: index everything, and
# when a layer blocks the index, repair that layer in dependency order.
#
# Denotation (the ADR line): this script denotes «the brain is rebuilt» — its
# value is a verdict per dependency layer plus the documents the index now
# holds. Every probe and repair is an effect at the edge; the ladder itself is
# DATA (an ordered list of layers), so the order cannot drift from the code.
#
# Modes (the owner's ruling, same as ram-clean): bare = --fix — the drill IS
# the default. `--check` is read-only: probes + freshness + smokes, no
# repairs, no indexing, no writes.
#
# The ladder (top blocks bottom):
#   1 launchd     the boot chain loaded (colima, stack-up, agent-brain, brain-mcp)
#   2 colima      the VM up            repair = the watchdog's own script
#   3 docker      the daemon answers   repair = bounded wait (colima just came up)
#   4 containers  agent-brain-* healthy repair = docker compose up -d --wait
#   5 pgvector    pg answers + vector  repair = CREATE EXTENSION IF NOT EXISTS
#   6 ollama      embedder model loaded repair = ollama pull nomic-embed-text
#   7 serve       /ready: db + migrations + a real embedding probe
#                                      repair = launchctl kickstart -k + wait
#   8 index       BOTH legs, sequential (shared DB + one embedder — parallel
#                 would thrash ollama): `index` (corpus.txt) then `index-repos`
#   9 verify      doc count + freshest updated_at + query/memory/bus smokes
#
# Out of scope ON PURPOSE: the judge evals (real-questions, usage, shadow,
# dream) are MEASUREMENT, not rebuild — their door is `brain-eval` / the 04:00
# rag-nightly. This script rebuilds; it does not grade.
#
# Every run appends to ~/Library/Logs/index-brain.log (the fleet contract).

const BIN: string = "/Users/lattenero/Projects/agent-brain/core/build/install/agent-brain/bin/agent-brain"
const LOG_FILE: string = "/Users/lattenero/Library/Logs/index-brain.log"
const COMPOSE: string = "/Users/lattenero/Projects/agent-brain/docker-compose.yml"
const COLIMA_WATCHDOG: string = "/Users/lattenero/Projects/agent-brain/scripts/colima-watchdog.nu"
const COLIMA: string = "/opt/homebrew/bin/colima"
const OLLAMA: string = "/opt/homebrew/bin/ollama"
const EMBED_MODEL: string = "nomic-embed-text"
const SERVE_READY: string = "http://127.0.0.1:8765/ready"
const OLLAMA_TAGS: string = "http://127.0.0.1:11434/api/tags"
const PG_CONTAINER: string = "agent-brain-pg"
const PG_DB: string = "agent_brain"
const PG_USER: string = "brain"
# the boot chain the health-check and stack-up already agree on
const AGENTS: list<string> = ["com.zcode.colima" "com.zcode.stack-up" "com.zcode.agent-brain" "com.zcode.brain-mcp"]

# The type aliases (the owner's law): every shape reads once. The probe
# verdicts, the Prior ADT and the classifier ride lib/index-brain.nu (tested).
type Layer = record<name: string, hint: string, probe: closure, repair: closure>
type IndexLeg = record<leg: string, args: list<string>>
type LegResult = record<leg: string, ok: bool, exit: int, secs: int, detail: string>
type VerifyRow = record<check: string, ok: bool, detail: string>

use /Users/lattenero/Projects/nushell-fp/mods/log.nu *
use /Users/lattenero/Projects/nushell-fp/mods/proc.nu fold-stderr
use /Users/lattenero/Projects/nushell-fp/mods/wait.nu wait-until
use /Users/lattenero/Projects/nushell-fp/mods/types.nu *
use ../lib/index-brain.nu *

# One voice for stdout AND the run log — the shared mod does the work.
def emit [line: string]: nothing -> nothing {
    emit-to $LOG_FILE $line
}

# ── the probes (pure reads: every external is parsed ONCE into a record) ──

def missing-agents []: nothing -> list<string> {
    let l: record = (^launchctl list | complete)
    if $l.exit_code != 0 { return $AGENTS }
    # the table parse rides lib/index-brain.nu (missing-from, tested)
    missing-from $l.stdout $AGENTS
}

def probe-launchd []: nothing -> LayerProbe {
    let missing: list<string> = (missing-agents)
    let ok: bool = ($missing | is-empty)
    {ok: $ok, detail: (if $ok { "4/4 loaded" } else { $"missing: ($missing | str join ', ')" })}
}

def probe-colima []: nothing -> LayerProbe {
    let s: record = (^$COLIMA status | complete)
    {ok: ($s.exit_code == 0), detail: (if $s.exit_code == 0 { "up" } else { "down" })}
}

def probe-docker []: nothing -> LayerProbe {
    let d: record = (^docker ps --format "{{.Names}}" | complete)
    {ok: ($d.exit_code == 0), detail: (if $d.exit_code == 0 { "daemon answers" } else { "daemon not answering" })}
}

def probe-containers []: nothing -> LayerProbe {
    let ps: record = (^docker ps --format "{{.Names}}\t{{.Status}}" | complete)
    if $ps.exit_code != 0 { return {ok: false, detail: "docker not answering"} }
    let rows: table = ($ps.stdout | lines | where {|l| ($l | str trim) != "" } | parse "{name}\t{status}")
    # the "(healthy)"-exact verdict rides lib/index-brain.nu (tested)
    containers-verdict $rows $PG_CONTAINER
}

def probe-pgvector []: nothing -> LayerProbe {
    let q: record = (^docker exec -i $PG_CONTAINER psql -U $PG_USER -d $PG_DB -t -A -c "select extversion from pg_extension where extname='vector';" | complete)
    if $q.exit_code != 0 { return {ok: false, detail: "psql not answering"} }
    let v: string = ($q.stdout | lines | where {|l| ($l | str trim) != "" } | first | default "" | str trim)
    pgvector-verdict $v
}

def probe-ollama []: nothing -> LayerProbe {
    let t: record = (^curl -s -m 5 $OLLAMA_TAGS | complete)
    if $t.exit_code != 0 or ($t.stdout | str trim | is-empty) { return {ok: false, detail: "ollama not answering"} }
    let models: list<string> = (try { $t.stdout | from json | get models | get name } catch { [] })
    ollama-verdict $models $EMBED_MODEL
}

def probe-serve []: nothing -> LayerProbe {
    let r: record = (^curl -s -m 6 $SERVE_READY | complete)
    if $r.exit_code != 0 or ($r.stdout | str trim | is-empty) { return {ok: false, detail: "/ready not answering"} }
    let j: record = (try { $r.stdout | from json } catch { {status: "unparseable"} })
    serve-verdict $j
}

# ── the repairs (each bounded by wait-until — no blind long sleeps) ──

def repair-launchd []: nothing -> nothing {
    for label in (missing-agents) {
        let plist: string = ($"($env.HOME)/Library/LaunchAgents/($label).plist")
        if not ($plist | path exists) {
            emit $"   ($label).plist does not exist — cannot bootstrap"
            continue
        }
        let r: record = (^launchctl bootstrap $"gui/(id -u)" $plist | complete)
        emit $"   bootstrap ($label): exit ($r.exit_code)"
    }
}

def repair-colima []: nothing -> nothing {
    # Composition, not a copy: the LaunchAgent's own watchdog starts the VM.
    let r: record = (^nu $COLIMA_WATCHDOG | complete)
    emit $"   colima-watchdog: exit ($r.exit_code)"
}

def repair-docker []: nothing -> nothing {
    # Nothing to start that is not colima's job: wait for the socket.
    let ok: bool = (wait-until 60sec {|| (probe-docker).ok } --interval 1sec)
    let state: string = (if $ok { "up" } else { "still down" })
    emit $"   docker wait: ($state)"
}

def repair-containers []: nothing -> nothing {
    let r: record = (^docker compose -f $COMPOSE up -d --wait | complete)
    emit $"   compose up --wait: exit ($r.exit_code)"
    if $r.exit_code != 0 {
        emit $"   (fold-stderr $r | str substring 0..200)"
    }
}

def repair-pgvector []: nothing -> nothing {
    let r: record = (^docker exec -i $PG_CONTAINER psql -U $PG_USER -d $PG_DB -c "create extension if not exists vector;" | complete)
    emit $"   create extension vector: exit ($r.exit_code)"
    (wait-until 30sec {|| (probe-pgvector).ok } --interval 1sec) | ignore
}

def repair-ollama []: nothing -> nothing {
    emit $"   pulling ($EMBED_MODEL) (network — the one fix that can take minutes)…"
    let r: record = (^$OLLAMA pull $EMBED_MODEL | complete)
    emit $"   ollama pull: exit ($r.exit_code)"
    (wait-until 30sec {|| (probe-ollama).ok } --interval 1sec) | ignore
}

def repair-serve []: nothing -> nothing {
    let r: record = (^launchctl kickstart -k $"gui/(id -u)/com.zcode.agent-brain" | complete)
    emit $"   kickstart com.zcode.agent-brain: exit ($r.exit_code)"
    let ok: bool = (wait-until 120sec {|| (probe-serve).ok } --interval 1sec)
    let state: string = (if $ok { "up" } else { "still not ready" })
    emit $"   /ready wait: ($state)"
}

# ── the ladder as DATA: order = dependency order (top blocks bottom) ──
def layers []: nothing -> list<Layer> {
    [
        {name: "launchd", hint: "bootstrap the missing plists from ~/Library/LaunchAgents", probe: {|| probe-launchd }, repair: {|| repair-launchd }}
        {name: "colima", hint: "start the VM via its own watchdog", probe: {|| probe-colima }, repair: {|| repair-colima }}
        {name: "docker", hint: "wait for the daemon socket (colima just came up)", probe: {|| probe-docker }, repair: {|| repair-docker }}
        {name: "containers", hint: "docker compose up -d --wait", probe: {|| probe-containers }, repair: {|| repair-containers }}
        {name: "pgvector", hint: "CREATE EXTENSION IF NOT EXISTS vector", probe: {|| probe-pgvector }, repair: {|| repair-pgvector }}
        {name: "ollama", hint: $"ollama pull ($EMBED_MODEL)", probe: {|| probe-ollama }, repair: {|| repair-ollama }}
        {name: "serve", hint: "launchctl kickstart -k com.zcode.agent-brain", probe: {|| probe-serve }, repair: {|| repair-serve }}
    ]
}

def probe-it [layer: Layer]: nothing -> LayerProbe {
    try { do $layer.probe } catch {|e| {ok: false, detail: $"probe raised: ($e.msg)"} }
}

# Probe → (in fix mode) repair once → re-probe. One repair per layer per run:
# a repair that needs a second pass is a bug to read, not to loop on.
def ensure [layer: Layer, fix: bool]: nothing -> LayerProbe {
    let before: LayerProbe = (probe-it $layer)
    if $before.ok {
        emit $"✅ ($layer.name) — ($before.detail)"
        return $before
    }
    if not $fix {
        emit $"✗ ($layer.name) — ($before.detail) · would: ($layer.hint)"
        return $before
    }
    emit $"🔧 ($layer.name) — ($before.detail) · repairing: ($layer.hint)"
    let r: record = (do -i { do $layer.repair } | complete)
    if $r.exit_code != 0 {
        let errText: string = (fold-stderr $r | str substring 0..200)
        emit $"   repair raised: ($errText)"
    }
    let after: LayerProbe = (probe-it $layer)
    let mark: string = (if $after.ok { "✅" } else { "✗" })
    emit $"($mark) ($layer.name) — ($after.detail)"
    $after
}

# ── the index + the receipts ──

def doc-stats []: nothing -> Prior {
    let q: record = (^docker exec -i $PG_CONTAINER psql -U $PG_USER -d $PG_DB -t -A -c "select count(*)::text || '|' || coalesce(to_char(max(updated_at), 'YYYY-MM-DD'), '-') from documents;" | complete)
    if $q.exit_code != 0 { return (none) }
    # the count|freshest parse rides lib/index-brain.nu (doc-stats-parse)
    doc-stats-parse $q.stdout
}

def index-legs []: nothing -> list<IndexLeg> {
    [
        {leg: "corpus.txt", args: ["index"]}
        {leg: "repos", args: ["index-repos"]}
    ]
}

def run-leg [leg: IndexLeg]: nothing -> LegResult {
    emit $"📚 indexing — ($leg.leg)…"
    let t0: datetime = (date now)
    let r: record = (do { ^$BIN ...$leg.args } | complete)
    let secs: int = ((((date now) - $t0) / 1sec) | into int)
    let ok: bool = ($r.exit_code == 0)
    let detail: string = (if $ok { "ok" } else { (fold-stderr $r | str substring 0..200) })
    let mark: string = (if $ok { "✅" } else { "✗" })
    emit $"($mark) index ($leg.leg) — ($secs)s ($detail)"
    {leg: $leg.leg, ok: $ok, exit: $r.exit_code, secs: $secs, detail: $detail}
}

def verify-rows []: nothing -> list<VerifyRow> {
    let q: record = (^$BIN query "nushell job recv timeout" --k 1 | complete)
    let m: record = (^$BIN memory search "kap functional design" --k 1 | complete)
    let b: record = (^$BIN bus status | complete)
    [
        {check: "rag query", ok: ($q.exit_code == 0), detail: (if $q.exit_code == 0 { "ok" } else { fold-stderr $q | str substring 0..120 })}
        {check: "memory search", ok: ($m.exit_code == 0), detail: (if $m.exit_code == 0 { "ok" } else { fold-stderr $m | str substring 0..120 })}
        {check: "bus status", ok: ($b.exit_code == 0), detail: (if $b.exit_code == 0 { "ok" } else { fold-stderr $b | str substring 0..120 })}
    ]
}

def main [--check]: nothing -> nothing {
    let fix: bool = (not $check)
    let mode: string = (if $fix { "FIX" } else { "CHECK (read-only)" })
    let stamp: string = (date now | format date '%Y-%m-%d %H:%M:%S')
    emit $"== index-brain ($stamp) — mode ($mode) =="

    # Baseline BEFORE any repair: the delta is the receipt.
    let before: Prior = (doc-stats)

    # Walk the ladder; the first dead layer blocks the rest (dependency order).
    mut blocked: string = ""
    mut dead: int = 0
    for layer in (layers) {
        if ($blocked != "") {
            emit $"⏭️  ($layer.name) — not attempted (blocked by ($blocked))"
            continue
        }
        let r: LayerProbe = (ensure $layer $fix)
        if not $r.ok {
            $blocked = $layer.name
            $dead = $dead + 1
        }
    }

    if ($blocked != "") {
        emit $"🛑 ladder blocked at ($blocked) — index legs skipped"
        exit 1
    }

    # The index legs: sequential on purpose (one DB, one embedder).
    mut legFailures: int = 0
    if $fix {
        for leg in (index-legs) {
            let r: LegResult = (run-leg $leg)
            if not $r.ok { $legFailures = $legFailures + 1 }
        }
    } else {
        emit "⏭️  index legs skipped in --check mode"
    }

    # The receipts: docs before → after, plus the three smoke calls.
    let after: Prior = (doc-stats)
    let delta: string = (delta-line $before $after)
    emit $"📄 documents: ($delta)"
    let checks: list<VerifyRow> = (verify-rows)
    mut verifyFailures: int = 0
    for c in $checks {
        let mark: string = (if $c.ok { "✅" } else { "✗" })
        emit $"($mark) ($c.check) — ($c.detail)"
        if not $c.ok { $verifyFailures = $verifyFailures + 1 }
    }

    if ($dead + $legFailures + $verifyFailures) > 0 {
        emit $"🛑 FAIL — ($dead) dead layer(s) · ($legFailures) failed index leg(s) · ($verifyFailures) failed smoke(s)"
        exit 1
    }
    emit "✅ brain rebuilt — ladder green, index fresh, smokes green"
}
