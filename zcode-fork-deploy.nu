#!/Users/lattenero/.local/bin/nu-nightly
# zcode-fork-deploy.nu — SOLO el fork de ZCode (la app, no un bot): build
# (~15 min, la app sigue viva), CIERRA ZCode solo, swap, reabre y anuncia.
# El arco completo, sin ⌘Q.
#
# El script canónico vive en el repo (scripts/build-install.nu --quit); esto
# SOLO lo invoca. El build habla sus tramos al Telegram (pnpm → bundle →
# build listo → cierre → Fork instalado). Ojo honesto: el cierre mata las
# sesiones de ZCode abiertas — guardá lo que esté a medio hacer.
#
# Ley de oro: UN deploy por cambio. Si solo cambió un bot, alcanza con
# zcode-bot-kotlin-deploy (el bot Kotlin espejo ZCode) o
# zcode-whatsapp-kotlin-deploy (el bot Kotlin de WhatsApp);
# si cambian varios, zcode-deploy-all.
#
# CHATTER BENIGNO del build (verificado 10/11 — NO es error, el build sigue):
#   · «Some chunks are larger than 500 kB» + PLUGIN_TIMINGS — límite web de
#     vite sobre el bundle del renderer; así lo tiene upstream, no se tapa.
#   · «duplicate dependency references» — enlaces del workspace pnpm, ruido.
#   · «platform-specific optional dependencies not bundled (@napi-rs/canvas-*»
#     — binaries de OTRAS plataformas; solo compilás mac-arm64.
#   · «@electron/rebuild already used by electron-builder» — el hint NO se
#     atiende: el postinstall del desktop (node-pty-rebuild.mjs) invoca ese
#     CLI directamente; quitarlo rompería el rebuild de node-pty.
#     (El «packageManager not detected» sí se arregló de fuente: campo
#     packageManager en packages/desktop/package.json, damian cde054a8.)

const NU: string = "/Users/lattenero/.local/bin/nu-nightly"
const FORK_SCRIPT: string = "/Users/lattenero/Projects/ZCode/scripts/build-install.nu"

def main []: nothing -> nothing {
    print $"🚀 (ansi cyan)fork: build-install --quit(ansi reset) \(build → cierra ZCode → swap → reabre\)"
    try {
        # The flag must ride as its OWN argument. 0.116.2-nightly does NOT
        # spread a list arg (`run-external $NU $SCRIPT ["--quit"]` reaches the
        # child as the literal string `["--quit"]` → `extra_positional`, build
        # never starts, measured 17/11) and it REJECTS a bare quoted flag
        # (`"--quit"` → rc 1). The spread operator is the form that works on
        # both 0.116.2-nightly and 0.117 (verified live on both).
        run-external $NU $FORK_SCRIPT ...["--quit"]
        print "✅ fork deployado — la app quedó reabierta; verificá con /status (canal UP)"
    } catch { |err|
        print $"❌ deploy del fork falló: ($err.msg)"
        exit 1
    }
}
