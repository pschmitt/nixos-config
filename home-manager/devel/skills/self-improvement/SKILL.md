---
name: self-improvement
description: Improve a first-party skill when real use reveals a factual error or a useful adjustment.
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
