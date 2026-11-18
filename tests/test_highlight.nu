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

# render-expanded: layout is pinned for a small tree (quoted single-line leaf)
let tree: record = {user: {name: "ana", tags: ["x" "y"]}, ok: true}
assert equal ($tree | render-expanded) (
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
assert equal ({} | render-expanded) "{}"
assert equal ([] | render-expanded) "[]"

# multi-line text becomes real lines, not escaped ones
let block_text: string = ("line one" + (char nl) + "line two")
assert equal ({output: $block_text} | render-expanded) (
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

print "test_highlight ok"
