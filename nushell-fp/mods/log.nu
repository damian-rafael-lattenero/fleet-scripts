# log.nu — the fleet-script receipt: one voice for stdout AND the run log.
#
# Every fleet script (healthcheck, fleet-errors, ram-clean, deploy-status,
# worktree-sweep, day, brain) speaks through this: what the user sees on
# stdout is also appended to the script's own ~/Library/Logs/<name>.log, so
# the receipt survives the terminal that ran it.

# Print the line to stdout AND append it (with newline) to the log file.
export def emit-to [log: path, line: string]: nothing -> nothing {
    print $line
    $"($line)\n" | save --append --raw $log
}
