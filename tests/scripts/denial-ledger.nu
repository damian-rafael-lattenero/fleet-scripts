# denial-ledger.nu — the three denying hooks append ONE ledger line per deny
# (ts, session, hook, rule, language, target), and the deny never depends on
# the ledger: with the log path unwritable the hook still exits 2 with the
# same stderr. The hooks run for real — the payload on stdin, the ledger
# redirected with --log — so nothing touches ~/.zcode.
# covers: /Users/lattenero/Scripts/scripts/hooks/nushell-typing.nu
# covers: /Users/lattenero/Scripts/scripts/hooks/anti-pattern-lint.nu
# covers: /Users/lattenero/Scripts/scripts/hooks/nushell-law.nu
use std/assert
use /Users/lattenero/Scripts/nushell-fp/mods/proc.nu fold-stderr

const SELF: path = (path self)
const SID: string = 'ses_ledger_test'
const FILE: string = '/tmp/ledger-case/sample.nu'

let HUB: path = ($SELF | path expand | path dirname | path dirname | path dirname)

# One denial a hook must make: what goes in, and what must come out.
type Case = record<name: string, hook: string, payload: record, rule: string, language: string, target: string, says: string>

# One call a hook must let through.
type Clean = record<name: string, hook: string, payload: record>

# An Edit/Write payload for a .nu file.
def write-payload [tool: string, text: string]: nothing -> record {
    {tool_name: $tool, session_id: $SID, tool_input: {file_path: $FILE, old_string: 'a', new_string: $text, content: $text}}
}

# A Bash payload for the shell hook.
def bash-payload [command: string]: nothing -> record {
    {tool_name: 'Bash', session_id: $SID, tool_input: {command: $command}}
}

# Fire one hook for real: the payload on stdin, the ledger redirected.
def fire [hook: path, payload: record, log: path]: nothing -> record<exit_code: int, stderr: string> {
    let res: record = (do { $payload | to json -r | ^$nu.current-exe --stdin $hook --log $log } | complete)
    {exit_code: $res.exit_code, stderr: (fold-stderr $res)}
}

# The ledger's lines; an absent ledger is an empty one.
def ledger-lines [log: path]: nothing -> list<string> {
    if ($log | path exists) {
        open --raw $log | lines | where {|l| not ($l | is-empty) }
    } else {
        []
    }
}

# The fields of the ledger's last line.
def last-fields [log: path]: nothing -> list<string> {
    ledger-lines $log | last | split column "\t" | first | values
}

# The offending fragments, SPLIT so this test file never carries one whole
# (the live hooks judge a .nu file like any other).
let longZ: string = ('z' | fill --width 200 --character 'z')
let longCommand: string = ('sl' + 'eep 30sec; print 1' + (char nl) + "\t" + $longZ)

