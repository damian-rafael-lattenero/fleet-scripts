# highlight.nu — terminal syntax highlighting.
#
# Gap: `nu-highlight` is nushell's only highlighter and it speaks only
# Nushell; `bat` ships no Nushell grammar. So .nu routes to `nu-highlight`
# (which follows $env.config.color_config) and every other language to
# `bat --theme=ansi` (the terminal palette, not a bundled theme).
# Verified on nu 0.117.0 with bat 0.26.1.

# Infer the highlight language: explicit override, else the lowercased
# path extension, else "". The precedence table (the mode-table law —
# the else-if chain died in the 22/11 self-audit): explicit first, then
# the extension, then the empty catch-all.
export def highlight-language [path?: path, explicit?: string]: nothing -> string {
    let rows: list<record<lang: string, when: closure>> = [
        {lang: ($explicit | default "" | str lowercase), when: {|_p: any| ($explicit | default "" | is-not-empty)}}
        {lang: ($path | default "" | path parse | get extension | default "" | str lowercase), when: {|_p: any| ($path | default "" | is-not-empty)}}
        {lang: "", when: {|_p: any| true}}
    ]
    ($rows | where {|row| do $row.when $path } | first | get lang)
}

# Highlight a string for the terminal; bat is required off-Nushell.
# An empty language means "no highlighter known": return the code unchanged.
# The renderer table (the mode-table law): nu/nushell -> nu-highlight,
# empty -> passthrough, catch-all -> bat (which gates its own absence).
export def highlight-text [language: string, code: string]: nothing -> string {
    let lang: string = $language | str lowercase
    let rows: list<record<when: closure, render: closure>> = [
        {when: {|_c: string| $lang in ["nu" "nushell"]}, render: {|_c: string| $code | nu-highlight}}
        {when: {|_c: string| ($lang | is-empty)}, render: {|_c: string| $code}}
        {when: {|_c: string| true}, render: {|_c: string|
            if (which bat | is-empty) {
                error make {msg: "hl: bat is required for non-Nushell languages (brew install bat)"}
            }
            $code | ^bat --plain --color=always --theme=ansi --language $lang
        }}
    ]
    let hit: record = ($rows | where {|row| do $row.when $code } | first)
    do $hit.render $code
}

# Highlight files, or the piped input when no paths are given.
export def hl [--language (-l): string, ...paths: path]: any -> string {
    if ($paths | is-empty) {
        let piped: any = $in
        # a literal null cannot be passed to an optional `path` param (0.117 parse check)
        let no_path: any = null
        highlight-text (highlight-language $no_path $language) $piped
    } else {
        $paths | each {|p: any|
            highlight-text (highlight-language $p) (open --raw $p)
        } | str join "\n"
    }
}

# Detect a structured text shape for terminal rendering: "json", "jsonl",
# "csv", "tsv", or "" when unknown. Conservative: prose and logs stay plain.
export def structured-output-kind [text: string]: nothing -> string {
    let trimmed: string = ($text | str trim)
    if ($trimmed | is-empty) { return "" }
    if (($trimmed | str starts-with "{") or ($trimmed | str starts-with "[")) {
        let is_json: bool = (try { $trimmed | from json; true } catch { false })
        if $is_json { return "json" }
    }

    let lines: list<string> = (
        $trimmed
        | lines
        | each {|line: any| $line | str trim }
        | where {|line: any| $line | is-not-empty }
    )
    if (($lines | length) >= 1) {
        let all_json: bool = ($lines | all {|line: any| (($line | str starts-with "{") or ($line | str starts-with "[")) and (try { $line | from json; true } catch { false }) })
        if $all_json { return "jsonl" }
    }
    if (($lines | length) >= 2) {
        let commas: list<int> = ($lines | each {|line: any| ($line | split row "," | length) - 1 })
        let first_comma: int = ($commas | first)
        if (($first_comma >= 1) and ($commas | all {|c: any| $c == $first_comma })) {
            return "csv"
        }
        let tabs: list<int> = ($lines | each {|line: any| ($line | split row (char tab) | length) - 1 })
        let first_tab: int = ($tabs | first)
        if (($first_tab >= 1) and ($tabs | all {|c: any| $c == $first_tab })) {
            return "tsv"
        }
    }
    ""
}

# Pretty-print structured text for display. JSON gets 2-space indentation;
# other kinds pass through (bat colors them).
export def structured-output-text [text: string, kind: string]: nothing -> string {
    if $kind == "json" {
        try { $text | from json | to json } catch { $text }
    } else {
        $text
    }
}

