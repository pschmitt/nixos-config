---
name: skill-suggestions
description: Review the user's recent agent conversations (claude, claude-work, codex, agy), find pain points and recurring toil, review the existing skills, and propose new or improved skills and scripts. Use when the user asks for skill suggestions, runs /skill-suggestions, asks what could be automated, or wants a periodic review of how the agents are being used.
---

# Skill suggestions

Turns the history of past agent sessions into concrete proposals that make the next sessions
cheaper: a new skill, a fix to an existing one, a helper script, or a line in `CONTEXT.md` /
`AGENTS.md`. Proposals only: nothing is created before the user says yes (the rule in
`self-improvement`).

## 1. Collect

```
scripts/collect.sh --days 14 --out "$SCRATCH/skill-suggestions-data"
```

(`$SCRATCH` is the session scratchpad.) It writes, from claude, claude-work, claude-auto, codex
and agy: `prompts.tsv` (agent, time, project or session, prompt), `corrections.tsv` (prompts that
look like a complaint or repeated instruction), `agy.tsv` (conversations over 2 steps; the 2-step
ones are usage probes), `skills-used.txt`, `bash-heads.txt` (most common commands), `volume.txt`
(prompts per agent and project). It takes about 15 seconds.

Default window: 14 days. Use `--days` when the user names another period. If the user says "my
previous session", use a short window (1 to 3 days).

## 2. Read, do not just count

- `volume.txt`: where the time goes (which projects, which agent).
- `corrections.tsv`: read all of it. Each line is a failure the user had to correct. Group them:
  same complaint twice means a missing rule or skill. Look for "always", "again", "forgot".
- `prompts.tsv`: skim by project. Look for the same kind of request in several projects (for
  example "deploy to X and check the version", "make the icon bigger") and for resume or
  handoff prompts, which mean context was lost.
- `agy.tsv`: titles and previews only. Read the biggest conversations more closely if they look
  like toil (see `references/method.md` for reading agy steps).
- `bash-heads.txt` and `tool-use.tsv`: long hand-typed command chains that repeat (ssh plus
  rsync, polling loops) are script candidates, not skill candidates.
- `skills-used.txt`: skills that never load although the work matched them have a bad
  description or are not needed.

## 3. Check what exists

Before proposing, read the skill list and the likely owners: `home-manager/devel/skills/` in
`nixos-config`, `hm/skills/` in `nixos-config-private`, `CONTEXT.md`, and the `AGENTS.md` of the
project involved. Many "missing skills" are a stale or untriggered existing one.

## 4. Classify each finding

Use the smallest fix that works (details and criteria: `references/method.md`):

| Kind | When |
|---|---|
| Rule in `CONTEXT.md` or `AGENTS.md` | One line, applies to every agent or one repo |
| Fix to an existing skill | It exists but is wrong, silent on the case, or never triggers |
| Helper script (in a skill's `scripts/`) | A long command sequence repeated verbatim |
| New skill | Recurs across sessions, non-obvious, and no skill covers it |

Drop anything that is a one-off or that the user already handled (check the git log).

## 5. Report

Rank by evidence, at most about eight items. For each: the pain in one sentence, the evidence
(counts, dates, a quoted line), the proposed kind and what it would contain, and the effort.
Close with the question of which to build. Keep secrets, tokens and customer data out of the
report. After approval, build the chosen items, commit, push and deploy as the repository rules
say, then report what changed.
