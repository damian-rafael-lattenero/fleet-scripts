# lib/zcode-update.nu — the pure core of zcode-update.nu: the version-line
# pick (stdout, else stderr, else the honest "(missing)"), the gradle pin
# parse and the pins panel from already-read files. The script keeps the
# brew and external calls.
export type ToolVersion = record<tool: string, version: string>

# One external's version line: --version writes to stdout for most tools and
# to stderr for some (java); empty everywhere answers "(missing)" — never an
# error that kills the panel.
export def version-line [stdout: string, stderr: string]: nothing -> string {
    let text: string = if ($stdout | str trim) == "" { $stderr } else { $stdout }
    $text | lines | get -o 0 | default "(missing)"
}

# The bot's gradle pin from gradle-wrapper.properties; unparseable -> "?"
# (an empty parse must land on the default — `get 0.v?` on no match RAISES
# access_empty_content, measured while testing: the panel died on a
# missing wrapper).
export def gradle-pin [wrapper: string]: nothing -> string {
    let found: list<record> = ($wrapper | parse -r 'gradle-(?<v>[0-9.]+)')
    if ($found | is-empty) { "?" } else { ($found | get 0.v? | default "?") }
}

# The PINS — from the repos' already-read files; these move ONLY with a
# tested upgrade of the fork or the bot, never from this script.
export def pins-from [desktop: record, root: record, wrapper: string]: nothing -> table<tool: string, pin: string> {
    [
        {tool: "electron (fork desktop)", pin: ($desktop.devDependencies?.electron? | default "?")}
        {tool: "pnpm (fork root field)", pin: ($root | get packageManager? | default "?")}
        {tool: "gradle (bot wrapper)", pin: (gradle-pin $wrapper)}
    ]
}
