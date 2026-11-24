# usage-report.nu core — WHICH scripts actually run, as data. Two honest
# questions, two answers: the AGENT (the CLI's own tool calls, last N days,
# one SQL scan) and the OWNER (his terminal history and the phone's command
# ledger — both all-time, because neither carries dates).
#
# Pure: SQL built from the hub's names, text counted into rows, rows ranked.

export type Use = record<name: string, agent: int, terminal: int, phone: int, auto: bool>

# One scan, one column per name, counting EXECUTIONS: only the Bash tool's
# calls are commands, and only their `state.input.command` is read — the part
# also carries tool OUTPUT and file CONTENTS, so a grep over the scripts dir
# or a Write of a file would count as a run (measured 24/11: ram-clean showed
# 405 mentions and 111 real commands).
# Each script is counted by its path (`/name.nu`) and by its verb (`fleet
# name`), whichever the agent typed.
export def count-query [names: list<string>, since: int]: nothing -> string {
    let cmd: string = "json_extract(data,'$.state.input.command')"
    let cols: list<string> = ($names | each {|n|
        let path: string = "sum(instr(" + $cmd + ", '/" + $n + ".nu') > 0)"
        let verb: string = "sum(instr(" + $cmd + ", 'fleet " + $n + " ') > 0)"
        "(" + $path + " + " + $verb + ") as \"" + $n + "\""
    })
    let window: string = "from part where time_created > " + ($since | into string)
    let only_bash: string = " and json_extract(data, '$.type') = 'tool' and json_extract(data, '$.tool') = 'Bash'"
    ("select " + ($cols | str join ', ') + " " + $window + $only_bash)
}

# The CLI's single answer row (one big object) → name/count pairs.
export def agent-counts [row: record, names: list<string>]: nothing -> list<record<name: string, count: int>> {
    $names | each {|n|
        let v = ($row | get -o $n)
        {name: $n, count: (if $v == null { 0 } else { $v | into int })}
    }
}

# Count how many lines of a text mention the name (history lines are commands).
# The verb match needs a BOUNDARY: `fleet brain` is a substring of `fleet
# brain-eval` (measured 24/11 — brain counted its sibling's runs).
export def text-counts [text: string, names: list<string>]: nothing -> list<record<name: string, count: int>> {
    let lines: list<string> = ($text | lines)
    $names | each {|n|
        let verb_re: string = ('fleet ' + $n + '(\s|$)')
        let path_re: string = ('/' + $n + '\.nu')
        let hits: list<string> = ($lines | where {|l| ($l =~ $verb_re) or ($l =~ $path_re)})
        {name: $n, count: ($hits | length)}
    }
}

# The phone's ledger: palette names (`ram_clean`, `fleet_healthcheck`) map onto
# verbs (`ram-clean`, `healthcheck`) — the fleet-prefixed key first, the bare
# one as the fallback (the pre-fleet commands).
export def phone-counts [ledger: record, names: list<string>]: nothing -> list<record<name: string, count: int>> {
    let counts = ($ledger | get -o counts | default {})
    $names | each {|n|
        let key: string = ($n | str replace --all '-' '_')
        let v = ($counts | get -o ('fleet_' + $key) | default ($counts | get -o $key))
        {name: $n, count: (if $v == null { 0 } else { $v | into int })}
    }
}

# Scheduled = a LaunchAgent plist runs it (automatic: a phone command adds
# nothing). The plist text is the evidence, so the check stays pure.
export def scheduled? [plist_text: string, name: string]: nothing -> bool {
    ($plist_text | str contains ("/" + $name + ".nu")) or ($plist_text | str contains ("fleet " + $name))
}

export def join-uses [
    names: list<string>
    agent: list<record<name: string, count: int>>
    terminal: list<record<name: string, count: int>>
    phone: list<record<name: string, count: int>>
    scheduled: list<string>
]: nothing -> list<Use> {
    $names | each {|n|
        {
            name: $n
            agent: (($agent | where name == $n | get -o 0.count) | default 0)
            terminal: (($terminal | where name == $n | get -o 0.count) | default 0)
            phone: (($phone | where name == $n | get -o 0.count) | default 0)
            auto: ($n in $scheduled)
        }
    } | sort-by -r {|u| $u.agent + $u.terminal * 10 + $u.phone * 20}
}