let cases: list<Case> = [
    {
        name: 'typing: hyphenated variable', hook: 'nushell-typing.nu'
        payload: (write-payload 'Edit' 'let my-var = 1')
        rule: 'hyphenated-variable', language: 'nu', target: $FILE
        says: 'hyphenated variables are INVALID'
    }
    {
        name: 'typing: blind sleep', hook: 'nushell-typing.nu'
        payload: (write-payload 'Edit' ('sl' + 'eep 20sec'))
        rule: 'blind-sleep', language: 'nu', target: $FILE
        says: ('blind sl' + 'eep 20sec FORBIDDEN')
    }
    {
        name: 'typing: def without IO signature', hook: 'nushell-typing.nu'
        payload: (write-payload 'Write' ('de' + 'f g [] { 2 }'))
        rule: 'def-without-signature', language: 'nu', target: $FILE
        says: 'defs WITHOUT an IO signature'
    }
    {
        name: 'typing: untyped params', hook: 'nushell-typing.nu'
        payload: (write-payload 'Edit' ('de' + 'f h [a b]: nothing -> nothing { }'))
        rule: 'untyped-params', language: 'nu', target: $FILE
        says: 'params WITHOUT a type'
    }
    {
        name: 'lint: else-if chain', hook: 'anti-pattern-lint.nu'
        payload: (write-payload 'Write' ('if $a { 1 } el' + 'se if $b { 2 } el' + 'se if $c { 3 } else { 4 }'))
        rule: 'dispatch-chain', language: 'nu', target: $FILE
        says: 'dispatch-chain'
    }
    {
        name: 'lint: orphaned branch', hook: 'anti-pattern-lint.nu'
        payload: (write-payload 'Write' ('if $a { 1 }' + (char nl) + '    or print 2'))
        rule: 'orphaned-branch', language: 'nu', target: $FILE
        says: 'anti-pattern orphaned-branch'
    }
    {
        name: 'lint: paren-wrapped let', hook: 'anti-pattern-lint.nu'
        payload: (write-payload 'Write' ('print (' + 'let x = 1) + 2'))
        rule: 'paren-let', language: 'nu', target: $FILE
        says: 'paren-wrapped let'
    }
    {
        name: 'law: blind sleep', hook: 'nushell-law.nu'
        payload: (bash-payload ('sl' + 'eep 15sec; print 1'))
        rule: 'blind-sleep', language: 'shell', target: ('sl' + 'eep 15sec; print 1')
        says: ('blind sl' + 'eep 15sec is FORBIDDEN')
    }
    {
        name: 'law: paren-wrapped let', hook: 'nushell-law.nu'
        payload: (bash-payload ('echo (le' + 't x = 1) + 2'))
        rule: 'paren-let', language: 'shell', target: ('echo (le' + 't x = 1) + 2')
        says: 'Paren-wrapped `let` law'
    }
    {
        name: 'law: long command', hook: 'nushell-law.nu'
        payload: (bash-payload $longCommand)
        rule: 'blind-sleep', language: 'shell', target: ''
        says: ('blind sl' + 'eep 30sec is FORBIDDEN')
    }
    {
        name: 'law: bash escape', hook: 'nushell-law.nu'
        payload: (bash-payload "bash -c 'echo hi'")
        rule: 'bash-escape', language: 'shell', target: "bash -c 'echo hi'"
        says: 'nu-only law'
    }
    {
        name: 'law: bad sleep unit', hook: 'nushell-law.nu'
        payload: (bash-payload ('sl' + 'eep 5s; print 1'))
        rule: 'bad-sleep-unit', language: 'shell', target: ('sl' + 'eep 5s; print 1')
        says: 'is NOT a duration unit'
    }
    {
        name: 'law: two inline lets', hook: 'nushell-law.nu'
        payload: (bash-payload 'let a = 1; let b = 2; print ($a + $b)')
        rule: 'two-lets', language: 'shell', target: 'let a = 1; let b = 2; print ($a + $b)'
        says: 'SECOND binding'
    }
    {
        name: 'law: bash redirect', hook: 'nushell-law.nu'
        payload: (bash-payload 'git status 2>/dev/null')
        rule: 'bash-redirect', language: 'shell', target: 'git status 2>/dev/null'
        says: 'Bash redirects do not exist here'
    }
    {
        name: 'law: literal dollar', hook: 'nushell-law.nu'
        payload: (bash-payload 'echo "$HOME/x"')
        rule: 'literal-dollar', language: 'shell', target: 'echo "$HOME/x"'
        says: 'keeps the dollar LITERAL'
    }
    {
        name: 'law: bash export', hook: 'nushell-law.nu'
        payload: (bash-payload 'export FOO=1')
        rule: 'bash-export', language: 'shell', target: 'export FOO=1'
        says: 'the environment is'
    }
    {
        name: 'law: bash exit code', hook: 'nushell-law.nu'
        payload: (bash-payload 'echo $?')
        rule: 'bash-exit-code', language: 'shell', target: 'echo $?'
        says: 'LAST_EXIT_CODE'
    }
    {
        name: 'law: sort -u', hook: 'nushell-law.nu'
        payload: (bash-payload 'ls | sort -u')
        rule: 'sort-uniq', language: 'shell', target: 'ls | sort -u'
        says: 'nushell dedupes'
    }
    {
        name: 'law: mkdir -p', hook: 'nushell-law.nu'
        payload: (bash-payload 'mkdir -p a/b')
        rule: 'mkdir-parents', language: 'shell', target: 'mkdir -p a/b'
        says: 'parents implicitly'
    }
    {
        name: 'law: for-do-done', hook: 'nushell-law.nu'
        payload: (bash-payload 'for x in 1 2 3; do echo $x; done')
        rule: 'for-do-done', language: 'shell', target: 'for x in 1 2 3; do echo $x; done'
        says: 'nushell is `for x in'
    }
    {
        name: 'law: then-fi', hook: 'nushell-law.nu'
        payload: (bash-payload 'if true; then echo y; fi')
        rule: 'then-fi', language: 'shell', target: 'if true; then echo y; fi'
        says: 'blocks, no keywords'
    }
    {
        name: 'law: bracket test', hook: 'nushell-law.nu'
        payload: (bash-payload "grep '[ -f x' file")
        rule: 'test-bracket', language: 'shell', target: "grep '[ -f x' file"
        says: 'nushell asks the value'
    }
    {
        name: 'law: caret builtin', hook: 'nushell-law.nu'
        payload: (bash-payload '^str trim')
        rule: 'caret-builtin', language: 'shell', target: '^str trim'
        says: 'EXTERNAL binaries only'
    }
]

