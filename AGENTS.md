# nushell-fp repo law

- English only in all files: code, names, comments, docs, commits.
- Typed by law: every `def` carries typed params plus an input/output
  signature; annotate `let`/`mut` when the type is not evident on the line.
  Closures passed to builtins (`each`, `where`, `reduce`, ...) stay
  unannotated — builtins reject annotations (parse error).
- Gaps only — check in ORDER before adding a function: (1) builtin
  (`each`=map, `where`=filter, `reduce`=fold, `zip`, `chunks`, `uniq`,
  `flatten`, `transpose`, `interleave`, `take while`, `skip until`,
  `sort-by`, `group-by`, `merge deep`); (2) std-rfc module (iter,
  conversions, date, kv, path, pb, random — see
  nushell-kb/notes/std-rfc-inventory.md); (3) this repo's README. Never
  wrap what already exists.
- Verify live: probe any doubtful syntax with a real `nu` run before it
  enters a module. Confirmed traps get a note in the module header.
- Tests mandatory: every exported function has an assertion in `tests/`;
  `nu test.nu` must print ALL GREEN before a commit.
- The README index is part of the definition of done: every new module or
  function ships its README row in the SAME commit. (Lesson: a module without
  its index row is invisible to the brain RAG — a missing human-num row read
  as an indexer bug for an hour.)
- Commit + push per logical unit.
