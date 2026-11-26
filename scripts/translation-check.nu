# Receipt of a translation: compares a translated note with the version a git ref
# still holds and lists every change the translation never should have made.
#
#   headings   the same number of headings at every level
#   fenced     the code of the fenced blocks, identical and in the same order
#              (a comment inside a fence is prose, on its own line or after code)
#   inline     the inline code spans outside the fences, identical and in order
#              (a span that is only a comment, or the comment after the code, is prose)
#   numbers    the same numbers outside code (versions, dates, counts)
#   links      the same link targets; every anchor link still resolves — from
#              this note and from every note of the folder that links into it
#   english    the prose of every line that was already English is still there,
#              byte for byte (code and link targets masked, the verified tag
#              may change spelling, an anchor may be renamed; a line is read as
#              Spanish by its stopwords, its function words or its accents). A
#              line the rule misreads is declared by its number in --declared,
#              and the PASS line counts it.
#   language   no line of the result reads as Spanish — in prose or in a code
#              comment, inside a fence or inside an inline span — nor the whole
#
# Usage: nu translation-check.nu <translated.md> [--base master] [--dir <folder>] [--declared <file>]
# The folder defaults to the file's parent; links resolve against it. The
# declared file holds one line number of the ORIGINAL per line. Exit 1 when
# there is a finding.

const ES: string = '\b(que|del|las|los|para|con|por|una|como|mas|más|pero|sus|cuando|muy|sin|sobre|también|hasta|hay|donde|desde|durante|todos|contra|otros|ese|eso|este|esto|antes|algunos|unos|otro|otra|tanto|esa|estos|mucho|nada|muchos|cual|poco|algo|esta|cómo|qué|será|sera|fueron|tiene|tienen|puede|pueden|debe|deben|cada|entre|hacia|según|segun|así|asi|entonces|porque|aunque|luego|siempre|nunca|aquí|aqui)\b'

# Any trace of Spanish on a line, beyond the stopwords: the short function words
# a stopword list cannot hold without catching English too (de, la, el...), the
# letters English never writes, and the adverbs in -mente. Generous on purpose —
# a false marker only lifts the protection of one line, a missed one would pin
# Spanish as English.
const MARK: string = '(\b(de|la|el|en|es|y|un|al|se|lo|le|les|ni|fue|son|ha|han|si|ya|mi|tu|te|nos|mas|sin|con|por|para|que|del|las|los|una|como|más|pero|sus|cuando|muy|sobre|también|hasta|hay|donde|desde|todos|contra|otros|ese|eso|este|esto|antes|algunos|unos|otro|otra|tanto|esa|estos|mucho|nada|muchos|cual|poco|algo|esta|cómo|qué|será|sera|fueron|tiene|tienen|puede|pueden|debe|deben|cada|entre|hacia|según|segun|así|asi|entonces|porque|aunque|luego|siempre|nunca|aquí|aqui)\b|[áéíóúñ¿¡]|\b\p{L}+mente\b)'

# The function words that alone betray a Spanish line (a comment of four words
# has no stopword of the list above): none of them is a word English writes —
# not even inside "et al.", which a bibliography carries on every other line.
const FUNCTION: string = '\b(de|la|el|se|lo|le|les|ni|fue|han|tu|te|nos|durante|través|vez|sin|con|por|para|que|del|las|los|una|como|más|pero|sus|cuando|muy|hasta|hay|donde|desde|cada|entre|hacia|según|porque|aunque|luego|siempre|nunca)\b'

const EN: string = '\b(the|and|for|with|that|this|from|are|not|you|have|has|was|were|will|which|their|would|about|there|when|what|where|then|them|these|those|can|into|only|also|other|than|your|should|because|each|such|some|more|most|over|under|after|before|between|through|does|been|being)\b'

type Walk = record<fence: bool, prose: list<string>, fenced: list<string>, block: list<string>, comments: list<string>>
type Text = record<prose: list<string>, fenced: list<string>, inline: list<string>, comments: list<string>>
type Numbered = record<n: int, text: string>
type Link = record<file: string, anchor: string>
type Finding = record<rule: string, detail: string>

def count [text: string, pattern: string]: nothing -> int {
  ($text | split row -r $pattern | length) - 1
}

def cut [text: string, cap: int]: nothing -> string {
  if ($text | str length) > $cap { $text | str substring 0..($cap - 1) } else { $text }
}

# What may legitimately differ between two versions of a line: the target of
# a link (an anchor is renamed with its heading) and the spelling of the
# verified tag (a Spanish tag becomes an English one).
def mask [text: string]: nothing -> string {
  $text | str replace -a -r '\]\([^)]*\)' '](link)' | str replace -a '[verificado ' '[verified ' | str replace -a '<versión>' '<version>'
}

