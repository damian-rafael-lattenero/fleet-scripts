# mods/telegram.nu — the deploy announce rung shared by every repo's deploy
# script (audit wave 6 dedupe: the SAME function lived copy-pasted in
# zcode-bot-kotlin/scripts/lib/deploy.nu, whatsdigest-kt/scripts/deploy-daemon.nu
# and ZCode/scripts/lib/fork-ops.nu).
#
# Silent BY DESIGN: a deploy never dies because the phone is off. A missing
# config, an empty token/chat or a dead network are all no-ops.
#
# THE FLAG, NOT THE NULL (the owner's 10/11 triple silence): the old shape
# passed `null` into a string-typed param and nu REJECTS that call AT PARSE —
# every deploy script died at import, before its first print, and launchd only
# showed exit 1 with a lost buffer. A long flag carries the parse mode; no null
# crosses any signature.

# Announce [text] to the owner's phone, HTML-formatted with --html.
export def send-telegram [text: string, --html]: nothing -> nothing {
    let cfg_path: string = ($nu.home-dir | path join ".zcode/telegram-remote.json")
    if not ($cfg_path | path exists) { return }
    try {
        let cfg: any = (open $cfg_path)
        let token: string = ($cfg.token? | default "")
        let chat: any = ($cfg.chat_id? | default "")
        if ($token | is-empty) or ($chat | is-empty) { return }
        let body: string = if $html {
            ({chat_id: $chat, text: $text, parse_mode: "HTML"} | to json)
        } else {
            ({chat_id: $chat, text: $text} | to json)
        }
        do -i {
            http post -m 10sec -t application/json $"https://api.telegram.org/bot($token)/sendMessage" $body -r | ignore
        }
    } catch {|_e| }
}