let clean: list<Clean> = [
    {name: 'typing: a clean edit', hook: 'nushell-typing.nu', payload: (write-payload 'Edit' 'print "clean"')}
    {name: 'typing: not a .nu file', hook: 'nushell-typing.nu', payload: {tool_name: 'Edit', session_id: $SID, tool_input: {file_path: '/tmp/ledger-case/sample.md', new_string: 'let my-var = 1'}}}
    {name: 'lint: a clean write', hook: 'anti-pattern-lint.nu', payload: (write-payload 'Write' 'print "clean"')}
    {name: 'law: a clean command', hook: 'nushell-law.nu', payload: (bash-payload 'print "clean"')}
    {name: 'law: one let is legal', hook: 'nushell-law.nu', payload: (bash-payload 'let r = (ls | complete); print $r.exit_code')}
    {name: 'law: caret on an external is legal', hook: 'nushell-law.nu', payload: (bash-payload 'git -C /tmp status --short')}
    {name: 'law: sh -c mid-command is the containers business', hook: 'nushell-law.nu', payload: (bash-payload "docker exec -i agent-brain-pg sh -c 'echo hi'")}
    {name: 'law: a nu redirect is legal', hook: 'nushell-law.nu', payload: (bash-payload 'print hi e>| /dev/null')}
    {name: 'law: env interpolation is legal', hook: 'nushell-law.nu', payload: (bash-payload 'print $"($env.HOME)/x"')}
    {name: 'law: a dollar amount is legal', hook: 'nushell-law.nu', payload: (bash-payload 'print "costs $5"')}
    {name: 'law: sleep with a real unit below 10s is legal', hook: 'nushell-law.nu', payload: (bash-payload ('sl' + 'eep 2sec'))}
]

let tmp: path = ($"($env.TMPDIR? | default /tmp)/denial-ledger-(random uuid)")
mkdir $tmp
let ledger: path = ($tmp | path join 'denials.tsv')
# a regular file where the ledger's parent directory should be: mkdir fails
'not a directory' | save --force ($tmp | path join 'blocked')

