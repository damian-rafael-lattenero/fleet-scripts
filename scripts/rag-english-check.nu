#!/opt/homebrew/bin/nu
# rag-english-check.nu — the language inventory of the brain's RAG store, and
# the gate that keeps it English (ADR-009; the twin word lists live in
# agent-brain's `English.kt` — a word added here is added there).
#
# Reads what the brain's database exports — one JSON object per line with the
# fields id, source, uri, bytes and sample (the first characters of the
# document) — and classifies every document by its stopwords:
#
#   spanish  eight or more Spanish stopwords and more of them than English ones
#   mixed    eight or more Spanish stopwords, but as many English ones or more
#   lean     three to seven Spanish stopwords and more of them than English ones
#            (code with a Spanish comment, a short note)
#   english  everything else with English prose in it
#   noprose  too few stopwords of either language to tell (config, data)
#
# Prints one row per source, one per area (repository plus two folders, only the
# areas holding something that is not English) and one per file extension (the
# same filter); writes every non-English document to --out as
# `language<TAB>uri`. Read-only: nothing is opened but the export.
#
# `--check` turns the report into the gate: exit 1 when any document is
# `spanish`, or when a PROSE file (md txt adoc rst) is `mixed` — the corpus
# law (ADR-009) forbids Spanish prose in the store; a code file carrying a
# Spanish comment is reported, never failed (rule 5: code is code).
#
# `--memories` judges memory rows instead of documents: one line of text needs
# one stopword to tell its language, not eight.
#
# Usage:
#   nu rag-english-check.nu /tmp/rag-docs.jsonl --out /tmp/rag-non-english.tsv
#   nu rag-english-check.nu /tmp/rag-docs.jsonl --check
# The export, run against the database container:
#   select row_to_json(t) from (select id, source, uri, length(content) as bytes,
#     left(content, 40000) as sample from documents order by id) t

const ES: string = '\b(que|del|las|los|para|con|por|una|como|mas|más|pero|sus|cuando|muy|sin|sobre|también|hasta|hay|donde|desde|durante|todos|contra|otros|ese|eso|este|esto|antes|algunos|unos|otro|otra|tanto|esa|estos|mucho|nada|muchos|cual|poco|algo|esta|cómo|qué|será|sera|fueron|tiene|tienen|puede|pueden|debe|deben|cada|entre|hacia|según|segun|así|asi|entonces|porque|aunque|luego|siempre|nunca|aquí|aqui)\b'

const EN: string = '\b(the|and|for|with|that|this|from|are|not|you|have|has|was|were|will|which|their|would|about|there|when|what|where|then|them|these|those|can|into|only|also|other|than|your|should|because|each|such|some|more|most|over|under|after|before|between|through|does|been|being)\b'

# The verdict for each value of the key: the four flags (es >= 8, es >= 3,
# en >= 3, es > en) read as one binary number. A table, not a chain of else-if.
const VERDICT: list<string> = ['noprose' 'noprose' 'english' 'english' 'english' 'lean' 'english' 'lean' 'mixed' 'spanish' 'mixed' 'spanish' 'mixed' 'spanish' 'mixed' 'spanish']

const HOME: string = '/Users/lattenero/Projects/'

type Doc = record<id: int, source: string, uri: string, bytes: int, sample: string>
type Judged = record<source: string, uri: string, bytes: int, lang: string, es: int, sample: string>
type Item = record<group: string, bytes: int, lang: string>
type Row = record<group: string, docs: int, mb: float, spanish: int, mixed: int, lean: int>

def count [text: string, pattern: string]: nothing -> int {
  ($text | split row -r $pattern | length) - 1
}

def language [sample: string, short: bool]: nothing -> string {
  let low: string = ($sample | str lowercase)
  let es: int = (count $low $ES)
  let en: int = (count $low $EN)
  # A document needs eight Spanish stopwords to count; a one-line memory (short) needs one.
  let heavy: int = (if $short { 1 } else { 8 })
  let some: int = (if $short { 1 } else { 3 })
  let floor: int = (if $short { 1 } else { 3 })
  let flags: list<bool> = [($es >= $heavy) ($es >= $some) ($en >= $floor) ($es > $en)]
  let bits: int = ($flags | into int | reduce --fold 0 {|bit, acc| ($acc * 2) + $bit })
  $VERDICT | get $bits
}

def cut [text: string, cap: int]: nothing -> string {
  if ($text | str length) > $cap { $text | str substring 0..($cap - 1) } else { $text }
}

def area-of [uri: string]: nothing -> string {
  let parts: list<string> = ($uri | str replace -a $HOME '' | split row /)
  $parts | first 3 | str join '/'
}

def extension-of [uri: string]: nothing -> string {
  let ext: any = ($uri | path parse | get extension?)
  if ($ext | is-empty) { 'none' } else { $ext }
}

