# test_highlight.nu — palette routing and ANSI output for mods/highlight.nu.
use std/assert
use ../mods/highlight.nu *

const ESC: string = "\u{1b}"

# highlight-language: lowercased extension, explicit override, no extension
assert equal (highlight-language /tmp/sample.NU) "nu"
assert equal (highlight-language /tmp/sample.py) "py"
assert equal (highlight-language /tmp/sample) ""
assert equal (highlight-language /tmp/sample.nu "py") "py"
assert equal (highlight-language /tmp/sample.nu "PY") "py"
assert equal (highlight-language /tmp/sample.nu "") "nu"

# Nushell route: nu-highlight emits ANSI from the active palette
let nu_out: string = (highlight-text "nu" "let x = 1")
assert ($nu_out | str contains $ESC)

# .nu file through hl
let nu_file: path = "/tmp/nushell_fp_test_highlight.nu"
"let x = 1" | save -f $nu_file
let file_out: string = (hl $nu_file)
rm -f $nu_file
assert ($file_out | str contains $ESC)

# bat route: py emits ANSI
let py_out: string = (highlight-text "py" "def f(x):\n    return 1")
assert ($py_out | str contains $ESC)

# piped input with an explicit language
let piped_out: string = ("let x = 1" | hl -l nu)
assert ($piped_out | str contains $ESC)

# unknown language: no highlighter, no error, code passes through unchanged
assert equal (highlight-text "" "plain") "plain"
assert equal ("plain" | hl) "plain"

# structured-output-kind: JSON, JSONL, CSV, TSV, plain
assert equal (structured-output-kind '{"a":1}') "json"
assert equal (structured-output-kind '[1,2]') "json"
let jsonl_in: string = '{"a":1}' + (char nl) + '{"b":2}'
assert equal (structured-output-kind $jsonl_in) "jsonl"
let csv_in: string = "name,size" + (char nl) + "alpha,1"
assert equal (structured-output-kind $csv_in) "csv"
let tsv_in: string = "a" + (char tab) + "b" + (char nl) + "1" + (char tab) + "2"
assert equal (structured-output-kind $tsv_in) "tsv"
assert equal (structured-output-kind "plain text") ""

# structured-output-text: JSON pretty-printed, other kinds untouched
let pretty: string = (structured-output-text '{"a":1}' "json")
assert equal $pretty ('{' + (char nl) + '  "a": 1' + (char nl) + '}')
assert equal (structured-output-text "x: 1" "yaml") "x: 1"

# shape-escape: a color_config shape becomes SGR (attributes first, color last)
assert equal (shape-escape "green") "\u{1b}[32m"
assert equal (shape-escape "purple_bold") "\u{1b}[1;35m"
assert equal (shape-escape "light_cyan") "\u{1b}[96m"
assert equal (shape-escape "cyan_bold") "\u{1b}[1;36m"
assert equal (shape-escape "") ""
assert equal (shape-escape 42) ""

# render-expanded: layout is pinned (ANSI stripped) for a small tree
let tree: record = {user: {name: "ana", tags: ["x" "y"]}, ok: true}
assert equal ($tree | render-expanded | ansi strip) (
    '{' + (char nl) +
    '  user: {' + (char nl) +
    '    name: "ana"' + (char nl) +
    '    tags: [' + (char nl) +
    '      "x"' + (char nl) +
    '      "y"' + (char nl) +
    '    ]' + (char nl) +
    '  }' + (char nl) +
    '  ok: true' + (char nl) +
    '}'
)
assert equal ({} | render-expanded | ansi strip) "{}"
assert equal ([] | render-expanded | ansi strip) "[]"
assert (($tree | render-expanded) | str contains $ESC)

# multi-line text becomes real lines, not escaped ones
let block_text: string = ("line one" + (char nl) + "line two")
assert equal ({output: $block_text} | render-expanded | ansi strip) (
    '{' + (char nl) +
    '  output:' + (char nl) +
    '    line one' + (char nl) +
    '    line two' + (char nl) +
    '}'
)

