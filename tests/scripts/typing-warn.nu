# typing-warn.nu — the typing hook's ADVISORY path (the type-alias law).
# A NAMED alias is the fix and never warns — `type X = ...` and the exported
# `export type X = ...` alike (the exported form used to warn on every file
# that obeyed the law). An anonymous deep record in a signature warns, and the
# warn BUILDS: two prose parens inside its message once crashed the hook.
# The hook runs for real — the payload on stdin — so nothing touches ~/.zcode.
# covers: /Users/lattenero/Scripts/scripts/hooks/nushell-typing.nu
use std/assert
use /Users/lattenero/Scripts/nushell-fp/mods/proc.nu fold-stderr

const SELF: path = (path self)

# What a fired hook answers.
type Run = record<exit_code: int, stdout: string>

# One file the hook judges: what goes in, and whether the law must speak.
type Case = record<name: string, text: string, warns: bool>

let HUB: path = ($SELF | path expand | path dirname | path dirname | path dirname)
let HOOK: path = ($HUB | path join 'scripts' 'hooks' 'nushell-typing.nu')

# The shapes, SPLIT so this test file never carries a whole offending one
# (the live hooks judge a .nu file like any other).
let deep: string = ('record<a: int, b: string, c: bool>')

# Fire the typing hook over a Write of the given text.
def fire [hook: path, text: string]: nothing -> Run {
    let res: record = (do { {tool_name: Write, session_id: sess_typing_test, tool_input: {file_path: '/tmp/typing-case/sample.nu', content: $text}} | to json -r | ^$nu.current-exe --stdin $hook } | complete)
    {exit_code: $res.exit_code, stdout: ($res.stdout | str trim)}
}

let cases: list<Case> = [
    {name: 'a plain alias is the fix', text: ($'type Shape = ($deep)\nprint 1'), warns: false}
    {name: 'an exported alias is the fix too', text: ($'export type Shape = ($deep)\nprint 1'), warns: false}
    {name: 'an anonymous deep record in a signature warns', text: ($'def f [x: ($deep)]: nothing -> int { $x.a }'), warns: true}
]

for case in $cases {
    let run: Run = (fire $HOOK $case.text)
    assert equal $run.exit_code 0 $"($case.name): the hook advises, it never denies here"
    let spoke: bool = ($run.stdout | str contains 'TYPE-ALIAS LAW')
    assert equal $spoke $case.warns $"($case.name): warns = ($case.warns)"
    if $spoke {
        # the warn BUILDS: it is the hook contract's JSON, not a crash's prose
        assert equal ($run.stdout | from json | get hookSpecificOutput.hookEventName) 'PreToolUse' $"($case.name): the warn rides the hook contract"
    }
}

print $"scripts/typing-warn ok — ($cases | length) cases: named aliases stay silent, the anonymous one warns and builds"