# ── Palette: color_config shapes -> SGR ───────────────────────────────
# The skeleton must be colored even when piped, but `ansi` cannot be used:
# in a non-TTY session it returns "" and its --escape form mangles style
# strings (measured 0.117.0). So a shape like "purple_bold" maps to its SGR
# here; unknown or hex shapes render unstyled instead of failing.

def lookup [table: record, key: string]: nothing -> any {
    try { $table | get $key } catch { null }
}

def palette [shape: string]: nothing -> string {
    if ($shape | is-empty) { return "" }
    try { $env.config.color_config | get $shape | to text } catch { "" }
}

# Map one color_config shape to an SGR sequence (attributes first, then the
# color, matching nu-highlight's own ordering).
export def shape-escape [shape: any]: nothing -> string {
    if not ((($shape | describe) | str starts-with "string")) { return "" }
    let words: list<string> = ($shape | split row "_" | where {|word: any| $word | is-not-empty })
    if ($words | is-empty) { return "" }
    let colors: record = {black: 30, red: 31, green: 32, yellow: 33, blue: 34, purple: 35, magenta: 35, cyan: 36, white: 37}
    let bright: record = {black: 90, red: 91, green: 92, yellow: 93, blue: 94, purple: 95, magenta: 95, cyan: 96, white: 97}
    let attrs: record = {bold: 1, dimmed: 2, dim: 2, italic: 3, underline: 4, blink: 5, reverse: 7}
    mut attr_codes: list<int> = []
    mut color_codes: list<int> = []
    mut light: bool = false
    for word in $words {
        if $word == "light" { $light = true; continue }
        let color: any = (if $light { lookup $bright $word } else { lookup $colors $word })
        if ($color | is-not-empty) {
            $color_codes = ($color_codes | append $color)
            $light = false
            continue
        }
        let attr: any = (lookup $attrs $word)
        if ($attr | is-not-empty) { $attr_codes = ($attr_codes | append $attr) }
    }
    let codes: list<int> = ($attr_codes | append $color_codes)
    if ($codes | is-empty) { return "" }
    $"\u{1b}[($codes | str join ';')m"
}

def styled [shape: string, text: string]: nothing -> string {
    let escape: string = (shape-escape (palette $shape))
    if ($escape | is-empty) { return $text }
    $escape + $text + "\u{1b}[0m"
}

# ── Display tree: one ADT, one catamorphism, many algebras ────────────
# Every Nushell value is classified ONCE into this sum type (tagged records):
#   {tag: "scalar", text, shape}     numbers, bools, null, dates, durations,
#                                    filesizes, binaries, ranges… as NUON text
#   {tag: "text",   text}            plain single-line string
#   {tag: "json",   text}            string holding embedded JSON / JSONL
#   {tag: "code",   text}            string holding Nu code
#   {tag: "lines",  text}            multi-line plain text
#   {tag: "record", fields}          product: list<{key: string, node: Tree}>
#   {tag: "list",   items}           recursion: list<Tree> (tables included)
# `classify-display` is the pure parser (parse once, don't re-probe), and
# `fold-tree` is the only eliminator: recursion and child folds live there,
# so render / expandable / any future query is an ALGEBRA (a record of
# closures passed as a value) instead of a new if-chain. Serializers escape
# strings by design and bat/shiki never look inside one, which is why the
# expansion has to happen at this layer.

const PAD: string = "  "

# Conservative Nu-code detector: a declaration head, an external head, or a
# pipeline that actually speaks Nu (a bare `a | b` of prose stays plain).
def looks-like-nu [text: string]: nothing -> bool {
    let trimmed: string = ($text | str trim)
    if ($trimmed | is-empty) { return false }
    let head: string = ($trimmed | split row " " | first)
    let declarations: list<string> = ["let" "mut" "def" "use" "alias" "source" "export" "if" "for" "while" "print"]
    let pipeline_words: list<string> = ["complete" "get " "lines" "where " "each " "select " "sort-by" "str " "to text" "to json" "to nuon" "from json" "into " "open " "save " "ignore" "print " "reduce" "update " "insert " "reject " "compact"]
    let is_declaration: bool = ($head in $declarations)
    let is_external: bool = ($head | str starts-with "^")
    let is_variable_pipeline: bool = (($trimmed | str contains '$') and ($trimmed | str contains " | "))
    let is_nu_pipeline: bool = (($trimmed | str contains " | ") and ($pipeline_words | any {|word: any| $trimmed | str contains $word }))
    $is_declaration or $is_external or $is_variable_pipeline or $is_nu_pipeline
}

