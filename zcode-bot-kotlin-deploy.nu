#!/Users/lattenero/.local/bin/nu-nightly
# zcode-bot-kotlin-deploy.nu — the ZCode MIRROR bot ONLY: gradle build
# (+ detekt + tests) → install → LaunchAgent relaunch → heartbeat check.
# This bot carries the ZCode sessions to the phone.
#
# The canonical script lives in the repo (scripts/deploy-daemon.nu); this
# wrapper ONLY invokes it. The deploy speaks its 4 phases to Telegram
# (🚀 1/4 building … 🔥 final) — the phone is never blind.
#
# Golden rule: ONE deploy per change. Every extra run is another build and
# another restart — six in 45 minutes was the 4/11 "bad connection".
# Final verification: /status from the phone (channel UP).

const NU: string = "/Users/lattenero/.local/bin/nu-nightly"
const BOT_SCRIPT: string = "/Users/lattenero/Projects/zcode-bot-kotlin/scripts/deploy-daemon.nu"

def main []: nothing -> nothing {
    print $"🚀 (ansi cyan)ZCode mirror bot: deploy-daemon(ansi reset) \(build + install + LaunchAgent + heartbeat\)"
    try {
        run-external $NU $BOT_SCRIPT
        print "✅ ZCode mirror bot deployed — verify with /status from the phone (channel UP)"
    } catch { |err|
        print $"❌ ZCode mirror bot deploy failed: ($err.msg)"
        exit 1
    }
}
