# Secrets and private inputs

Credentials the task needs may be sent to a worker. Workers are private and
temporary, and the user allows it without asking each time: this holds for
the S3 cache credentials, a GitHub token for a private flake input and
whatever else the build or test needs. For a private flake input you can also
transfer a checkout at the exact revision pinned in `flake.lock` and use
`--override-input NAME path:<worker-checkout>`. Verify the revision first; a
dirty checkout changes what is evaluated. Remember that Nix may copy the
source into the worker's world-readable store: never include plaintext
secrets. `rworker sync` does **not** exclude `.git` by itself.

Sending a credential does not make it safe to show. The worker user and
administrators can read it, and processes or tools may copy or log it, so keep
it out of the transcript: pass it as a file, never in MCP arguments,
command-line arguments, Git, Nix expressions or the Nix store, avoid shell
tracing and commands that print it, and delete it before `down`. A narrow,
short-lived credential is nicer when it is cheap to get, but it is not
required. Prefer sending just the file or entry the job needs over a whole
credentials directory or the SSH agent.

The worker may remove an agent user's `/dev/shm` files when its last SSH login
ends. If the next command needs the file, keep one SSH session open through
the transfer and consumption, or send it on stdin to the consuming command in
the same SSH session. For a locally prepared mode-0600 `secret_file`:

```bash
rworker ssh "$w" 'umask 077; d=$(mktemp -d /dev/shm/rworker-secret.XXXXXXXX); trap '\''rm -rf "$d"'\'' EXIT; cat > "$d/credential"; your-command "$d/credential"' < "$secret_file"
```

Check each step; if transfer or the job fails, still remove the directory and
tear down the worker. Remove any local temporary secret file, revoke temporary tokens
when finished, and always `down` the worker. Do not assume deletion erases
copies made by the workload.

For private flake fetches, prepare a minimal Nix user configuration without
printing tokens. Include `access-tokens` for every private host, including nested
inputs: overriding the parent does not authenticate its dependencies. GitLab
tokens need a `PAT:` or `OAuth2:` prefix. Set `NIX_USER_CONF_FILES` to this file
for the worker's Nix command; it replaces the normal user configuration and
authenticates client fetches, not build sandboxes or daemon-side cache access.
Do not put tokens in `NIX_CONFIG` or arguments. `nix-cache` handles S3 separately.

On hosts with our Home Manager Nix configuration, the rendered SOPS template
already contains the GitHub and WIIT GitLab entries, including those needed by
the private configuration's nested inputs. Set up an existing worker in one
step (the file stays on its encrypted disk, readable only by the worker user):

```bash
rworker ssh "$w" 'umask 077 && mkdir -p "$HOME/.config/rworker" && chmod 700 "$HOME/.config/rworker" && install -m 600 /dev/stdin "$HOME/.config/rworker/nix-auth.conf"' < "$HOME/.config/sops-nix/secrets/rendered/nix-access-tokens"
rworker ssh "$w" "cd repo && NIX_USER_CONF_FILES=\$HOME/.config/rworker/nix-auth.conf nix eval --json '.#nixosConfigurations.example.config.system.build.toplevel.drvPath'"
rworker ssh "$w" 'rm -f "$HOME/.config/rworker/nix-auth.conf"'
```

Use the synced checkout and desired command; keep the config until fetching is
done. If the template is unavailable, use the minimal-config method above.
Remove the file even on failure and then tear down the worker as usual.

