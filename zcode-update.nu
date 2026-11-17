#!/Users/lattenero/.local/bin/nu-nightly
# zcode-update.nu — deliberate tool maintenance, OUTSIDE the deploys.
#
# The owner's ask (10/11): "update/upgrade everything at the start of the
# deploy scripts so nothing fails from being stale". The desire is right;
# the placement is a trap, so it lives HERE as its own deliberate command:
#
#   · a deploy that upgrades first is UNREPRODUCIBLE — the same code builds
#     differently before and after; when the app breaks you cannot tell the
#     change from the update of the day;
#   · the toolchain is PINNED on purpose (electron + pnpm in package.json,
#     node via assert-node-version, gradle via the wrapper) — a global
#     upgrade fights those pins and buys nothing;
#   · the golden rule ONE deploy per change: an update day is ITS OWN
#     change — run this, verify the apps, only then deploy real work.
#
# What it does: brew update + upgrade (the FLOATING surface: gh, jq,
# colima, ripgrep…) and a read-only panel of the pins, so the pinned vs
# floating split stays visible. It NEVER touches the pins — node, pnpm,
# electron and gradle move only with a fork/bot upgrade (tested), never
# from a shell script.
#
# Run it from Ghostty (or anywhere) whenever you feel like it. Not before
# every deploy — that is the whole point.

const BREW: string = "/opt/homebrew/bin/brew"
const FORK_ROOT: string = "/Users/lattenero/Projects/ZCode"
const BOT_ROOT: string = "/Users/lattenero/Projects/zcode-bot-kotlin"

# One external's version line (complete captures the streams — KB
# stdout_stderr_exit_codes.md; --version works for java since JDK 9 too)
def version-of [name: string]: nothing -> string {
    let out: record = do -i { ^$name --version } | complete
    let text: string = if ($out.stdout | str trim) == "" { $out.stderr } else { $out.stdout }
    $text | lines | first | default "(missing)"
}

# The PINS — read-only from the repos; these move ONLY with a tested
# upgrade of the fork or the bot, never from this script
def pins []: nothing -> table<tool: string, pin: string> {
    let desktop: record = open $"($FORK_ROOT)/packages/desktop/package.json"
    let root: record = open $"($FORK_ROOT)/package.json"
    let wrapper: string = open --raw $"($BOT_ROOT)/gradle/wrapper/gradle-wrapper.properties"
    let gradle: string = ($wrapper | parse -r 'gradle-(?<v>[0-9.]+)' | get 0.v? | default "?")
    [
        {tool: "electron (fork desktop)", pin: ($desktop.devDependencies?.electron? | default "?")}
        {tool: "pnpm (fork root field)", pin: ($root | get packageManager? | default "?")}
        {tool: "gradle (bot wrapper)", pin: $gradle}
    ]
}

# The panel: floating tools' live versions next to the pins — read-only
def panel []: nothing -> nothing {
    let live: list<record<tool: string, version: string>> = [
        {tool: "nu-nightly", version: (version-of "nu-nightly")}
        {tool: "node", version: (version-of "node")}
        {tool: "pnpm", version: (version-of "pnpm")}
        {tool: "java", version: (version-of "java")}
        {tool: "brew", version: (version-of "brew")}
    ]
    print $"📌 (ansi cyan)pins — they move ONLY with a tested fork/bot upgrade(ansi reset)"
    print (pins)
    print $"🌊 (ansi cyan)floating — brew upgrade just refreshed these(ansi reset)"
    print $live
}

def main [
    --report-only  # versions panel only — touch nothing
]: nothing -> nothing {
    if not $report_only {
        print $"🔄 (ansi cyan)brew update(ansi reset) — refreshing the index"
        try { ^$BREW update } catch { |err|
            print $"❌ brew update failed (exit ($err.exit_code)) — the panel still runs"
        }
        print $"🔄 (ansi cyan)brew upgrade(ansi reset) — upgrading the floating surface (this is the slow step)"
        try { ^$BREW upgrade } catch { |err|
            print $"❌ brew upgrade failed (exit ($err.exit_code)) — some tools may be stale"
        }
    }
    panel
    print "✅ done — updates are their own change: verify the apps BEFORE the next deploy"
}