def collapse [text: string]: nothing -> string {
  $text | str replace -a -r '\s+' ' ' | str trim
}

# A literal backtick is written between runs of two or more: by Markdown's own
# rule such a span is not code of one backtick, and reading it as one flips
# the parity of every line after it. It becomes one word, on both versions.
def literal-backticks [text: string]: nothing -> string {
  $text | str replace -a -r '(`{2,})[^`]*(?:`(?!`)[^`]*)*?\1(?![`])' 'CODE'
}

# The prose of a line: every inline code span gone. The literal backticks are
# folded first, or the span of a single backtick would read them wrong.
def plain-of [text: string]: nothing -> string {
  let folded: string = (literal-backticks $text)
  $folded | str replace -a -r '`[^`]*`' ''
}

# The inline code spans of a text, outside their backticks.
def spans-of [text: string]: nothing -> list<string> {
  literal-backticks $text | split row '`' | enumerate | where {|t| ($t.index mod 2) == 1 } | get item
}

# A comment as a whole line of code writes it.
def comment? [text: string]: nothing -> bool {
  let t: string = ($text | str trim)
  ($t | str starts-with '//') or ($t | str starts-with '/*') or ($t | str starts-with '(*') or ($t | str starts-with '#') or ($t | str starts-with '*') or ($t =~ '^--\s')
}

# A comment as the head of an inline code span writes it.
def comment-head? [text: string]: nothing -> bool {
  let t: string = ($text | str trim)
  ($t | str starts-with '//') or ($t | str starts-with '/*') or ($t | str starts-with '(*') or ($t | str starts-with '# ') or ($t =~ '^--\s')
}

# Where a trailing comment starts on a line of code; -1 when there is none.
def comment-at [text: string]: nothing -> int {
  let marks: list<string> = [' //' ' /*' ' (*' ' # ' ' -- ']
  let cuts: list<int> = ($marks | each {|m| $text | str index-of $m } | where $it >= 0)
  if ($cuts | is-empty) { -1 } else { $cuts | math min }
}

# The code of a line of code: what stands before a trailing comment.
def code-part [text: string]: nothing -> string {
  let at: int = (comment-at $text)
  if $at < 0 { $text } else { $text | str substring 0..($at - 1) | str trim }
}

# The comment that trails code on the same line; empty when there is none. The
# cut is the comment's own position, so an indented line keeps its code out.
def comment-tail [text: string]: nothing -> string {
  let at: int = (comment-at $text)
  if $at < 0 { '' } else { $text | str substring $at.. | str trim }
}

# The prose an inline span carries: itself when it is only a comment, its
# trailing comment otherwise.
def note-of [span: string]: nothing -> string {
  if (comment-head? $span) { $span } else { comment-tail $span }
}

# One line of the walk, six cases as rows of a table. A fence edge opens or
# closes the fence; inside a fence a comment line goes to the comments and
# leaves an empty row in the block, a line of code keeps its code in the block
# and gives its trailing comment to the comments; outside a fence every line is
# prose.
def step [line: string, acc: Walk]: nothing -> Walk {
  let edge: int = (if ($line | str trim | str starts-with '```') { 2 } else { 0 })
  let inside: int = (if $acc.fence { 1 } else { 0 })
  let rows: list<Walk> = [
    {fence: false, prose: ($acc.prose | append $line), fenced: $acc.fenced, block: $acc.block, comments: $acc.comments}
    {fence: true, prose: $acc.prose, fenced: $acc.fenced, block: ($acc.block | append $line), comments: $acc.comments}
    {fence: true, prose: $acc.prose, fenced: $acc.fenced, block: [], comments: $acc.comments}
    {fence: false, prose: $acc.prose, fenced: ($acc.fenced | append ($acc.block | str join "\n")), block: [], comments: $acc.comments}
    {fence: true, prose: $acc.prose, fenced: $acc.fenced, block: ($acc.block | append ''), comments: ($acc.comments | append $line)}
    {fence: true, prose: $acc.prose, fenced: $acc.fenced, block: ($acc.block | append (code-part $line)), comments: ($acc.comments | append (comment-tail $line))}
  ]
  let pick: int = (if ($edge == 0 and $inside == 1 and (comment? $line)) { 4 } else { $edge + $inside })
  let pick: int = (if ($edge == 0 and $inside == 1 and (not (comment? $line)) and (not ((comment-tail $line) | is-empty))) { 5 } else { $pick })
  $rows | get $pick
}

