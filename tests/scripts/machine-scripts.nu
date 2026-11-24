# machine-scripts.nu — the scripts that live OUTSIDE any repo but still run on
# this Mac every session: the ZCode hooks (they guard every tool call) and the
# skill scripts (the phone's drills). They are machine state, so their tests
# live here — parse + shebang resolves + no stale pre-hub import.
# covers: /Users/lattenero/.zcode/hooks/*.nu
# covers: /Users/lattenero/.agents/skills/*/scripts/*.nu
use std/assert
use ../../lib/structural.nu *

let hooks: list<string> = (glob '/Users/lattenero/.zcode/hooks/*.nu')
let skills: list<string> = (glob '/Users/lattenero/.agents/skills/*/scripts/*.nu')
let files: list<string> = ($hooks | append $skills)
assert greater ($hooks | length) 10 "the hook family must be seen"
assert greater ($skills | length) 0 "the skill family must be seen"

let found: list<Finding> = (findings $files)
assert equal $found [] ($found | to json)

print $"machine scripts structural ok — ($hooks | length) hooks, ($skills | length) skill scripts"
