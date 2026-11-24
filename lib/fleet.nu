# fleet.nu core — THE hub's verb table, pure: the caller hands in the file
# list (the script globs scripts/*.nu at its edge), so every def here answers
# from its arguments alone.
#
# One Command per verb. Discovery is the file list itself (verb = file stem);
# the only explicit rows are the five deploy verbs the owner types from
# memory plus healthcheck, which lives in the skills tree.
#
# resolve is TOTAL: it answers 0 or 1 row. The decision to refuse an unknown
# verb belongs to the edge (main), never to the table.

export type Command = record<verb: string, script: string, kind: string>

# healthcheck is the fleet-healthcheck skill's script (the 11-leg battery the
# phone's /fleet_healthcheck also runs) — one copy, not a second script.
export def aliases [root: path, healthcheck: path]: nothing -> list<Command> {
    let dir: path = ($root | path join 'scripts')
    [
        {verb: 'deploy-all', script: ($dir | path join 'zcode-deploy-all.nu' | into string), kind: 'alias'}
        {verb: 'deploy-brain', script: ($dir | path join 'zcode-brain-deploy.nu' | into string), kind: 'alias'}
        {verb: 'deploy-fork', script: ($dir | path join 'zcode-fork-deploy.nu' | into string), kind: 'alias'}
        {verb: 'deploy-bot', script: ($dir | path join 'zcode-bot-kotlin-deploy.nu' | into string), kind: 'alias'}
        {verb: 'deploy-whatsapp', script: ($dir | path join 'zcode-whatsapp-kotlin-deploy.nu' | into string), kind: 'alias'}
        {verb: 'healthcheck', script: ($healthcheck | into string), kind: 'alias'}
    ]
}

# The door itself is not a verb.
export def verbs [files: list<string>]: nothing -> list<Command> {
    $files
    | where {|p| ($p | path basename) != 'fleet.nu'}
    | each {|p| {verb: ($p | path parse | get stem), script: $p, kind: 'script'}}
}

export def verb-table [alias_rows: list<Command>, file_rows: list<Command>]: nothing -> list<Command> {
    ($alias_rows | append $file_rows | sort-by verb)
}

export def resolve [verb: string, table: list<Command>]: nothing -> list<Command> {
    $table | where {|c| $c.verb == $verb}
}

# ── the listing: what a verb TAKES and WHAT IT IS ─────────────────────────
# Both answers come from the script's own SOURCE TEXT (string in, string out):
# the table is generated from the file that runs, so there is no hand-kept
# argument list to drift from the signature.

export type Param = record<depth: int, quote: string, parts: list<string>, cur: string>
export type Scan = record<depth: int, quote: string, out: string, done: bool>

def in-quote [c: string, acc: Scan]: nothing -> Scan {
    if $c == $acc.quote {
        {depth: $acc.depth, quote: '', out: ($acc.out + $c), done: false}
    } else {
        {depth: $acc.depth, quote: $acc.quote, out: ($acc.out + $c), done: false}
    }
}

# One character of the bracket scan: the OUTER [ ] are dropped, nested ones
# kept (a list default like `= ['a']` must not close the signature).
def scan-step [c: string, acc: Scan]: nothing -> Scan {
    if $acc.done { return $acc }
    if ($acc.quote | is-not-empty) { return (in-quote $c $acc) }
    if ($c == "'" or $c == '"') { return {depth: $acc.depth, quote: $c, out: ($acc.out + $c), done: false} }
    if $c == '[' {
        let out: string = (if $acc.depth == 0 { '' } else { $acc.out + $c })
        return {depth: ($acc.depth + 1), quote: '', out: $out, done: false}
    }
    if $c == ']' {
        let depth: int = ($acc.depth - 1)
        if $depth == 0 { return {depth: 0, quote: '', out: $acc.out, done: true} }
        return {depth: $depth, quote: '', out: ($acc.out + $c), done: false}
    }
    if $acc.depth == 0 { return $acc }
    {depth: $acc.depth, quote: '', out: ($acc.out + $c), done: false}
}

# The text INSIDE the first [...] of the given source (the def main signature).
export def bracket-body [text: string]: nothing -> string {
    let scanned: Scan = ($text | split chars | reduce --fold {depth: 0, quote: '', out: '', done: false} {|c, acc| scan-step $c $acc})
    $scanned.out
}