# Prefix every line of a (possibly ANSI-colored) block.
def indent-lines [text: string, pad: string]: nothing -> string {
    $text | str trim --right | lines | each {|line: any| $pad + $line } | str join (char nl)
}

# Shift every line AFTER the first (an inline value's continuation lines).
def shift-continuation [text: string, prefix: string]: nothing -> string {
    let rows: list<string> = ($text | lines)
    if (($rows | length) <= 1) { return $text }
    ($rows | first) + (char nl) + ($rows | skip 1 | each {|line: any| $prefix + $line } | str join (char nl))
}

# Key style matches NUON: bare when identifier-like, quoted otherwise.
def render-key [key: string]: nothing -> string {
    if ($key =~ '^[A-Za-z_][A-Za-z0-9_]*$') { $key } else { $key | to nuon }
}

# ── The parser: value -> Tree (pure, total) ───────────────────────────

def classify-string [text: string]: nothing -> record {
    let kind: string = (structured-output-kind $text)
    if $kind == "json" or $kind == "jsonl" { return {tag: "json", text: $text} }
    if (looks-like-nu $text) { return {tag: "code", text: $text} }
    if ($text | str contains (char nl)) { return {tag: "lines", text: $text} }
    {tag: "text", text: $text}
}

# The palette shape for a scalar follows its type, so numbers, bools, dates
# and binaries each keep the color Nushell gives them.
def scalar-shape [description: string]: nothing -> string {
    if ($description | str starts-with "int") { return "shape_int" }
    if ($description | str starts-with "float") { return "shape_float" }
    if ($description | str starts-with "bool") { return "shape_bool" }
    if ($description | str starts-with "nothing") { return "shape_nothing" }
    if ($description | str starts-with "binary") { return "shape_binary" }
    if ($description | str starts-with "range") { return "shape_range" }
    if ($description | str starts-with "datetime") { return "shape_datetime" }
    "shape_literal"
}

# Scalar fallback is total: NUON for anything serializable, `describe` for
# values NUON cannot render (closures, custom values).
def classify-scalar [value: any]: nothing -> record {
    let description: string = ($value | describe)
    let shape: string = (scalar-shape $description)
    try {
        {tag: "scalar", text: ($value | to nuon), shape: $shape}
    } catch {
        {tag: "scalar", text: $description, shape: $shape}
    }
}

def classify-value [value: any]: nothing -> record {
    let description: string = ($value | describe)
    if ($description | str starts-with "record") {
        let fields: list<any> = ($value | columns | each {|key: any|
            {key: $key, node: (classify-value ($value | get $key))}
        })
        return {tag: "record", fields: $fields}
    }
    if ($description | str starts-with "list") or ($description | str starts-with "table") {
        return {tag: "list", items: ($value | each {|item: any| classify-value $item })}
    }
    if ($description | str starts-with "string") { return (classify-string $value) }
    classify-scalar $value
}

# Classify any value into the display tree (pure, total).
export def classify-display []: any -> record {
    let value: any = $in
    classify-value $value
}

# ── The eliminator: catamorphism over the Tree ────────────────────────
# algebra = one closure per constructor:
#   scalar/text/json/code/lines : |node| -> A
#   record                      : |fields: list<{key, node, value: A}>| -> A
#   list                        : |items: list<{node, value: A}>| -> A
# A leaf handler receives its whole node (tag, text, shape); a product
# handler receives each child's folded value plus the child node itself, so
# layout decisions stay in the algebra (a paramorphism by construction).
export def fold-tree [tree: record, algebra: record]: nothing -> any {
    let tag: string = $tree.tag
    if $tag == "record" {
        let fields: list<any> = ($tree.fields | each {|field: any|
            {key: $field.key, node: $field.node, value: (fold-tree $field.node $algebra)}
        })
        let handler: closure = ($algebra | get "record")
        return (do $handler $fields)
    }
    if $tag == "list" {
        let items: list<any> = ($tree.items | each {|item: any|
            {node: $item, value: (fold-tree $item $algebra)}
        })
        let handler: closure = ($algebra | get "list")
        return (do $handler $items)
    }
    let handler: closure = ($algebra | get $tag)
    do $handler $tree
}

# A leaf that renders as a block (its own lines): embedded JSON always, code
# and plain text only when they actually span multiple lines.
def block-node? [node: record]: nothing -> bool {
    if $node.tag == "json" { return true }
    if $node.tag in ["code" "lines"] { return ($node.text | str contains (char nl)) }
    false
}

# ── Algebra: render (relative layout, no pad; parents indent) ─────────

