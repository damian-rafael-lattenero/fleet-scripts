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
