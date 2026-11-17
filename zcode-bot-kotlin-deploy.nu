#!/Users/lattenero/.local/bin/nu-nightly
# zcode-bot-kotlin-deploy.nu — SOLO el bot Kotlin ESPEJO DE ZCODE: build de
# Gradle (+ detekt + tests) → install → relanza el LaunchAgent → verifica el
# heartbeat armado. Este bot lleva las sesiones de ZCode al teléfono.
#
# El script canónico vive en el repo (scripts/deploy-daemon.nu); este SOLO lo
# invoca. El deploy habla sus 4 fases al Telegram (🚀 1/4 building …
# 🔥 final) — el teléfono nunca queda a ciegas.
#
# Ley de oro: UN deploy por cambio. Cada corrida extra es otro build y otro
# reinicio — seis en 45 minutos fue la «mala conexión» del 4/11.
# Verificación final: /status desde el teléfono (canal UP).

const NU: string = "/Users/lattenero/.local/bin/nu-nightly"
const BOT_SCRIPT: string = "/Users/lattenero/Projects/zcode-bot-kotlin/scripts/deploy-daemon.nu"

def main []: nothing -> nothing {
    print $"🚀 (ansi cyan)Bot Kotlin espejo ZCode: deploy-daemon(ansi reset) \(build + install + LaunchAgent + verificación\)"
    try {
        run-external $NU $BOT_SCRIPT
        print "✅ Bot Kotlin espejo ZCode deployado — verificá con /status desde el teléfono (canal UP)"
    } catch { |err|
        print $"❌ deploy del Bot Kotlin espejo ZCode falló: ($err.msg)"
        exit 1
    }
}
