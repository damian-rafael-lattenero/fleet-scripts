# fmt.nu — display formatting for shell output.
#
# The owner's number law (corrected in-session four times in one day): quota
# and token numbers render on a raw -> K -> M ladder, American system, and
# the M rung fires AT the boundary — 1,000,000 is "1M", never "1000K".
# nushell has no K/M formatter builtin (gap verified on 0.117).

# Render an integer on the raw -> K -> M ladder, trailing zeros trimmed.
# The ladder is a PRIORITY TABLE (the mode-table law — the else-if chain
# died in the 22/11 self-audit): rows highest-first, first holding wins,
# the raw catch-all last.
export def human-num [x: int]: nothing -> string {
    let rungs: list<record<min: int, suffix: string>> = [
        {min: 1000000, suffix: "M"}
        {min: 1000, suffix: "K"}
    ]
    # nullable by construction (no row below min=1000) — the is-empty guard
    # is the raw catch-all, so the binding stays unannotated (the checker
    # infers the union; annotating record<...> rejects the null arm)
    let rung = ($rungs | where {|r| $x >= $r.min } | first)
    if ($rung | is-empty) {
        $x | into string
    } else {
        (($x / $rung.min) | math round --precision 2 | into string | str replace -r '\.0+$' "") + $rung.suffix
    }
}

# Chunk any token longer than max into space-separated pieces, so a wide
# table cell never holds an unbreakable run (stack-trace class tokens
# overflow their cell and the wrapping surface then misaligns every border
# below — measured 21/11). Short tokens pass through; the pieces join with
# SPACES, never newlines (explicit newlines inside table cells + -w trigger
# a width-calc inconsistency — measured the same night).
export def hard-wrap [s: string, max: int]: nothing -> string {
    $s
    | split row " "
    | each {|t: any|
        if ($t | str length) <= $max { $t } else {
            $t | split chars | chunks $max | each {|c: any| $c | str join } | str join " "
        }
    }
    | str join " "
}
