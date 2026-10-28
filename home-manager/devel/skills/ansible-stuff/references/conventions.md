# Ansible Stuff Conventions

## Repository

The private Ansible repository is located at:

```text
~/devel/private/pschmitt/ansible-stuff.git
```

## Environment

- Nix is available and is the expected way to run project tooling.
- Prefer explicit one-shot commands when running validation from an agent:

```bash
nix develop --command ansible-lint
nix develop --command ansible-lint roles/example/tasks/main.yaml
nix develop --command ansible-galaxy install -r requirements.yml
```

- Do not trust ambient user-level `ansible-lint`; it may resolve to a broken
  Python environment outside the flake dev shell.

## Flake

`flake.nix` defines the default dev shell (Ansible, ansible-lint, sops and the
Python packages from `requirements.txt`; read `flake.nix` for the full list).

After changing the flake or lock file, run `nix flake check` on rofl-13/rofl-14
(rsync the checkout to `~/build/ansible-stuff`), not on the local host
(expensive Nix evaluation and checks).

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
nix develop --command ansible-galaxy install -r requirements.yml
```

The GitHub workflow also passes `requirements.yml` to the official
`ansible/ansible-lint` action.

## Local Style

- Follow repo-root `AGENTS.md`.
- Keep edits focused and avoid unrelated YAML formatting churn.
- Prefer fully qualified built-in Ansible module names where practical.
- Preserve existing role, task, handler, and playbook organization.
- Handle SOPS files, inventory, host vars, and group vars as sensitive.
- Never commit decrypted secrets or temporary credential material.