def split-text [text: string]: nothing -> Text {
  let walked: Walk = ($text | lines | reduce --fold {fence: false, prose: [], fenced: [], block: [], comments: []} {|line, acc| step $line $acc })
  let open: list<string> = ($walked.fenced | append ($walked.block | str join "\n"))
  let fenced: list<string> = (if $walked.fence { $open } else { $walked.fenced })
  let spans: list<string> = ($walked.prose | each {|l| mask $l } | spans-of ($in | str join "\n"))
  let inline: list<string> = ($spans | where {|s| not (comment-head? $s) } | each {|s| code-part $s })
  let notes: list<string> = ($walked.prose | each {|l| spans-of $l | each {|s| note-of $s } | where {|n| not ($n | is-empty) } } | flatten)
  {prose: $walked.prose, fenced: $fenced, inline: $inline, comments: ($walked.comments | append $notes)}
}

# The lines outside the fences, each with its number in the original.
def numbered [text: string]: nothing -> list<Numbered> {
  $text | lines | enumerate | reduce --fold {fence: false, kept: []} {|t, acc|
    let edge: bool = ($t.item | str trim | str starts-with '```')
    let row: list<Numbered> = (if ($acc.fence or $edge) { [] } else { [{n: ($t.index + 1), text: $t.item}] })
    {fence: ($acc.fence xor $edge), kept: ($acc.kept | append $row)}
  } | get kept
}

def heading-lines [prose: list<string>]: nothing -> list<string> {
  $prose | where {|l| $l =~ '^#{1,6} ' }
}

def headings [prose: list<string>]: nothing -> list<int> {
  let marks: list<int> = (heading-lines $prose | each {|l| $l | str replace -r '^(#+) .*$' '$1' | str length })
  [1 2 3 4 5 6] | each {|level| $marks | where $it == $level | length }
}

# The GitHub slug of every heading: lowercase, punctuation gone, spaces to hyphens.
def slugs [prose: list<string>]: nothing -> list<string> {
  heading-lines $prose | each {|l|
    $l | str replace -r '^#+ ' '' | str lowercase | str replace -a -r '[^\p{L}\p{N}\s_-]' '' | str replace -a -r '\s' '-'
  }
}

def numbers [prose: list<string>]: nothing -> list<string> {
  let clean: string = ($prose | each {|l| plain-of $l } | str join "\n")
  $clean | parse -r '(?P<n>[0-9]+(?:[.,:/][0-9]+)*)' | get n | sort
}

def links [prose: list<string>]: nothing -> list<Link> {
  $prose | str join "\n" | parse -r '\[[^\]]*\]\((?P<target>[^)\s]+)\)' | get target | each {|t|
    {file: ($t | split row '#' | first), anchor: ($t | split row '#' | skip 1 | str join '#')}
  }
}

# The file every link points at, in order. Anchors are not compared: a heading
# that is translated renames its anchor, and the two resolution rules below
# are what keep those links honest.
def link-files [prose: list<string>]: nothing -> list<string> {
  links $prose | get file
}

# A line the translation must leave alone: its prose is English by its words,
# with no trace of Spanish.
def english? [line: string]: nothing -> bool {
  let stripped: string = (plain-of $line | str lowercase)
  (count $stripped $EN) >= 1 and (count $stripped $ES) == 0 and not ($stripped =~ $MARK)
}

# The words of a line the language rules read: its prose and the comments its
# inline code carries; the code itself is none of their business.
def words-of [line: string]: nothing -> string {
  let notes: list<string> = (spans-of $line | each {|s| note-of $s } | where {|n| not ($n | is-empty) })
  $"(plain-of $line) ($notes | str join ' ')" | str lowercase
}

# A line that still reads as Spanish: a stopword and no English, three that
# outnumber the English ones, or a function word on a line without English.
def spanish? [line: string]: nothing -> bool {
  let words: string = (words-of $line)
  let es: int = (count $words $ES)
  let en: int = (count $words $EN)
  ($es >= 1 and $en == 0) or ($es >= 3 and $es > $en) or (($words =~ $FUNCTION) and $en == 0)
}

def first-gap [before: list<string>, after: list<string>]: nothing -> string {
  let n: int = ([($before | length) ($after | length)] | math min)
  let diff: list<int> = (0..<$n | where {|i| (($before | get $i) != ($after | get $i)) })
  if ($diff | is-empty) {
    $"lengths ($before | length) and ($after | length)"
  } else {
    let i: int = ($diff | first)
    $"item ($i): (cut ($before | get $i) 70) -> (cut ($after | get $i) 70)"
  }
}

def only-in [mine: list<string>, theirs: list<string>]: nothing -> list<string> {
  $mine | where {|x| not ($theirs | any {|y| $y == $x }) } | uniq | first 8
}

# One rule: no finding when it holds, its finding when it does not.
def rule [holds: bool, name: string, detail: string]: nothing -> list<Finding> {
  if $holds { [] } else { [{rule: $name, detail: $detail}] }
}

def resolved [link: Link, self: path, folder: path]: nothing -> list<string> {
  let target: path = (if ($link.file | is-empty) { $self } else { $folder | path join $link.file })
  if not ($target | path exists) { [] } else {
    let known: list<string> = (slugs (split-text (open --raw $target)).prose)
    if ($known | any {|s| $s == $link.anchor }) { [] } else { [$"($link.file)#($link.anchor)"] }
  }
}

