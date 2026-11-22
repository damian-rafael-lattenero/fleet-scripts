#!/Users/lattenero/.local/bin/nu-nightly
# zcode-fork-deploy.nu — the ZCode fork ONLY (the app, not a bot): build
# (~15 min, the app stays alive), CLOSES ZCode itself, swaps, reopens,
# announces. The full arc, no ⌘Q.
#
# The canonical script lives in the repo (scripts/build-install.nu --quit);
# this wrapper ONLY invokes it. The build speaks its legs to Telegram
# (pnpm → bundle → build ready → close → Fork installed). Honest warning:
# the close kills the open ZCode sessions — save anything mid-flight.
#
# Golden rule: ONE deploy per change. If only a bot changed, it is enough
# with zcode-bot-kotlin-deploy (the ZCode mirror bot) or
# zcode-whatsapp-kotlin-deploy (the WhatsApp bot); if several changed,
# zcode-deploy-all.
#
# BENIGN BUILD CHATTER (verified 10/11 — NOT an error, the build goes on):
#   · "Some chunks are larger than 500 kB" + PLUGIN_TIMINGS — vite's web
#     limit on the renderer bundle; upstream ships it the same way, unmuted.
#   · "duplicate dependency references" — pnpm workspace links, noise.
#   · "platform-specific optional dependencies not bundled (@napi-rs/canvas-*"
#     — binaries of OTHER platforms; you only build mac-arm64.
#   · "@electron/rebuild already used by electron-builder" — do NOT act on
#     the hint: the desktop postinstall (node-pty-rebuild.mjs) invokes that
#     CLI directly; removing it would break the node-pty rebuild.
#     (The "packageManager not detected" one WAS fixed at the source: the
#     packageManager field in packages/desktop/package.json, damian cde054a8.)

const NU: string = "/Users/lattenero/.local/bin/nu-nightly"
const FORK_SCRIPT: string = "/Users/lattenero/Projects/ZCode/scripts/build-install.nu"

def main []: nothing -> nothing {
    print $"🚀 (ansi cyan)fork: build-install --quit(ansi reset) \(build → closes ZCode → swap → reopens\)"
    try {
        # The flag must ride as its OWN argument. 0.116.2-nightly does NOT
        # spread a list arg (`run-external $NU $SCRIPT ["--quit"]` reaches the
        # child as the literal string `["--quit"]` → `extra_positional`, build
        # never starts, measured 17/11) and it REJECTS a bare quoted flag
        # (`"--quit"` → rc 1). The spread operator is the form that works on
        # both 0.116.2-nightly and 0.117 (verified live on both).
        run-external $NU $FORK_SCRIPT ...["--quit"]
        print "✅ fork deployed — the app reopened; verify with /status (channel UP)"
    } catch { |err|
        print $"❌ fork deploy failed: ($err.msg)"
        exit 1
    }
}
