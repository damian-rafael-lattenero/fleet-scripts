#!/opt/homebrew/bin/nu
# RETIRED (U4, 27/11): the permanent laws now ride the system prompt itself.
# The fork reads ~/.zcode/denotational-law.md (a symlink to agent-brain's
# docs/denotational-law.md) into EVERY session — main and subagent — as its own
# stable section, so this per-prompt injection has no work left. The file stays
# as a registered no-op: the settings entry still points here, and a hook that
# prints nothing cannot drift from the law.
#
# Receipt of the handover: a subagent of session sess_5a90dc11 quoted the law
# verbatim from its system prompt, and its first Write was denied by the typing
# hook (denials.tsv, sess_subagent_agent_24d52dec, 2026-11-27T00:49:34-03:00).

def main []: string -> nothing {
  null
}
