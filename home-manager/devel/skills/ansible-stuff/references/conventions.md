# Ansible Stuff Conventions

## Repository

The private Ansible repository is located at:

```text
~/devel/private/pschmitt/ansible-stuff.git
```

## Environment

- Nix is available and is the expected way to run project tooling.
- `.envrc` contains `use flake`, so `direnv allow` can load the same
  environment automatically.
- Prefer explicit one-shot commands when running validation from an agent:

```bash
nix develop --command ansible-lint
nix develop --command ansible-lint roles/example/tasks/main.yaml
nix develop --command ansible-galaxy install -r requirements.yaml
```

- Do not trust ambient user-level `ansible-lint`; it may resolve to a broken
  Python environment outside the flake dev shell.

## Flake

`flake.nix` defines the default dev shell. It includes:

- `python3`
- Python packages derived from `requirements.txt`
- `ansible`
- `ansible-lint`
- `net-snmp`
- `sops`
- `git`
- `ipython`

Run this after changing the flake or lock file:

```bash
nix flake check
```

## Validation

Run linting through the dev shell:

```bash
nix develop --command ansible-lint
```

For focused changes, lint the touched file or role where practical:

```bash
nix develop --command ansible-lint roles/openwrt_gammu/tasks/sshtunnel.yaml
```

If Galaxy dependencies are missing or stale:

```bash
nix develop --command ansible-galaxy install -r requirements.yaml
```

The GitHub workflow also passes `requirements.yaml` to the official
`ansible/ansible-lint` action.

## Local Style

- Follow repo-root `AGENTS.md`.
- Keep edits focused and avoid unrelated YAML formatting churn.
- Prefer fully qualified built-in Ansible module names where practical.
- Preserve existing role, task, handler, and playbook organization.
- Handle SOPS files, inventory, host vars, and group vars as sensitive.
- Never commit decrypted secrets or temporary credential material.