const CODE: list<string> = ['kt' 'kts' 'java' 'py' 'nu' 'ts' 'sh']
type CodeRow = record<uri: string, es: int, en: int>

def comment-part [sample: string]: nothing -> string {
  $sample | lines | where {|l|
    let t: string = ($l | str trim)
    ($t | str starts-with '//') or ($t | str starts-with '*') or ($t | str starts-with '/*') or ($t | str starts-with '#')
  } | str join "\n"
}

# The Spanish that sits inside comment lines of a code file: tells a Spanish
# comment (to translate) from a Spanish string literal (the bot's own words).
def code-report [judged: list<Judged>]: nothing -> list<CodeRow> {
  $judged | where {|j| ($j.lang in ['mixed' 'lean']) and ((extension-of $j.uri) in $CODE) } | each {|j|
    let low: string = (comment-part $j.sample | str lowercase)
    {uri: (cut ($j.uri | str replace -a $HOME '') 100), es: (count $low $ES), en: (count $low $EN)}
  } | where {|r| $r.es > 0 } | sort-by es --reverse
}

def foreign [row: Row]: nothing -> bool {
  ($row.spanish + $row.mixed + $row.lean) > 0
}

def tally [items: list<Item>]: nothing -> list<Row> {
  $items | group-by --to-table group | each {|g|
    let mine: list<Item> = $g.items
    let size: int = ($mine | length)
    let bytes: int = ($mine | get bytes | math sum)
    let es: list<Item> = ($mine | where lang == 'spanish')
    let both: list<Item> = ($mine | where lang == 'mixed')
    let few: list<Item> = ($mine | where lang == 'lean')
    let mb: float = ($bytes | into float) / 1048576.0 | math round --precision 1
    {group: (cut $g.group 70), docs: $size, mb: $mb, spanish: ($es | length), mixed: ($both | length), lean: ($few | length)}
  } | sort-by docs --reverse
}

def main [docs: path, --out: path = '/tmp/rag-non-english.tsv', --check, --memories]: nothing -> nothing {
  let judged: list<Judged> = (open --raw $docs | lines | where {|l| not ($l | is-empty) } | each {|l|
    let d: Doc = ($l | from json)
    let low: string = ($d.sample | str lowercase)
    {source: $d.source, uri: $d.uri, bytes: $d.bytes, lang: (language $d.sample $memories), es: (count $low $ES), sample: $d.sample}
  })
  let bySource: list<Item> = ($judged | each {|j| {group: $j.source, bytes: $j.bytes, lang: $j.lang} })
  let byArea: list<Item> = ($judged | each {|j| {group: (area-of $j.uri), bytes: $j.bytes, lang: $j.lang} })
  let byExtension: list<Item> = ($judged | each {|j| {group: (extension-of $j.uri), bytes: $j.bytes, lang: $j.lang} })
  print '=== by source'
  print (tally $bySource)
  print '=== by area — only the areas holding something that is not English'
  print (tally $byArea | where {|r| foreign $r })
  print '=== by extension — the same filter'
  print (tally $byExtension | where {|r| foreign $r })
  print '=== Spanish inside comment lines — the code files above'
  print (code-report $judged | take 80)
  let listed: list<Judged> = ($judged | where lang in ['spanish' 'mixed' 'lean'])
  let linesOut: list<string> = ($listed | each {|j| $"($j.lang)\t($j.uri)" })
  ($linesOut | str join "\n") | save --force $out
  let es: int = ($judged | where lang == 'spanish' | length)
  let both: int = ($judged | where lang == 'mixed' | length)
  let few: int = ($judged | where lang == 'lean' | length)
  let none: int = ($judged | where lang == 'noprose' | length)
  let total: int = ($judged | length)
  let plain: int = ($total - $es - $both - $few - $none)
  print ($"($total) documents: spanish ($es), mixed ($both), lean ($few), english ($plain), noprose ($none). The non-English ones are listed in ($out).")
  if $check {
    const PROSE: list<string> = ['md' 'txt' 'adoc' 'rst']
    let proseMix: list<Judged> = ($judged | where {|j| ($j.lang == 'mixed') and ((extension-of $j.uri) in $PROSE) })
    # In memories mode a row quoting a Spanish product label (a button, a
    # command, a WhatsApp fragment) stays English: the gate only cuts Spanish
    # PROSE, which means the document floor's eight stopwords.
    let spanishProse: list<Judged> = ($judged | where {|j|
      if $memories { $j.es >= 8 } else { $j.lang == 'spanish' }
    })
    let failed: list<Judged> = ($spanishProse | append $proseMix)
    if ($failed | is-not-empty) {
      print ($"ENGLISH CHECK: FAIL - ($failed | length) documents break ADR-009:")
      $failed | each {|j| print $"  ($j.lang)  ($j.uri)" }
      exit 1
    }
    print 'ENGLISH CHECK: PASS - the store reads English.'
  }
}