def param-step [c: string, acc: Param]: nothing -> Param {
    if ($acc.quote | is-not-empty) {
        if $c == $acc.quote { return {depth: $acc.depth, quote: '', parts: $acc.parts, cur: ($acc.cur + $c)} }
        return {depth: $acc.depth, quote: $acc.quote, parts: $acc.parts, cur: ($acc.cur + $c)}
    }
    if ($c == "'" or $c == '"') { return {depth: $acc.depth, quote: $c, parts: $acc.parts, cur: ($acc.cur + $c)} }
    if ($c in ['<', '(', '[', '{']) { return {depth: ($acc.depth + 1), quote: '', parts: $acc.parts, cur: ($acc.cur + $c)} }
    if ($c in ['>', ')', ']', '}']) { return {depth: ($acc.depth - 1), quote: '', parts: $acc.parts, cur: ($acc.cur + $c)} }
    if ($c == ',' and $acc.depth == 0) { return {depth: 0, quote: '', parts: ($acc.parts | append ($acc.cur | str trim)), cur: ''} }
    if ($c == (char nl) and $acc.depth == 0) { return {depth: 0, quote: '', parts: ($acc.parts | append ($acc.cur | str trim)), cur: ''} }
    {depth: $acc.depth, quote: '', parts: $acc.parts, cur: ($acc.cur + $c)}
}

# Split a signature body on its TOP-LEVEL commas (record<..>, list<..>,
# defaults and quoted text never split).
export def split-params [body: string]: nothing -> list<string> {
    let st: Param = ($body | split chars | reduce --fold {depth: 0, quote: '', parts: [], cur: ''} {|c, acc| param-step $c $acc})
    ($st.parts | append $st.cur | each {|p| $p | str trim} | where {|p| $p | is-not-empty})
}

# The short type of a declaration: `--k: int = 5` -> int, `--fix` -> ''.
# The type is the FIRST word after the colon, so a trailing default of any
# shape (`= 5`, `= ['a']`, `= "x"`) never leaks into the label.
def type-of [decl: string]: nothing -> string {
    if not ($decl | str contains ':') { return '' }
    let after: string = ($decl | str replace --regex '^[^:]*:\s*' '')
    if ($after | is-empty) { return '' }
    ($after | split row ' ' | first | str trim)
}

# One parameter as the table shows it: flags keep their --name, positionals are
# quoted (optional in brackets, rest with the ...), and a typed one carries
# <type>.
export def render-param [token: string]: nothing -> string {
    let decl: string = ($token | str replace --regex '\s+=' '' | str replace --regex '=.*$' '')
    let name: string = (if ($decl | str contains ':') { $decl | str replace --regex ':.*$' '' } else { $decl })
    let ty: string = (type-of $decl)
    let typed: string = (if ($ty | is-empty) { '' } else { ' <' + $ty + '>' })
    if ($name | str starts-with '--') { return ($name + $typed) }
    if ($name | str starts-with '...') { return ($name + $typed) }
    if ($name | str ends-with '?') { return ('[' + ($name | str replace --regex '\?$' '') + ']' + $typed) }
    ('"' + $name + '"' + $typed)
}

# Every parameter of the script's `def main`, in order, as one line. The
# signature's own `# comments` are stripped FIRST: they carry apostrophes and
# parentheses that would poison the bracket/quote scan (measured 24/11 — the
# scan ran past the closing bracket and swallowed the whole file).
export def arguments-of [src: string]: nothing -> string {
    let lines: list<string> = ($src | lines)
    let hits: list<int> = ($lines | enumerate | where {|it| $it.item =~ 'def (--wrapped )?main\s*\['} | get index)
    if ($hits | is-empty) { return '-' }
    let head: string = (
        $lines
        | skip ($hits | first)
        | each {|l| $l | str replace --regex '\s+#.*$' ''}
        | str join (char nl)
    )
    let open: int = ($head | str index-of '[')
    if $open < 0 { return '-' }
    let body: string = (bracket-body ($head | str substring $open..))
    let labels: list<string> = (split-params $body | each {|p| render-param $p} | where {|l| $l | is-not-empty})
    if ($labels | is-empty) { return '-' }
    ($labels | str join ' · ')
}

# The header's prose paragraph starting at line N: consecutive comment lines,
# joined (a description cut at the first line reads like a telegram —
# "the ergonomics layer over the" — so the whole paragraph rides). No clipping:
# `commands` shows full doc comments, and this table is its twin.
def paragraph [lines: list<string>, start: int]: nothing -> string {
    let window: list<string> = ($lines | skip $start | take 4)
    let parts: list<string> = ($window | where {|l| $l | str starts-with '#'} | each {|l| $l | str replace --regex '^#+\s*' ''})
    let joined: string = ($parts | str join ' ')
    ($joined | str replace --regex '^\S+\.nu [—-] ' '')
}

# The script's own one-liner: the header's `<name>.nu — ...` paragraph, or the
# first comment paragraph when the header does not use the convention.
export def description-of [src: string]: nothing -> string {
    let lines: list<string> = ($src | lines)
    let tagged: list<int> = ($lines | enumerate | where {|it| $it.item =~ '^# \S+\.nu [—-] '} | get index)
    if not ($tagged | is-empty) {
        return (paragraph $lines ($tagged | first))
    }
    let plain: list<int> = ($lines | enumerate | where {|it| ($it.item | str starts-with '# ') and ($it.item | str length) > 3} | get index)
    if ($plain | is-empty) { return '-' }
    (paragraph $lines ($plain | first))
}
