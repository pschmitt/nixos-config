# GitHub-hosted runners

Use `gh-aarch64` for native ARM64 builds when the checkout and its dependencies
can run in the configured GitHub Actions repository. Use `gh-x86_64` (or
`gh`) for native x86-64. The workflow currently belongs to the rworker repo.
For jobs from other projects, check that the workflow belongs to the project
being built. `up`, `exec` and `ssh --create` give GitHub and GitLab leases
the private S3 cache, this host's flake access tokens and a niks3 push token,
like OpenStack workers (`--no-nix-cache`, `--no-nix-auth`, `--no-niks3-token`,
or `--no-credentials` for none), so private inputs build there too.

```bash
rworker exec --profile gh-aarch64 --ttl 30m --topic "Native ARM64 build" \
  --agent-id "<agent-id>" --sync .:src --fetch src/target/release/rworker:./rworker -- \
  'cd src && nix develop -c cargo build --release'
```

Adjust the command and fetch path to the project. `--sync` transfers the
working tree, including local edits. Choose the directories deliberately
and keep secrets out of the transferred files.

`rworker up --profile gh-aarch64 --ssh --topic "Native ARM64 session"` opens an
interactive shell. GitHub workers appear as `gha-…`. They use the
`rworker-build` account, pinned SSH keys, and the controller relay. Use
`rworker sync`, `rworker cp`, and `rworker down` as usual. The lease defaults
to 30 minutes, including queue time, and can be set to at most two hours.
Running `down` cancels the GitHub workflow. Use `rworker logs WORKER --cached`
for archived `exec` output after the worker ends.

The agent enables KVM when the build user can create a VM through `/dev/kvm`.
Check the `KVM` line from `up`. The live x86-64 trial had KVM and the ARM64
trial had no usable KVM device. `rworker profiles` shows GitHub's published
CPU and RAM allocations under the `github-actions` tag, plus the last observed total
disk size. GitHub runners start with Nix.
On a GitHub lease the build user's Nix uses the lease's own store
(`~/.local/share/nix/rworker`) once `setup nix` ran, so plain `nix build` and
`niks3 push --stdin` work in `rworker ssh`/`start` sessions. A lease created
with `--no-credentials` has no such config: select that store yourself
(`NIX_CONFIG="build-users-group =\nsandbox = true\nstore = $HOME/.local/share/nix/rworker"`),
or Nix runs as an untrusted user and ignores `--option extra-substituters`.
GitHub leases do not forward the ssh-agent.
