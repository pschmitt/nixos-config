---
name: self-improvement
description: Improve a first-party skill when real use reveals a factual error or a useful adjustment, or propose a new skill when toil or a recurring problem keeps coming back.
---

# Self-improvement

Use this skill when a first-party skill contains a factual error, has gone stale, or needs an adjustment based on what happened while carrying out its workflow. Make the targeted improvement as part of the current task when you have access to the owning repository; do not stop at reporting the issue.

## Find the owning skill

- Public skills live in `nixos-config/home-manager/devel/skills/<skill>/` in the `pschmitt/nixos-config` repository.
- Private skills live in `nixos-config-private/hm/skills/<skill>/` in the `pschmitt/nixos-config-private` repository.
- CKS skills live in the `kubernetes/agent-skills` repository on `git.wiit.one`. They already carry their own improvement instructions; follow those instructions and do not add the shared footer to them.

Check the skill's source before editing. Installed or generated copies may be assembled by Nix and are not the source of truth. Shared guidance for first-party skills is maintained once in `nixos-config/home-manager/devel/skill-footer.md`; Nix adds it when it builds the combined skill tree.

## Make a useful change

- Fix claims that are demonstrably wrong or outdated. For workflow adjustments, use evidence from the task or another concrete example.
- Keep the change narrow and in the owning skill. Do not turn a one-off hiccup into a universal rule unless the underlying behavior is repeatable.
- Preserve the skill's existing scope, safety constraints, and authorization boundaries. Do not expand the user's requested action while improving instructions.
- Check links and references affected by the edit, then run the skill's available validator or the repository's skill checks when practical. For Nix-managed skills, edit the source Markdown, not the generated output.

If the skill is owned by a repository that is unavailable or read-only, report the evidence and the exact proposed change so it can be applied at the source.

## Propose a new skill

Use this when you notice toil: a procedure you had to rediscover, the same failure hit twice, or a user correction that applies beyond this task. Do it at the end of the task, not in the middle of it.

A new skill is worth it when all of these hold:

- The problem recurs, or will plausibly recur, across sessions.
- The answer is non-obvious: it took investigation, or it was wrong at first.
- It is not already covered by a skill, `AGENTS.md`, or `CONTEXT.md`. Check first; extend an existing skill instead of adding an overlapping one.

If it is a single rule or a one-line gotcha, put it in `AGENTS.md` (repo-specific) or the shared context instead of a skill.

Process:

1. Tell the user what the skill would cover and why, in two or three lines. Wait for a go-ahead before creating it; the library should not fill with speculative skills.
2. Create `<skill>/SKILL.md` in the owning repository (see above). Nix picks up every directory under `skills/`, so no registration is needed. Do not add the improvement footer by hand.
3. Write the `description` as a trigger: say when to use it, using the words a future task would contain. Keep `SKILL.md` short and move long detail to `references/`.
4. Record what actually worked, including commands and the pitfalls you hit. Never record secret values; point to the vault entry or runtime interface instead.
5. Link it from `CONTEXT.md` only if agents must know about it without matching the description.
6. Follow the repository's commit and deploy workflow for the owning repository.
