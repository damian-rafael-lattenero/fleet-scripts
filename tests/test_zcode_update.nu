# test_zcode_update.nu — the pure-core proofs for lib/zcode-update.nu: the
# stdout-else-stderr version pick, the gradle wrapper parse and the pins
# panel from read files.
use std/assert
use ../lib/zcode-update.nu *

# 1. the version pick: stdout wins, stderr is the fallback, empty answers
#    "(missing)" (an empty version output must never kill the panel).
assert equal (version-line "nu 0.117.0\nsecond line" "") "nu 0.117.0"
assert equal (version-line "" "openjdk version \"21.0.2\"\nmore") "openjdk version \"21.0.2\""
assert equal (version-line "  \n " "") "(missing)"
assert equal (version-line "" "") "(missing)"

# 2. the gradle pin: the wrapper's distributionUrl answers the version;
#    anything unparseable answers "?".
let wrapper: string = "distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14.3-bin.zip"
assert equal (gradle-pin $wrapper) "8.14.3"
assert equal (gradle-pin "nothing here") "?"
assert equal (gradle-pin "") "?"

# 3. the pins panel: three rows, values from the files, "?" on missing keys.
let pins: table<tool: string, pin: string> = (pins-from
    {devDependencies: {electron: "35.1.5"}}
    {packageManager: "pnpm@10.12.1"}
    $wrapper)
assert equal ($pins | length) 3
assert equal $pins.0.tool "electron (fork desktop)"
assert equal $pins.0.pin "35.1.5"
assert equal $pins.1.pin "pnpm@10.12.1"
assert equal $pins.2.pin "8.14.3"
let bare: table<tool: string, pin: string> = (pins-from {} {} "")
assert equal ($bare | get pin | uniq) ["?"]

print "test_zcode_update ok"
