# proc.nu — the process-edge helpers: folding what `complete` returns into
# plain text. The measured trap (the 15/11 drill, duplicated in brain-doctor
# and brain): a complete record's `stderr` arrives as a STRING or a LIST OF
# LINES depending on how the external chunked its output — an error path
# that string-slices it blindly crashes on the list shape and HIDES the
# real error.

# Fold a complete record's stderr (string | list of lines) into one string.
# A missing or null stderr is the honest empty string, never a crash.
export def fold-stderr [run: record]: nothing -> string {
    let e: any = ($run.stderr? | default "")
    if ($e | describe | str starts-with "list") { $e | str join (char nl) } else { $e }
}
