#!/opt/homebrew/bin/nu
# zcode-original.nu — launch the NEWEST official ZCode: the build where the
# rewards are claimed. It CHECKS the release feed, DOWNLOADS + verifies a newer
# build, and only then launches. The fork and the official app share ONE bundle
# id (dev.zcode.app), so only one can run — when the fork is up this REFUSES
# instead of bouncing silently into it (measured 16/11 + 27/11).
#
# WHERE IT LOOKS. Local candidates are ranked by VERSION, never by path
# (lib/versions.nu): a mounted /Volumes/ZCode* volume (usable now, and it
# outlives the DMG it came from — the 3.19.0 volume survived its deleted
# Downloads folder), the staged app in ~/zcode-official-backup, and any
# ZCode*.dmg under ~/Downloads. The mount point is READ from hdiutil's table,
# never guessed from the filename — the old guess built
# "/Volumes/ZCode (3.19.0-arm64)" while the truth is "/Volumes/ZCode
# 3.19.0-arm64", so it launched nothing at all.
#
# WHERE IT UPDATES FROM. The GitHub release feed of zai-org/ZCode
# (releases/latest): its mac artifact for this architecture plus SHA256SUMS.
# A newer release is downloaded to ~/Downloads/zcode-official-<date>/, its
# SHA256 checked against the published sums, and only a verified file is ever
# attached. No sums published = no launch (an unverified 240 MB download is not
# worth the risk). Offline or rate-limited = the newest local build launches.
#
# PINNED RUNS. `--version <v>` wants exactly one version: the local candidate
# with that version, else that release from the feed (downloaded + verified
# like any other). A pinned run never upgrades — newer builds are ignored on
# purpose — which is how a claim is retried from an older client.
#
#   zcode-original              check → update if newer → launch
#   zcode-original --check      local vs latest; exit 1 when an update exists
#   zcode-original --no-update  skip the release feed, launch the newest local
#   zcode-original --print      the local pick as JSON; no network, no effects
#   zcode-original --version 3.18.2   launch exactly that version
use ../lib/versions.nu *

const DOWNLOADS: string = "/Users/lattenero/Downloads"
const BACKUP: string = "/Users/lattenero/zcode-official-backup"
const VOLUMES: string = "/Volumes/ZCode*"
const BUNDLE_ID: string = "dev.zcode.app"
const FEED: string = "https://api.github.com/repos/zai-org/ZCode/releases/latest"
const FEED_RELEASES: string = "https://api.github.com/repos/zai-org/ZCode/releases?per_page=30"

# One launchable candidate. `key` is the version as a number (versions.nu);
# `rank` breaks a tie between two sources of the SAME version: a mounted volume
# wins, then the staged app, then a DMG that still has to be attached (a fresh
# download outranks everything at its version).
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

# Every local candidate that carries a version; the input of both selections
# (newest and pinned).
def local-candidates []: nothing -> list<Candidate> {
    (((mounted-candidates) ++ (backup-candidates) ++ (dmg-candidates)) | where key > 0)
}

# The newest official build on this Mac, or null when there is none. Only a
# name that CARRIES a version can win (key > 0): an unversioned stray is never
# "the latest".
def newest []: nothing -> any {
    let all: list<Candidate> = (local-candidates)
    if ($all | is-empty) { return null }
    $all | sort-by key rank | last
}

def app-version [app: string]: nothing -> string {
    let read: record = (do { ^defaults read $"($app)/Contents/Info" CFBundleShortVersionString } | complete)
    $read.stdout | str trim
}

# The mac artifact suffix for THIS machine (the feed publishes arm64 and x64).
def arch-suffix []: nothing -> string {
    let probe: record = (do { ^uname -m } | complete)
    let arch: string = ($probe.stdout | str trim)
    match $arch {
        "arm64" => "arm64"
        "x86_64" => "x64"
        _ => { print -e $"unsupported architecture: ($arch)"; exit 1 }
    }
}

# The latest published release for this arch, or null when the feed cannot be
# read (offline, rate limit) or carries no mac asset — the caller then
# launches the newest LOCAL build, which is the honest degradation.
def remote-release [arch: string]: nothing -> any {
    let run: record = (do { ^curl -fsSL --connect-timeout 10 --max-time 25 -H 'Accept: application/vnd.github+json' $FEED } | complete)
    if $run.exit_code != 0 { return null }
    let parsed: any = (try { $run.stdout | from json } catch { null })
    if $parsed == null { return null }
    release-of $parsed $arch
}

