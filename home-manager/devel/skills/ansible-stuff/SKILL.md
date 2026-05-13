---
name: ansible-stuff
description: Use when working in the private Ansible repository at `~/devel/private/pschmitt/ansible-stuff.git`, especially for playbooks, roles, inventory, OpenWrt setup, SOPS-backed vars, Ansible linting, or flake/dev-shell maintenance. Read `references/conventions.md` before editing and run Ansible tools through the Nix dev shell.
---

# Ansible Stuff

Use this skill for work in the `ansible-stuff.git` repository.

## Quick start

1. Work from:

```bash
cd ~/devel/private/pschmitt/ansible-stuff.git
```

2. Read `references/conventions.md` before making changes.
3. Use the flake-provided dev shell for all Ansible tooling:

```bash
nix develop
```

4. For one-shot commands, prefer:

```bash
nix develop --command ansible-lint
```

## Workflow

1. Inspect `AGENTS.md`, `flake.nix`, and the relevant playbook or role before
   editing.
2. Keep changes narrow and preserve existing Ansible structure unless the task
   requires a larger refactor.
3. Treat inventory, host vars, group vars, and SOPS-encrypted files carefully.
4. Validate focused changes with `nix develop --command ansible-lint <path>`
   when practical.
5. Use `nix flake check` after changing `flake.nix`, `flake.lock`, or dev-shell
   behavior.

## Reference map

- `references/conventions.md`: Repository path, dev-shell rules, validation
  commands, and local Ansible conventions.

## Safety rules

- Do not rely on ambient `ansible`, `ansible-lint`, or Python packages outside
  the dev shell.
- Never commit decrypted secrets, temporary secret files, or credential output.
- Expect unrelated local changes in this repo and do not revert them unless the
  user explicitly asks.
