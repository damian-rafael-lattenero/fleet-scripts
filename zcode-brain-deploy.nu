#!/opt/homebrew/bin/nu
# zcode-brain-deploy.nu — brain (agent-brain) ONLY: build (installDist +
# detekt) -> LaunchAgent restart -> verify /ready. The canonical script
# lives in the repo (scripts/deploy-brain.nu); this wrapper ONLY invokes it.
#
# Brief /brain + memory outage during the restart: the ZCode brain-mcp
# plugin reconnects on its own. Final verification: /ready 200 + health-check
# 8 layers (nu ~/Projects/agent-brain/scripts/health-check.nu).

const NU: string = "/opt/homebrew/bin/nu"
const BRAIN_SCRIPT: string = "/Users/lattenero/Projects/agent-brain/scripts/deploy-brain.nu"

def main []: nothing -> nothing {
    print $"🚀 (ansi cyan)Agent-brain: deploy-brain(ansi reset) \(build + restart + /ready check\)"
    try {
        run-external $NU $BRAIN_SCRIPT
        print "✅ agent-brain deployed — /ready 200; run health-check (8 layers) for the full verdict"
    } catch { |err|
        print $"❌ agent-brain deploy failed: ($err.msg)"
        exit 1
    }
}
