#!/opt/homebrew/bin/nu
# rag-english-check.nu — the inventory classifies the store's export by its
# stopwords (spanish / mixed / lean / english / noprose), and --check is the
# ADR-009 gate: exit 1 on a `spanish` document or a `mixed` PROSE file, never
# on a code file's stray Spanish comment. The child runs under `complete` so
# its exit code and output are values, never inherited streams.
# covers: /Users/lattenero/Scripts/scripts/rag-english-check.nu

const SCRIPT: string = '/Users/lattenero/Scripts/scripts/rag-english-check.nu'
const FIXTURE: string = '/tmp/rag-english-check-fixture.jsonl'

# One row of the fixture, as the export line the script reads.
def row [uri: string, sample: string]: nothing -> string {
  {id: 1, source: 'fixture', uri: $uri, bytes: ($sample | str length), sample: $sample} | to json -r
}

const ES_TEXT: string = 'qué es este documento y por qué las cosas que tiene no están aquí del resto para con una como más pero muy sin sobre también hasta todos'
const EN_TEXT: string = 'the quick brown agent writes documents about types and functions because that is what this store keeps under its source trees for every row'
const MIXED_TEXT: string = 'este documento mezcla los dos idiomas del store que con una como más pero muy sin sobre también the and for with that this from are not you have has was were will which their would'

def write-fixture [rows: list<string>]: nothing -> nothing {
  $rows | str join "\n" | save --force $FIXTURE
}

def main []: nothing -> nothing {
  # The fixture: one row per verdict the gate cares about.
  write-fixture [
    (row '/x/kb/docs/en.md' $EN_TEXT)
    (row '/x/kb/docs/es.md' $ES_TEXT)
    (row '/x/kb/docs/mixed.md' $MIXED_TEXT)
    (row '/x/kb/src/Mixed.kt' $MIXED_TEXT)
    (row '/x/kb/config.json' '{"a": 1}')
  ]

  # Report mode: the summary line names all the verdicts.
  let report: string = (nu $SCRIPT $FIXTURE --out /tmp/rag-english-check-out.tsv | complete | get stdout)
  let summary: string = ($report | lines | where {|l| $l =~ 'documents: spanish' } | first)
  assert ($summary =~ 'spanish 1') 'exactly one spanish document'
  assert ($summary =~ 'mixed 2') 'two mixed documents (the md and the kt)'
  assert ($summary =~ 'english 1') 'one english document'
  assert ($summary =~ 'noprose 1') 'one noprose document'

  # Check mode: the spanish md fails the gate.
  let red: any = (nu $SCRIPT $FIXTURE --check --out /tmp/rag-english-check-out.tsv | complete)
  assert ($red.exit_code == 1) 'check exits 1 on a spanish document'
  assert ($red.stdout =~ 'ENGLISH CHECK: FAIL') 'the failure names the law'

  # Only a code file carrying Spanish: the gate passes.
  write-fixture [
    (row '/x/kb/docs/en.md' $EN_TEXT)
    (row '/x/kb/src/Mixed.kt' $MIXED_TEXT)
    (row '/x/kb/config.json' '{"a": 1}')
  ]
  let green: any = (nu $SCRIPT $FIXTURE --check --out /tmp/rag-english-check-out.tsv | complete)
  assert ($green.exit_code == 0) 'check exits 0 when only a code file carries Spanish'
  assert ($green.stdout =~ 'ENGLISH CHECK: PASS') 'the pass says the store reads English'

  print 'rag-english-check: all verdicts and both gate outcomes verified.'
}

# The tiny assertion the scripts tests share.
def assert [cond: bool, msg: string]: nothing -> nothing {
  if not $cond { print $"FAIL: ($msg)"; exit 1 }
}