for case in $cases {
    let hook: path = ($HUB | path join 'scripts' 'hooks' $case.hook)
    let before: int = (ledger-lines $ledger | length)
    let run: record<exit_code: int, stderr: string> = (fire $hook $case.payload $ledger)
    assert equal $run.exit_code 2 $"($case.name): the hook must deny"
    assert ($run.stderr | str contains $case.says) $"($case.name): the deny must still say why"
    assert equal ((ledger-lines $ledger | length)) ($before + 1) $"($case.name): exactly ONE ledger line per deny"

    let f: list<string> = (last-fields $ledger)
    assert equal ($f | length) 6 $"($case.name): ts, session, hook, rule, language, target"
    assert equal ($f | get 0 | into datetime | describe) 'datetime' $"($case.name): the ts must be an ISO timestamp"
    assert equal ($f | get 1) $SID $"($case.name): the session id rides the payload"
    assert equal ($f | get 2) ($case.hook | path parse | get stem) $"($case.name): the hook's own name"
    assert equal ($f | get 3) $case.rule $"($case.name): the rule name"
    assert equal ($f | get 4) $case.language $"($case.name): the language by extension, or shell"
    if ($case.target | is-empty) {
        # a long command is cut at 120 characters, and its tab and newline never break the row
        assert equal ($f | get 5 | str length) 120 $"($case.name): the target is cut at 120 characters"
        assert ($f | get 5 | str starts-with ('sl' + 'eep 30sec; print 1')) $"($case.name): the target is the command's head"
    } else {
        assert equal ($f | get 5) $case.target $"($case.name): the target is the file path, or the command"
    }
    assert equal ($f | get 5 | str contains "\t") false $"($case.name): no tab inside a field"

    # the deny never depends on the ledger
    let blocked: record<exit_code: int, stderr: string> = (fire $hook $case.payload ($tmp | path join 'blocked' 'denials.tsv'))
    assert equal $blocked.exit_code 2 $"($case.name): an unwritable ledger must not lift the deny"
    assert equal $blocked.stderr $run.stderr $"($case.name): an unwritable ledger must not change the reason"
    assert equal ((ledger-lines $ledger | length)) ($before + 1) $"($case.name): an unwritable ledger writes nothing"
}

for case in $clean {
    let before: int = (ledger-lines $ledger | length)
    let run: record<exit_code: int, stderr: string> = (fire ($HUB | path join 'scripts' 'hooks' $case.hook) $case.payload $ledger)
    assert equal $run.exit_code 0 $"($case.name): the hook must let it through"
    assert equal ((ledger-lines $ledger | length)) $before $"($case.name): an allow writes no ledger line"
}

# The event-bound warn (owner law 28/11): sleep-as-synchronization teaches
# without blocking; the bare <= 2 s race gap stays silent; a long sleep still
# denies. Warns never touch the ledger.
let sync: record<exit_code: int, stderr: string> = (fire ($HUB | path join 'scripts' 'hooks' 'nushell-law.nu') (bash-payload ('sl' + 'eep 2sec; print done')) $ledger)
assert equal $sync.exit_code 0 'the sync-sleep warn must not block'
assert ($sync.stderr | str contains 'event-bound') 'the warn must name the event-bound law'
let gap: record<exit_code: int, stderr: string> = (fire ($HUB | path join 'scripts' 'hooks' 'nushell-law.nu') (bash-payload ('sl' + 'eep 2sec')) $ledger)
assert equal $gap.exit_code 0 'the bare race gap must stay legal'
assert equal ($gap.stderr | str trim) '' 'the bare race gap must stay silent'
let ledgerBefore: int = (ledger-lines $ledger | length)
assert equal ((fire ($HUB | path join 'scripts' 'hooks' 'nushell-law.nu') (bash-payload ('sl' + 'eep 2sec; print done')) $ledger | get exit_code)) 0 'warns never deny'
assert equal ((ledger-lines $ledger | length)) $ledgerBefore 'a warn writes no ledger line'

rm -rf $tmp
print $"scripts/denial-ledger ok — ($cases | length) denials logged and still enforced, ($clean | length) allows unlogged"