def render-algebra []: nothing -> record {
    {
        "scalar": {|node: any| styled $node.shape $node.text }
        "text": {|node: any| styled "shape_string" ($node.text | to nuon) }
        "json": {|node: any|
            let kind: string = (structured-output-kind $node.text)
            let language: string = (if $kind == "jsonl" { "json" } else { $kind })
            highlight-text $language (structured-output-text $node.text $kind)
        }
        "code": {|node: any| try { highlight-text "nu" $node.text } catch { $node.text } }
        "lines": {|node: any| $node.text | str trim --right }
        "record": {|fields: any|
            let open: string = (styled "shape_record" "{")
            let close: string = (styled "shape_record" "}")
            if ($fields | is-empty) { $open + $close } else {
                let body: list<string> = ($fields | each {|field: any|
                    let label: string = ($PAD + (styled "shape_string" (render-key $field.key)))
                    if (block-node? $field.node) {
                        $label + ":" + (char nl) + (indent-lines $field.value ($PAD + $PAD))
                    } else {
                        $label + ": " + (shift-continuation $field.value $PAD)
                    }
                })
                $open + (char nl) + ($body | str join (char nl)) + (char nl) + $close
            }
        }
        "list": {|items: any|
            let open: string = (styled "shape_record" "[")
            let close: string = (styled "shape_record" "]")
            if ($items | is-empty) { $open + $close } else {
                let body: list<string> = ($items | each {|item: any| (indent-lines $item.value $PAD) })
                $open + (char nl) + ($body | str join (char nl)) + (char nl) + $close
            }
        }
    }
}

# ── Algebra: does the tree carry a block leaf? (the `out` trigger) ────

def has-block-algebra []: nothing -> record {
    {
        "scalar": {|_node: any| false }
        "text": {|_node: any| false }
        "json": {|_node: any| true }
        "lines": {|_node: any| true }
        "code": {|node: any| ($node.text | str contains (char nl)) }
        "record": {|fields: any| ($fields | any {|field: any| $field.value }) }
        "list": {|items: any| ($items | any {|item: any| $item.value }) }
    }
}

# Does the value carry a string leaf that the renderer expands? Plain data
# keeps the palette-colored NUON/JSON view.
export def expandable-leaf? []: any -> bool {
    let value: any = $in
    fold-tree (classify-value $value) (has-block-algebra)
}

# Render any value for display, expanding structured string leaves.
export def render-expanded []: any -> string {
    let value: any = $in
    fold-tree (classify-value $value) (render-algebra)
}

# NUON is Nushell's own literal format: --pretty indents records and aligns
# table columns, and nu-highlight colors it as Nu code.
def print-nuon [value: any]: nothing -> nothing {
    $value | to nuon --pretty | nu-highlight | print
}

# The string-value lane (extracted so `out` stays a pure dispatch table).
def out-string [text: string, compact: bool]: nothing -> nothing {
    let kind: string = (structured-output-kind $text)
    if (not $compact) and ($kind == "json") {
        let parsed: any = (try { $text | from json } catch { $text })
        let tree: record = (classify-value $parsed)
        if (fold-tree $tree (has-block-algebra)) {
            print (fold-tree $tree (render-algebra))
            return
        }
    }
    if ($kind | is-empty) or ($kind in ["csv" "tsv"]) {
        print $text
    } else {
        let language: string = (if $kind == "jsonl" { "json" } else { $kind })
        highlight-text $language (structured-output-text $text $kind) | print
    }
}

# Terminal counterpart of the ZCode card renderer: structured strings are
# pretty-printed and colored with bat; tables/lists render with nu's table.
# CSV/TSV stay as-is (bat has no grammar for them). Values that carry a
# block leaf (embedded JSON, multi-line text, Nu code) render with the tree;
# --compact keeps the plain NUON/JSON view instead. The top dispatch is a
# PRIORITY TABLE (the mode-table law — the else-if chain died in the 22/11
# self-audit): string lane, --compact lane, structure catch-all.
export def out [--compact]: any -> nothing {
    let value: any = $in
    let description: string = ($value | describe)
    let rows: list<record<when: closure, render: closure>> = [
        {when: {|_v: any| ($description | str starts-with "string")}, render: {|v: any| out-string $v $compact}}
        {when: {|_v: any| $compact}, render: {|v: any| print-nuon $v}}
        {when: {|_v: any| true}, render: {|v: any|
            let tree: record = (classify-value $v)
            if (fold-tree $tree (has-block-algebra)) {
                print (fold-tree $tree (render-algebra))
            } else {
                print-nuon $v
            }
        }}
    ]
    let hit: record = ($rows | where {|row| do $row.when $value } | first)
    do $hit.render $value
}