def broken-anchors [prose: list<string>, self: path, folder: path]: nothing -> list<string> {
  links $prose | where {|l| not ($l.anchor | is-empty) and not ($l.file =~ '^https?://') } | each {|l| resolved $l $self $folder } | flatten
}

# Every note of the folder that links into this one must still find its heading.
def stale-incoming [prose: list<string>, self: path, folder: path]: nothing -> list<string> {
  let mine: list<string> = (slugs $prose)
  let name: string = ($self | path basename)
  let others: list<string> = (^git -C $folder ls-files '*.md' | lines | where {|p| $p != $name })
  $others | each {|p|
    let theirs: list<Link> = (links (split-text (open --raw ($folder | path join $p))).prose)
    $theirs | where {|l| ($l.file | path basename) == $name and not ($l.anchor | is-empty) and not ($mine | any {|s| $s == $l.anchor }) } | each {|l| $"($p) -> #($l.anchor)" }
  } | flatten
}

def findings [before: Text, after: Text, self: path, folder: path, beforeText: string, declared: list<int>]: nothing -> list<Finding> {
  let allLines: list<string> = ($after.prose | append $after.comments)
  let low: string = ($allLines | str join "\n" | str lowercase)
  let es: int = (count $low $ES)
  let en: int = (count $low $EN)
  let afterPlain: list<string> = ($after.prose | each {|l| collapse (mask (plain-of $l)) })
  let protectedLines: list<Numbered> = (numbered $beforeText | where {|row| (english? $row.text) and not ($declared | any {|d| $d == $row.n }) })
  let singles: list<list<Finding>> = [
    (rule ((headings $before.prose) == (headings $after.prose)) 'headings' $"per level (headings $before.prose) -> (headings $after.prose)")
    (rule ($before.fenced == $after.fenced) 'fenced' (first-gap $before.fenced $after.fenced))
    (rule ($before.inline == $after.inline) 'inline' (first-gap $before.inline $after.inline))
    (rule ((numbers $before.prose) == (numbers $after.prose)) 'numbers' $"lost (only-in (numbers $before.prose) (numbers $after.prose)); gained (only-in (numbers $after.prose) (numbers $before.prose))")
    (rule ((link-files $before.prose) == (link-files $after.prose)) 'links' (first-gap (link-files $before.prose) (link-files $after.prose)))
    (rule (not ($es >= 8 and $es > $en)) 'language' $"the result reads as Spanish: ($es) Spanish and ($en) English stopwords")
  ]
  let many: list<list<Finding>> = [
    (broken-anchors $after.prose $self $folder | each {|a| {rule: 'links', detail: $"anchor no longer resolves: ($a)"} })
    (stale-incoming $after.prose $self $folder | each {|a| {rule: 'links', detail: $"a note links to a heading that is gone: ($a)"} })
    ($protectedLines | where {|row| not ($afterPlain | any {|a| $a == (collapse (mask (plain-of $row.text))) }) } | each {|row| {rule: 'english', detail: $"L($row.n) an English line changed or vanished: (cut $row.text 90)"} })
    ($allLines | where {|l| spanish? $l } | each {|l| {rule: 'language', detail: $"a Spanish line remains: (cut $l 90)"} })
  ]
  $singles | append $many | flatten
}

def main [file: path, --base: string = 'master', --dir: path, --declared: path]: nothing -> nothing {
  let folder: path = (if ($dir | is-empty) { $file | path dirname } else { $dir })
  let rel: string = ($file | path relative-to $folder | into string)
  let beforeText: string = (^git -C $folder show $"($base):($rel)")
  let afterText: string = (open --raw $file)
  let declared: list<int> = (if ($declared | is-empty) { [] } else { open --raw $declared | lines | where {|l| not ($l | is-empty) } | each {|l| $l | str trim | into int } })
  let text: Text = (split-text $afterText)
  let found: list<Finding> = (findings (split-text $beforeText) $text $file $folder $beforeText $declared)
  let name: string = ($file | path basename)
  if ($found | is-empty) {
    let notes: int = (^git -C $folder ls-files '*.md' | lines | length)
    let h: int = (headings $text.prose | math sum)
    let f: int = ($text.fenced | length)
    let i: int = ($text.inline | length)
    let k: int = (link-files $text.prose | length)
    print ($"PASS ($name) - headings ($h) - fenced ($f) - inline ($i) - links ($k) - ($notes) notes scanned for incoming links - declared Spanish by the translator: ($declared | length)")
  } else {
    $found | each {|f| print ($"FAIL ($name) - ($f.rule): ($f.detail)") }
    exit 1
  }
}