# The release whose version equals the request, from the feed's release page.
# The comparison goes through version-of/version-key, so "3.18" and "3.18.0"
# name the same release and a tag prefix ("v") is irrelevant. Null when the
# feed cannot be read or carries no such release.
def remote-release-by-version [arch: string, version: string]: nothing -> any {
    let run: record = (do { ^curl -fsSL --connect-timeout 10 --max-time 30 -H 'Accept: application/vnd.github+json' $FEED_RELEASES } | complete)
    if $run.exit_code != 0 { return null }
    let parsed: any = (try { $run.stdout | from json } catch { null })
    if $parsed == null { return null }
    let want: int = (version-key (version-of $"zcode-($version)"))
    $parsed
    | each {|release| release-of $release $arch }
    | where {|release| $release != null }
    | where {|release| $release.key == $want }
    | get --optional 0
    | default null
}

# The pinned pick: the local candidate whose version equals the request (the
# best rank wins), else the feed's release for it, else null. A pinned run
# never upgrades — newer local or remote builds are ignored on purpose.
def pick-pinned [candidates: list<Candidate>, remote: any, version: string]: nothing -> any {
    let want: int = (version-key (version-of $"zcode-($version)"))
    let local: any = ($candidates | where {|c| $c.key == $want } | sort-by rank | get --optional 0 | default null)
    if $local != null { return $local }
    $remote
}

# The downloaded file against the release's published sums: {ok, why}. Never
# trusts the network: a missing sums asset is a refusal, not a warning.
def verify [file: string, asset: record]: nothing -> record<ok: bool, why: string> {
    if ($asset.sums_url | is-empty) { return {ok: false, why: "the release publishes no SHA256SUMS"} }
    let sums: record = (do { ^curl -fsSL --connect-timeout 10 --max-time 30 $asset.sums_url } | complete)
    if $sums.exit_code != 0 { return {ok: false, why: "SHA256SUMS is unreachable"} }
    let name: string = ($file | path basename | str replace -r '\.part$' '')
    let want: string = (sha-of $sums.stdout $name)
    if ($want | is-empty) { return {ok: false, why: $"SHA256SUMS has no entry for ($name)"} }
    let have: record = (do { ^shasum -a 256 $file } | complete)
    if $have.exit_code != 0 { return {ok: false, why: $"shasum failed on ($file)"} }
    let got: string = ($have.stdout | split row ' ' | first | str lowercase)
    if $got != $want { return {ok: false, why: $"SHA256 mismatch: published ($want), got ($got)"} }
    {ok: true, why: "SHA256 verified"}
}

# Download the asset into a dated folder under ~/Downloads, verify it, and only
# then let it carry the DMG name (a partial file can never be picked as a
# candidate). A verified earlier copy is reused: a re-run must not re-download
# 240 MB.
def download-asset [asset: record]: nothing -> string {
    let dir: string = ($DOWNLOADS | path join $"zcode-official-((date now | format date '%Y-%m-%d'))")
    let name: string = ($asset.dmg_url | path basename)
    let dest: string = ($dir | path join $name)
    let part: string = $"($dest).part"
    if ($dest | path exists) and (verify $dest $asset).ok { return $dest }
    mkdir $dir
    print $"downloading ZCode ($asset.version) — (($asset.size / 1_000_000) | math round) MB"
    let pull: record = (do { ^curl -fL -sS --retry 2 --connect-timeout 20 --max-time 900 -o $part $asset.dmg_url } | complete)
    if $pull.exit_code != 0 {
        rm --force $part
        print -e $"download failed: ($pull.stderr | str trim)"
        exit 1
    }
    let checked: record = (verify $part $asset)
    if not $checked.ok {
        rm --force $part
        print -e $"refusing the download — ($checked.why)"
        exit 1
    }
    mv $part $dest
    print $"verified + saved: ($dest)"
    $dest
}

# The launch-path update: a newer published release replaces the local pick; an
# equal-or-older feed (or an unreadable one) leaves the local pick in charge.
def updated-pick [pick: any, arch: string]: nothing -> any {
    let remote: any = (remote-release $arch)
    if $remote == null { return $pick }
    let have: int = (if $pick == null { 0 } else { $pick.key })
    if $remote.key <= $have { return $pick }
    let dmg: string = (download-asset $remote)
    ({words: $remote.version, key: $remote.key, path: $dmg, kind: "dmg", rank: 4})
}

