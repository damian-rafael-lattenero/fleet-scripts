# fleet.nu core — THE hub's verb table, pure: the caller hands in the file
# list (the script globs scripts/*.nu at its edge), so every def here answers
# from its arguments alone.
#
# One Command per verb. Discovery is the file list itself (verb = file stem);
# the only explicit rows are the five deploy verbs the owner types from
# memory plus healthcheck, which lives in the skills tree.
#
# resolve is TOTAL: it answers 0 or 1 row. The decision to refuse an unknown
# verb belongs to the edge (main), never to the table.

export type Command = record<verb: string, script: string>

# healthcheck is the fleet-healthcheck skill's script (the 11-leg battery the
# phone's /fleet_healthcheck also runs) — one copy, not a second script.
export def aliases [root: path, healthcheck: path]: nothing -> list<Command> {
    let dir: path = ($root | path join 'scripts')
    [
        {verb: 'deploy-all', script: ($dir | path join 'zcode-deploy-all.nu' | into string)}
        {verb: 'deploy-brain', script: ($dir | path join 'zcode-brain-deploy.nu' | into string)}
        {verb: 'deploy-fork', script: ($dir | path join 'zcode-fork-deploy.nu' | into string)}
        {verb: 'deploy-bot', script: ($dir | path join 'zcode-bot-kotlin-deploy.nu' | into string)}
        {verb: 'deploy-whatsapp', script: ($dir | path join 'zcode-whatsapp-kotlin-deploy.nu' | into string)}
        {verb: 'healthcheck', script: ($healthcheck | into string)}
    ]
}

# The door itself is not a verb.
export def verbs [files: list<string>]: nothing -> list<Command> {
    $files
    | where {|p| ($p | path basename) != 'fleet.nu'}
    | each {|p| {verb: ($p | path parse | get stem), script: $p}}
}

export def verb-table [alias_rows: list<Command>, file_rows: list<Command>]: nothing -> list<Command> {
    ($alias_rows | append $file_rows | sort-by verb)
}

export def resolve [verb: string, table: list<Command>]: nothing -> list<Command> {
    $table | where {|c| $c.verb == $verb}
}
