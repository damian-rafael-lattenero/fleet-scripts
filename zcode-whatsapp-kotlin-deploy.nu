#!/Users/lattenero/.local/bin/nu-nightly
# zcode-whatsapp-kotlin-deploy.nu — SOLO el bot Kotlin de WhatsApp
# (whatsdigest): build de Gradle (+ detekt + tests) → install → relanza el
# LaunchAgent → verificación propia. NUNCA toca el fork ni el bot Kotlin
# espejo de ZCode.
#
# El script canónico vive en el repo (scripts/deploy-daemon.nu); esto SOLO lo
# invoca. El bot de los grupos saluda al boot y el script verifica el heartbeat.
#
# Ley de oro: UN deploy por cambio. Si cambian el fork y/o el bot también,
# zcode-deploy-all lleva los tres.

const NU: string = "/Users/lattenero/.local/bin/nu-nightly"
const WHATSAPP_SCRIPT: string = "/Users/lattenero/Projects/whatsdigest-kt/scripts/deploy-daemon.nu"

def main []: nothing -> nothing {
    print $"🚀 (ansi cyan)Bot Kotlin WhatsApp: deploy-daemon(ansi reset) \(build + install + LaunchAgent + verificación\)"
    try {
        run-external $NU $WHATSAPP_SCRIPT
        print "✅ Bot Kotlin WhatsApp deployado — el bot de los grupos saluda al boot; log: ~/.zcode/bot-kotlin/logs/deploy-whatsapp.log"
    } catch { |err|
        print $"❌ deploy del Bot Kotlin de WhatsApp falló: ($err.msg)"
        exit 1
    }
}
