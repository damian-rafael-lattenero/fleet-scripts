# highlight.nu — terminal syntax highlighting.
#
# Gap: `nu-highlight` is nushell's only highlighter and it speaks only
# Nushell; `bat` ships no Nushell grammar. So .nu routes to `nu-highlight`
# (which follows $env.config.color_config) and every other language to
# `bat --theme=ansi` (the terminal palette, not a bundled theme).
# Verified on nu 0.117.0 with bat 0.26.1.

# Infer the highlight language: explicit override, else the lowercased
# path extension, else "".
export def highlight-language [path?: path, explicit?: string]: nothing -> string {
    if ($explicit | is-not-empty) {
        $explicit | str lowercase
    } else if ($path | is-not-empty) {
        $path | path parse | get extension | default "" | str lowercase
    } else {
        ""
    }
}

# Highlight a string for the terminal; bat is required off-Nushell.
# An empty language means "no highlighter known": return the code unchanged.
export def highlight-text [language: string, code: string]: nothing -> string {
    let lang: string = $language | str lowercase
    if $lang in ["nu" "nushell"] {
        $code | nu-highlight
    } else if ($lang | is-empty) {
        $code
    } else {
        if (which bat | is-empty) {
            error make {msg: "hl: bat is required for non-Nushell languages (brew install bat)"}
        }
        $code | ^bat --plain --color=always --theme=ansi --language $lang
    }
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
            highlight-text (highlight-language $p $language) (open --raw $p)
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

# ── Tree rendering: the whole-value view behind `out --expand` ────────
# Serializers escape strings by design (a JSON/NUON string is one line) and
# bat/shiki are syntax-level, so neither formats what is INSIDE a string
# value. These helpers walk the tree and classify each string leaf: embedded
# JSON is pretty-printed, multi-line text becomes real lines, Nu code is
# highlighted, and everything else keeps its quotes.

const PAD: string = "  "

# Conservative Nu-code detector: a declaration head, an external head, or a
# pipe combined with a variable. Prose and log lines stay plain.
def looks-like-nu [text: string]: nothing -> bool {
    let trimmed: string = ($text | str trim)
    if ($trimmed | is-empty) { return false }
    let head: string = ($trimmed | split row " " | first)
    let declarations: list<string> = ["let" "mut" "def" "use" "alias" "source" "export" "if" "for" "while" "print"]
    ($head in $declarations) or ($head | str starts-with "^") or (($trimmed | str contains '$') and ($trimmed | str contains " | "))
}

# Prefix every line of a (possibly ANSI-colored) block.
def indent-lines [text: string, pad: string]: nothing -> string {
    $text | str trim --right | lines | each {|line: any| $pad + $line } | str join (char nl)
}

# Key style matches NUON: bare when identifier-like, quoted otherwise.
def render-key [key: string]: nothing -> string {
    if ($key =~ '^[A-Za-z_][A-Za-z0-9_]*$') { $key } else { $key | to nuon }
}

# A string leaf that renders as a block: multi-line text or embedded JSON.
def block-string? [value: any]: nothing -> bool {
    let description: string = ($value | describe)
    if not ($description | str starts-with "string") { return false }
    ($value | str contains (char nl)) or ((structured-output-kind $value) == "json")
}

def render-string [text: string, pad: string]: nothing -> string {
    let kind: string = (structured-output-kind $text)
    if $kind == "json" or $kind == "jsonl" {
        let language: string = (if $kind == "jsonl" { "json" } else { $kind })
        let pretty: string = (structured-output-text $text $kind)
        return (indent-lines (highlight-text $language $pretty) $pad)
    }
    if ($text | str contains (char nl)) {
        let body: string = (
            if (looks-like-nu $text) {
                try { highlight-text "nu" $text } catch { $text }
            } else {
                $text
            }
        )
        return (indent-lines $body $pad)
    }
    if (looks-like-nu $text) {
        return (try { highlight-text "nu" $text } catch { $text })
    }
    $text | to nuon
}

def render-node [value: any, pad: string]: nothing -> string {
    let description: string = ($value | describe)
    if ($description | str starts-with "record") {
        let keys: list<string> = ($value | columns)
        if ($keys | is-empty) { return "{}" }
        let body: list<string> = ($keys | each {|key: any|
            let item: any = ($value | get $key)
            if (block-string? $item) {
                $pad + $PAD + (render-key $key) + ":" + (char nl) + (render-string $item ($pad + $PAD + $PAD))
            } else {
                $pad + $PAD + (render-key $key) + ": " + (render-node $item ($pad + $PAD))
            }
        })
        return ("{" + (char nl) + ($body | str join (char nl)) + (char nl) + $pad + "}")
    }
    if ($description | str starts-with "list") or ($description | str starts-with "table") {
        if (($value | length) == 0) { return "[]" }
        let body: list<string> = ($value | each {|item: any|
            if (block-string? $item) {
                (render-string $item ($pad + $PAD))
            } else {
                $pad + $PAD + (render-node $item ($pad + $PAD))
            }
        })
        return ("[" + (char nl) + ($body | str join (char nl)) + (char nl) + $pad + "]")
    }
    if ($description | str starts-with "string") {
        return (render-string $value $pad)
    }
    $value | to nuon
}

# Does the value carry a string leaf that `render-node` would expand? This is
# the trigger for `out`: plain data keeps the palette-colored NUON/JSON view.
export def expandable-leaf? []: any -> bool {
    let value: any = $in
    let description: string = ($value | describe)
    if ($description | str starts-with "string") { return (block-string? $value) }
    if ($description | str starts-with "record") {
        return ($value | columns | any {|key: any| ($value | get $key | expandable-leaf?) })
    }
    if ($description | str starts-with "list") or ($description | str starts-with "table") {
        return ($value | any {|item: any| ($item | expandable-leaf?) })
    }
    false
}

# Render any value for display, expanding structured string leaves.
export def render-expanded []: any -> string {
    let value: any = $in
    render-node $value ""
}

# Terminal counterpart of the ZCode card renderer: structured strings are
# pretty-printed and colored with bat; tables/lists render with nu's table.
# CSV/TSV stay as-is (bat has no grammar for them). Values that carry a
# structured string leaf (embedded JSON, multi-line text, Nu code) render with
# `render-expanded`; --compact keeps the plain NUON/JSON view instead.
export def out [--compact]: any -> nothing {
    let value: any = $in
    let description: string = ($value | describe)
    if ($description | str starts-with "string") {
        let text: string = $value
        let kind: string = (structured-output-kind $text)
        if not $compact and ($kind == "json") {
            let parsed: any = (try { $text | from json } catch { $text })
            if ($parsed | expandable-leaf?) {
                print (render-node $parsed "")
                return
            }
        }
        if ($kind | is-empty) or ($kind in ["csv" "tsv"]) {
            print $text
        } else {
            let language: string = (if $kind == "jsonl" { "json" } else { $kind })
            highlight-text $language (structured-output-text $text $kind) | print
        }
    } else if not $compact and ($value | expandable-leaf?) {
        print (render-node $value "")
    } else {
        # NUON is Nushell's own literal format: --pretty indents records and
        # aligns table columns, and nu-highlight colors it as Nu code.
        $value | to nuon --pretty | nu-highlight | print
    }
}