# embedded JSON is pretty-printed (and bat-colored); ANSI splits tokens, so
# text assertions run on the stripped form
let json_leaf: string = '{"a":1,"b":[1,2]}'
let json_out: string = ({payload: $json_leaf} | render-expanded)
assert ($json_out | str contains $ESC)
let json_plain: string = ($json_out | ansi strip)
assert ($json_plain | str contains '"a": 1')
assert (($json_out | lines | length) > 4)
assert ($json_plain | str contains "payload:")

# Nu code leaves are highlighted, inline when single-line and as a block when not
assert (({command: "let x = 1"} | render-expanded) | str contains $ESC)
let code: string = ("let x = 1" + (char nl) + "print $x")
let code_out: string = ({command: $code} | render-expanded)
assert ($code_out | str contains $ESC)
assert equal ($code_out | lines | length) 5

# expandable-leaf?: the trigger for out — only structured string leaves count
assert (not ({a: "plain", b: 1} | expandable-leaf?))
assert (not ([{a: 1} {a: 2}] | expandable-leaf?))
assert (not ([] | expandable-leaf?))
assert ({a: ("x" + (char nl) + "y")} | expandable-leaf?)
assert ({a: {b: '{"k":1}'}} | expandable-leaf?)
assert ([{a: 1} {a: ("x" + (char nl) + "y")}] | expandable-leaf?)

# classify-display: every Nushell value kind lands in the display ADT
assert equal ('{"a":1}' | classify-display | get tag) "json"
assert equal ("let x = 1" | classify-display | get tag) "code"
assert equal (("plain" + (char nl) + "text") | classify-display | get tag) "lines"
assert equal ("plain" | classify-display | get tag) "text"
assert equal (42 | classify-display | get tag) "scalar"
assert equal (2.5 | classify-display | get tag) "scalar"
assert equal (true | classify-display | get tag) "scalar"
assert equal (null | classify-display | get tag) "scalar"
assert equal ({a: 1} | classify-display | get tag) "record"
assert equal ([1 2] | classify-display | get tag) "list"
assert equal ([[a]; [1] [2]] | classify-display | get tag) "list"

# nested values keep their own tags (parse once, recurse structurally)
let nested: record = ({a: {b: '{"k":1}'}} | classify-display)
assert equal ($nested.fields | first | get node.tag) "record"
assert equal ($nested.fields | first | get node.fields.0.node.tag) "json"
let nested_list: record = ([{a: "let x = 1"}] | classify-display)
assert equal ($nested_list.items | first | get tag) "record"
assert equal ($nested_list.items | first | get fields.0.node.tag) "code"

# fold-tree is generic: an independent algebra (leaf count) over the same tree
let count_algebra: record = {
    "scalar": {|_node: any| 1 }
    "text": {|_node: any| 1 }
    "json": {|_node: any| 1 }
    "code": {|_node: any| 1 }
    "lines": {|_node: any| 1 }
    "record": {|fields: any| if ($fields | is-empty) { 0 } else { $fields | get value | math sum } }
    "list": {|items: any| if ($items | is-empty) { 0 } else { $items | get value | math sum } }
}
let count_tree: record = ({a: {b: 1}, c: [1 2]} | classify-display)
assert equal (fold-tree $count_tree $count_algebra) 3
assert equal (fold-tree (5 | classify-display) $count_algebra) 1

