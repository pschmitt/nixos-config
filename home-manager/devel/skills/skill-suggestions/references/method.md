# Method notes

## Where the transcripts are

| Agent | Prompts | Full transcripts |
|---|---|---|
| claude, claude-work, claude-auto | `~/.config/<agent>/history.jsonl` (`timestamp` in ms, `project`, `display`) | `~/.config/<agent>/projects/<slug>/*.jsonl` (skip `subagents/`) |
| codex | `~/.config/codex/history.jsonl` (`ts` in s, `session_id`, `text`) | `~/.config/codex/sessions/YYYY/MM/DD/*.jsonl` |
| agy | `~/.gemini/antigravity-cli/conversation_summaries.db` (`title`, `preview`, `step_count`) | `~/.gemini/antigravity-cli/conversations/<id>.db`, table `steps` |

The Claude history records pasted text only as `[Pasted text #n]`; the content is in the
transcript. `tool-use.tsv` covers Claude only; codex tool
calls are in its session files (`response_item` payloads), agy's in the protobuf steps.

Reading an agy conversation: `sqlite3 <id>.db "select hex(step_payload) from steps order by idx"`
per row through `xxd -r -p | tr -c '[:print:]\n' ' '`. Commands the agent ran show up after
`RunCommand`.

## Is it worth a new skill?

All of these:

1. It recurs, or plainly will, across sessions or projects.
2. The answer was non-obvious (it needed investigation or was wrong at first).
3. No skill, `AGENTS.md` or `CONTEXT.md` line covers it. Check first.

A single rule belongs in `AGENTS.md`/`CONTEXT.md`. A long identical command chain belongs in a
script. A skill is for a procedure with judgment, ordering and pitfalls.

## Signals worth weighting

- The same correction from the user twice ("always do X"), especially to different agents:
  Claude's memory is invisible to codex and agy, so a rule only in memory has to move to shared
  context.
- Resume and handoff prompts: context was lost, so the project lacks a durable note or skill.
- A skill the user had to ask for by name ("create an adb skill so you stop messing up inputs").
- Work started in one project directory but done in another.
- Waiting loops: sleep-and-poll chains for CI, deploys or builds.
- Hosts that are off, tokens that expire, tools that are locked: recurring environment friction
  that a note would save a round trip on.

## Baseline from the first review (2026-10-30, window 10-16 to 10-30)

Already built from it, do not propose again: `resume-work` for agy and cross-project resume,
shared rules in `CONTEXT.md`, `extension-dev`, `release`, `brkn-infra`, the `nix` skill's
`remote-sync.sh` and `ci-wait.sh`, and the HA repairs notes. The Authelia passkey counter issue
was fixed in rbw. Open after that review: recheck whether skills trigger at all (only about 27
Skill invocations in 179 Claude sessions; Codex was not measured).
