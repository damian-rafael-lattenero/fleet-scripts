# test_highlight.nu — palette routing and ANSI output for mods/highlight.nu.
use std/assert
use ../mods/highlight.nu *

const ESC: string = "\u{1b}"

# highlight-language: lowercased extension, explicit override, no extension
assert equal (highlight-language /tmp/sample.NU) "nu"
assert equal (highlight-language /tmp/sample.py) "py"
assert equal (highlight-language /tmp/sample) ""
assert equal (highlight-language /tmp/sample.nu "py") "py"
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

print "test_highlight ok"