# The bundle root a running main process really lives in. `ps` is NOT enough:
# the app's argv[0] is the bare word "ZCode" (measured 27/11 — a path-based
# probe saw nothing, the guard passed, and `open` bounced silently into the
# fork), so the truthful source is the process's own text segment, which lsof
# names as the executable's real path inside the bundle.
def bundle-of [pid: string]: nothing -> string {
    let run: record = (do { ^lsof -p $pid -a -d txt -Fn } | complete)
    let hit: any = ($run.stdout | lines
        | where {|line| $line =~ '/ZCode\.app/Contents/MacOS/ZCode$' }
        | get --optional 0
        | default null)
    if $hit == null { return "" }
    ($hit | str substring 1..) | path dirname | path dirname | path dirname
}

# Every running ZCode MAIN process (the helpers are named "ZCode Helper" and
# never match), as bundle roots.
def running-bundles []: nothing -> list<string> {
    let ps: record = (do { ^ps -axo pid=,comm= } | complete)
    let pids: list<string> = ($ps.stdout | lines
        | parse -r '^\s*(?<pid>\d+)\s+ZCode$'
        | get --optional pid
        | default []
        | into string)
    ($pids | each {|pid| bundle-of $pid } | where {|bundle| not ($bundle | is-empty) } | uniq)
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

def main [--print, --check, --no-update, --version: string = ""]: nothing -> nothing {
    let arch: string = (arch-suffix)
    let pinned: string = ($version | str trim)
    let pick: any = (newest)
    # --print is hermetic: the gate proves this path, so it touches no network.
    if $print {
        if not ($pinned | is-empty) {
            let pinned_local: any = (pick-pinned (local-candidates) null $pinned)
            if $pinned_local == null {
                print -e $"no official ZCode ($pinned) among the local builds — mounted, staged or downloaded — run zcode-original --version ($pinned) without --print to fetch it from the feed."
                exit 1
            }
            print ({version: $pinned_local.words, kind: $pinned_local.kind, path: $pinned_local.path} | to json)
            return
        }
        if $pick == null {
            print -e "no official ZCode found — nothing mounted, nothing staged in ~/zcode-official-backup, no ZCode*.dmg in ~/Downloads."
            exit 1
        }
        print ({version: $pick.words, kind: $pick.kind, path: $pick.path} | to json)
        return
    }
    # --check reports the two sides and nothing else; exit 1 = an update exists.
    if $check {
        let remote: any = (remote-release $arch)
        let local: string = (if $pick == null { "none" } else { $pick.words })
        if $remote == null {
            print $"local ($local) · release feed unreachable — cannot tell whether an update exists"
            return
        }
        if $remote.key > (if $pick == null { 0 } else { $pick.key }) {
            print $"local ($local) · latest ($remote.version) — an update is available: run zcode-original"
            exit 1
        }
        print $"local ($local) · latest ($remote.version) — up to date"
        return
    }
    # The launch path: a pinned run wants exactly one version and never
    # upgrades; otherwise update first (a download never fights the running
    # app), then the collision guard.
    let freshest: any = (if not ($pinned | is-empty) {
        let remote: any = (remote-release-by-version $arch $pinned)
        pick-pinned (local-candidates) $remote $pinned
    } else if $no_update {
        $pick
    } else {
        updated-pick $pick $arch
    })
    if $freshest == null {
        if not ($pinned | is-empty) {
            print -e $"no official ZCode ($pinned) — not mounted, not staged, not in ~/Downloads, and the feed carries no such release."
            exit 1
        }
        print -e "no official ZCode found — nothing mounted, nothing staged in ~/zcode-official-backup, no ZCode*.dmg in ~/Downloads, and the release feed answered nothing."
        exit 1
    }
    let running: list<string> = (running-bundles)
    if ($freshest.path in $running) {
        print $"already running: ZCode ($freshest.words) — ($freshest.path)"
        return
    }
    if not ($running | is-empty) {
        print -e $"ZCode is already running from ($running | first). The fork and the official build share the bundle id ($BUNDLE_ID), so opening the official one would bounce into it — quit ZCode and run this again."
        exit 1
    }
    let mount: string = (if $freshest.kind == "dmg" { attach $freshest.path } else { $freshest.path | path dirname })
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
    # open's zero is NOT proof a launch happened (measured 27/11: a bounced
    # open returns 0), so the receipt names what is actually up.
    if ($bundle in (running-bundles)) {
        print $"launched ZCode ($version) — ($bundle)"
    } else {
        print $"open accepted ($bundle) — no ($version) process is up yet; if nothing appears, quit the other ZCode and run this again."
    }
}
