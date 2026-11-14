# nu-fp repo law

- English only in all files: code, names, comments, docs, commits.
- Typed by law: every `def` carries typed params plus an input/output
  signature; annotate `let`/`mut` when the type is not evident on the line.
  Closures passed to builtins (`each`, `where`, `reduce`, ...) stay
  unannotated — builtins reject annotations (parse error).
- Gaps only: before adding a function, check it is not already a builtin
  (`each`=map, `where`=filter, `reduce`=fold, `zip`, `chunks`, `uniq`,
  `flatten`, `transpose`, `interleave`, `take while`, `skip until`,
  `sort-by`, `group-by`). Never wrap builtins.
- Verify live: probe any doubtful syntax with a real `nu` run before it
  enters a module. Confirmed traps get a note in the module header.
- Tests mandatory: every exported function has an assertion in `tests/`;
  `nu test.nu` must print ALL GREEN before a commit.
- Commit + push per logical unit.
