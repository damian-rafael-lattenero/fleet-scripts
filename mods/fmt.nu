# fmt.nu — display formatting for shell output.
#
# The owner's number law (corrected in-session four times in one day): quota
# and token numbers render on a raw -> K -> M ladder, American system, and
# the M rung fires AT the boundary — 1,000,000 is "1M", never "1000K".
# nushell has no K/M formatter builtin (gap verified on 0.117).

# Render an integer on the raw -> K -> M ladder, trailing zeros trimmed.
export def human-num [x: int]: nothing -> string {
    if $x >= 1000000 {
        (($x / 1000000) | math round --precision 2 | into string | str replace -r '\.0+$' "") + "M"
    } else if $x >= 1000 {
        (($x / 1000) | math round --precision 2 | into string | str replace -r '\.0+$' "") + "K"
    } else {
        $x | into string
    }
}
