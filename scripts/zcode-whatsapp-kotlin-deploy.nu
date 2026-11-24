#!/Users/lattenero/.local/bin/nu-nightly
# zcode-whatsapp-kotlin-deploy.nu — the WhatsApp bot ONLY (whatsdigest):
# gradle build (+ detekt + tests) → install → LaunchAgent relaunch → its own
# check. It NEVER touches the fork or the ZCode mirror bot.
#
# The canonical script lives in the repo (scripts/deploy-daemon.nu); this
# wrapper ONLY invokes it. The groups bot greets on boot and the script
# verifies the heartbeat.
#
# Golden rule: ONE deploy per change. If the fork and/or the mirror bot
# changed too, zcode-deploy-all carries them together.

const NU: string = "/Users/lattenero/.local/bin/nu-nightly"
const WHATSAPP_SCRIPT: string = "/Users/lattenero/Projects/whatsdigest-kt/scripts/deploy-daemon.nu"

def main []: nothing -> nothing {
    print $"🚀 (ansi cyan)WhatsApp bot: deploy-daemon(ansi reset) \(build + install + LaunchAgent + check\)"
    try {
        run-external $NU $WHATSAPP_SCRIPT
        print "✅ WhatsApp bot deployed — the groups bot greets on boot; log: ~/.zcode/bot-kotlin/logs/deploy-whatsapp.log"
    } catch { |err|
        print $"❌ WhatsApp bot deploy failed: ($err.msg)"
        exit 1
    }
}