# fixture: a real Bash card — the Nu pipeline command renders as CODE (raw
# quotes, no escapes) and the whole layout is pinned on the stripped form.
let card: record = {
    type: "tool"
    state: {
        input: {
            command: 'rg -n -F "KIND_TURN_FAILED = " /tmp/BusProducer.kt | complete | get stdout | lines | to text'
            description: "Locate the constants block"
        }
        output: '435:        const val KIND_TURN_FAILED = "turn.failed"'
    }
}
let card_out: string = ($card | render-expanded)
let card_plain: string = ($card_out | ansi strip)
assert ($card_out | str contains $ESC)
assert equal $card_plain (
    '{' + (char nl) +
    '  type: "tool"' + (char nl) +
    '  state: {' + (char nl) +
    '    input: {' + (char nl) +
    '      command: rg -n -F "KIND_TURN_FAILED = " /tmp/BusProducer.kt | complete | get stdout | lines | to text' + (char nl) +
    '      description: "Locate the constants block"' + (char nl) +
    '    }' + (char nl) +
    '    output: "435:        const val KIND_TURN_FAILED = \"turn.failed\""' + (char nl) +
    '  }' + (char nl) +
    '}'
)

# living fixture: a real multi-line Bash card — the owner's repo-branch
# script as the command and a 20-row pipe table as the output. The command
# must classify as code (colored, unquoted) and both blocks must expand into
# real lines, one level deeper than their keys.
const BRANCHES_CMD: string = r#'def branches [p: string]: nothing -> record {
  let d0 = (do { ^git -C $p symbolic-ref --short refs/remotes/origin/HEAD } | complete).stdout | str trim | str replace "origin/" ""
  let def = (if $d0 == "" { (do { ^git -C $p branch --show-current } | complete).stdout | str trim } else { $d0 })
  let local = (do { ^git -C $p branch --format "%(refname:short)|%(upstream:short)|%(upstream:track)|%(committerdate:short)" } | complete).stdout | lines | where {|l| $l != ""}
  {def: $def, local: $local}
}
[ZCode agent-brain bot cv eri haskell-rules-and-mcp kap kap-starter kotlin-kb nushell-fp pg-base rxjava-applicative-dsl sql-psi sqldelight whatsdigest-kt zcode-bot-kotlin zcode-diff-ask zcode-watchdog] | each {|r| let p = $"/Users/lattenero/Projects/($r)"; let d = (branches $p); $"=== ($r) default=($d.def)"; $d.local | each {|l| $"  ($l)"} } | flatten | str join "\n"'#

const BRANCHES_OUT: string = r#'damian|origin/damian||2026-11-18
main|origin/main||2026-10-20
master|origin/master||2026-11-18
master|origin/master||2026-11-02
master|origin/master||2026-11-13
main|origin/main||2026-10-26
master|origin/master||2026-11-13
master|origin/master||2026-11-17
master|origin/master||2026-11-16
master|origin/master||2026-11-17
master|origin/master||2026-11-18
master|||2026-11-18
develop|origin/develop||2026-11-10
main|origin/main||2026-11-15
damian|origin/damian||2026-11-16
master|origin/master||2026-11-18
master|origin/master||2026-11-18
wip/retry-f22|origin/wip/retry-f22||2026-11-02
master|origin/master||2026-11-18
master|origin/master||2026-11-13'#

let branches_card: record = {command: $BRANCHES_CMD, output: $BRANCHES_OUT}
assert equal (($branches_card | classify-display).fields.0.node.tag) "code"
let branches_render: string = ($branches_card | render-expanded)
let branches_plain: string = ($branches_render | ansi strip)
assert ($branches_render | str contains $ESC)
assert equal ($branches_plain | lines | length) 31
let command_block: list<string> = ($branches_plain | lines | skip 2 | first ($BRANCHES_CMD | lines | length))
let expected_command: list<string> = ($BRANCHES_CMD | lines | each {|line: any| "    " + $line })
assert equal $command_block $expected_command
let output_block: list<string> = ($branches_plain | lines | skip 10 | first ($BRANCHES_OUT | lines | length))
let expected_output: list<string> = ($BRANCHES_OUT | lines | each {|line: any| "    " + $line })
assert equal $output_block $expected_output

print "test_highlight ok"
