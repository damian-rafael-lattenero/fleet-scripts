#!/opt/homebrew/bin/nu
# zcode-original.nu — launch the NEWEST official ZCode on this Mac: the build
# where the rewards are claimed. The fork and the official app share ONE bundle
# id (dev.zcode.app), so only one can run — when the fork is up this REFUSES
# instead of bouncing silently into it (measured 16/11).
#
# Candidates, ranked: a mounted official volume (usable now, and it outlives
# the DMG it came from — measured 27/11: the 3.19.0 volume was still mounted
# after its Downloads folder was deleted), then the staged official app in
# ~/zcode-official-backup, then any ZCode*.dmg under ~/Downloads, attached on
# demand. The VERSION decides, never the path (lib/versions.nu); the mount
# point is READ from hdiutil, never guessed from the filename — the old guess
# built "/Volumes/ZCode (3.19.0-arm64)" while the truth is "/Volumes/ZCode
# 3.19.0-arm64", so the command launched nothing at all.
#
#   zcode-original            launch the newest official build
#   zcode-original --print    which build would launch; no side effects
use ../lib/versions.nu *

const DOWNLOADS: string = "/Users/lattenero/Downloads"
const BACKUP: string = "/Users/lattenero/zcode-official-backup"
const VOLUMES: string = "/Volumes/ZCode*"
const BUNDLE_ID: string = "dev.zcode.app"

# One launchable candidate. `key` is the version as a number (versions.nu);
# `rank` breaks a tie between two sources of the SAME version: a mounted volume
# wins, then the staged app, then a DMG that still has to be attached.
type Candidate = record<words: string, key: int, path: string, kind: string, rank: int>

def candidate [path: string, kind: string, rank: int, name: string]: nothing -> Candidate {
    let parts: list<int> = (version-of $name)
    {words: (version-words $parts), key: (version-key $parts), path: $path, kind: $kind, rank: $rank}
}

def mounted-candidates []: nothing -> list<Candidate> {
    (glob $VOLUMES)
    | where {|vol| ($vol | path join "ZCode.app") | path exists }
    | each {|vol| candidate ($vol | path join "ZCode.app") "volume" 3 ($vol | path basename) }
}

def backup-candidates []: nothing -> list<Candidate> {
    (glob ($BACKUP | path join "**" "ZCode*.app"))
    | each {|app| candidate $app "app" 2 ($app | path basename) }
}

def dmg-candidates []: nothing -> list<Candidate> {
    (glob ($DOWNLOADS | path join "**" "ZCode*.dmg"))
    | each {|dmg| candidate $dmg "dmg" 1 ($dmg | path basename) }
}

# The newest official build on this Mac, or null when there is none. Only a
# name that CARRIES a version can win (key > 0): an unversioned stray is never
# "the latest".
def newest []: nothing -> any {
    let all: list<Candidate> = (((mounted-candidates) ++ (backup-candidates) ++ (dmg-candidates)) | where key > 0)
    if ($all | is-empty) { return null }
    $all | sort-by key rank | last
}

def app-version [app: string]: nothing -> string {
    let read: record = (do { ^defaults read $"($app)/Contents/Info" CFBundleShortVersionString } | complete)
    $read.stdout | str trim
}

# The MAIN bundle processes only — "<bundle>/Contents/MacOS/ZCode", never a
# helper — mapped back to their bundle root.
def running-bundles []: nothing -> list<string> {
    (^ps -axo args= | lines
        | where {|line| $line =~ 'ZCode\.app/Contents/MacOS/ZCode(\s|$)' }
        | each {|line| $line | split row '/Contents/MacOS/ZCode' | first }
        | uniq)
}

# Attach the image and READ the mount point from hdiutil's own table — its
# last tab-separated field. A filename is a guess; the table is the truth.
def attach [dmg: string]: nothing -> string {
    let run: record = (do { ^hdiutil attach $dmg -nobrowse } | complete)
    if $run.exit_code != 0 {
        print -e $"hdiutil attach failed: ($run.stderr | str trim)"
        exit 1
    }
    let mounts: list<string> = ($run.stdout | lines
        | where {|line| $line | str contains '/Volumes/' }
        | each {|line| $line | split row (char tab) | last | str trim })
    if ($mounts | is-empty) {
        print -e "hdiutil attach named no mount point — hands needed."
        exit 1
    }
    $mounts | last
}

def main [--print]: nothing -> nothing {
    let pick: any = (newest)
    if $pick == null {
        print -e "no official ZCode found — nothing mounted, nothing staged in ~/zcode-official-backup, no ZCode*.dmg in ~/Downloads. Download the official DMG first."
        exit 1
    }
    if $print {
        print ({version: $pick.words, kind: $pick.kind, path: $pick.path} | to json)
        return
    }
    let running: list<string> = (running-bundles)
    if ($pick.path in $running) {
        print $"already running: ZCode ($pick.words) — ($pick.path)"
        return
    }
    if not ($running | is-empty) {
        print -e $"ZCode is already running from ($running | first). The fork and the official build share the bundle id ($BUNDLE_ID), so opening the official one would bounce into it — quit ZCode and run this again."
        exit 1
    }
    let mount: string = (if $pick.kind == "dmg" { attach $pick.path } else { $pick.path | path dirname })
    let bundle: string = ($mount | path join "ZCode.app")
    if not ($bundle | path exists) {
        print -e $"($mount) carries no ZCode.app — the image layout changed; hands needed."
        exit 1
    }
    let version: string = (app-version $bundle)
    let opened: record = (do { ^open $bundle } | complete)
    if $opened.exit_code != 0 {
        print -e $"open failed: ($opened.stderr | str trim)"
        exit 1
    }
    print $"launched ZCode ($version) — ($bundle)"
}
