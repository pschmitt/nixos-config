# GitHub-hosted runners

Use `gh-aarch64` for native ARM64 builds when the checkout and its dependencies
can run in the configured GitHub Actions repository. Use `gh-x86_64` (or
`gh`) for native x86-64. The workflow currently belongs to the rworker repo.
For jobs from other projects, check that the workflow belongs to the project
being built. Use OpenStack for builds that need private inputs or the private
Nix caches.

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
CPU and RAM allocations under the `github-actions` tag, plus disk size and
free space measured at the latest startup. GitHub runners start with Nix.
Use an OpenStack worker when a build requires the worker-image niks3
shortcuts or private cache credentials.
