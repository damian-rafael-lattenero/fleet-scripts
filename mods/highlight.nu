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

# Terminal counterpart of the ZCode card renderer: structured strings are
# pretty-printed and colored with bat; tables/lists render with nu's table.
# CSV/TSV stay as-is (bat has no grammar for them).
export def out []: any -> nothing {
    let value: any = $in
    let description: string = ($value | describe)
    if ($description | str starts-with "string") {
        let text: string = $value
        let kind: string = (structured-output-kind $text)
        if ($kind | is-empty) or ($kind in ["csv" "tsv"]) {
            print $text
        } else {
            let language: string = (if $kind == "jsonl" { "json" } else { $kind })
            highlight-text $language (structured-output-text $text $kind) | print
        }
    } else {
        # NUON is Nushell's own literal format: --pretty indents records and
        # aligns table columns, and nu-highlight colors it as Nu code.
        $value | to nuon --pretty | nu-highlight | print
    }
}
