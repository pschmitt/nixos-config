# CI build policy

The build workflow compares the PR base (or the previous main commit) with
its checkout. It uses paths, not PR authors or titles, to select targets:

- Markdown and `docs/` changes: no builds or host evaluation.
- Files inside a known package directory: build that package on its supported
  architectures and evaluate every host, without building host closures.
- Files inside a known host directory: build that host and evaluate every host.
- Service-only changes (including container tag bumps): compare evaluated host
  and Android derivations against the base and build only changed systems;
  skip the standalone package matrix.
- Shared definitions, lock files, workflows, unknown paths, or manual runs:
  evaluate and build all targets.
- Draft PRs: defer the build workflow until ready for review.

Mixed changes select the union of targets; any shared or unknown path selects
full validation. A weekly full run also covers reverse dependencies. A package-only change does not build its reverse dependencies;
shared definition changes and broad input updates get full builds.

Each build matrix runs one job at a time. The package categories can occupy
three runners together; the host/Android phase can also occupy three.
This is a per-run limit, not an account-wide limit. Separate PRs can overlap.
New commits cancel obsolete builds of the same branch or PR.

ISO and Raspberry Pi images build weekly and on manual dispatch. Package
updates run daily, with two concurrent update jobs per category. Eligible patch
updates receive a label; a short workflow checks their current versions, policy,
commit and CI results after builds finish, with an hourly retry. No runner waits
for another workflow. The merge workflow only executes default-branch code.

Build outputs continue to be copied to the persistent remote Nix store and reused
through the SSH substituter. The Actions cache primarily accelerates evaluation;
it is not the repository's binary build cache.
