# CI build policy

The build workflow compares the PR base (or the previous main commit) with
its checkout. It uses paths, not PR authors or titles, to select targets:

- Markdown, `docs/`, and PR reporter/release-note automation changes: no builds
  or host evaluation in the build workflow.
- Files inside a known package directory: build that package on its supported
  architectures and evaluate every host, without building host closures.
- Files inside known host directories only: evaluate and build just those hosts.
  Package metadata and unrelated host modules are not evaluated.
- Service-only changes (including container tag bumps): compare evaluated host
  and Android derivations against the base and build only changed systems;
  skip the standalone package matrix. Successful derivation paths are cached by
  exact commit, target and evaluator version, so unchanged baselines can be reused.
  Missing or invalid cache entries are evaluated again; failed evaluations are
  never cached. Restored caches retain only the two compared revisions.
- Shared definitions, lock files, workflows, unknown paths, or manual runs:
  evaluate and build all targets.
- Draft PRs: defer the build workflow until ready for review.

Mixed changes select the union of targets; any shared or unknown path selects
full validation. A weekly full run also covers reverse dependencies. A package-only change does not build its reverse dependencies;
shared definition changes and broad input updates get full builds.

The build setup skips Nix installation and cache restoration for documentation
and reporting-only changes. The `Lint` workflow runs four parallel jobs over
every tracked file of their kind: Actionlint; statix, deadnix and nixfmt;
ShellCheck and Ruff; and the CI regression tests. New files are covered without
editing a list: opt out with the linter's own directives (`# shellcheck
disable=...`, `# noqa`). Linters come from the locked nixpkgs, settings from
`.shellcheckrc` and `ruff.toml`; `.github/workflows/scripts/lint.sh nix|scripts`
runs the same checks locally. The stable `Nix build result` check aggregates
selected builds; intentional skips pass, while failures and cancellations fail.

The aarch64 build matrices run natively on GitHub arm runners, up to eight
jobs each, outside the runner budget below. New commits cancel obsolete PR
builds; main runs finish so their outputs reach niks3.

ISO and Raspberry Pi images build weekly and on manual dispatch. Package
updates run daily, with two concurrent update jobs per category. Eligible patch
updates receive a label; a short workflow checks their current versions, policy,
commit and CI results after builds finish, with an hourly retry. No runner waits
for another workflow. The merge workflow only executes default-branch code. Main-branch completions do
not trigger redundant merge checks. Updater workflows have bounded timeouts and
serialize overlapping scheduled/manual runs without interrupting active updates.

Matrix evaluation has authenticated SSH access and ARM emulation for Android
import-from-derivation helpers. Successful derivation snapshots are saved even
when a different target fails.

CI first checks the primary store on rofl-14. A cache hit is retained remotely
without building or downloading its closure to the runner; proprietary-source,
QEMU and Netbird setup are skipped where unnecessary. Cache misses are signed,
copied to the primary and rooted after signature verification through Harmonia.
Incoming closures are checked against available space, keeping a 15 GiB reserve.

The persistent population worker on rofl-14 fills missing main outputs in bounded
passes and replicates retained main closures to rofl-13. Main retains the latest
successful output per target; PR/manual roots expire after three days. The worker
also imports a canary through authenticated HTTPS into an empty store and verifies
signatures and contents. See [cache operations](../services/harmonia/README.md)
for limits, state and failure reporting. The Actions cache accelerates evaluation;
Harmonia and explicit GC roots provide the artifact cache and retention.

## PR impact comments

The impact job compares the PR branch point and head commits, so changes that
landed on main after the branch forked are not incorrectly attributed to the PR. Each selected
configuration is evaluated once per revision for its kernel, system/Home Manager
package names and versions, and OCI image references defined entirely in public modules. Two workers bound memory
and CPU use. Successful JSON snapshots are cached by commit, target and snapshot
schema, so synchronizing a PR can reuse its base evaluation.

Identical changes are grouped in one editable bot comment. Unchanged targets
are collapsed; evaluation failures are explicit and fail the job. The artifact
contains full Markdown and JSON reports. ISO configurations are excluded from
broad changes, but included when their host directory is edited or explicitly
selected. Stale standalone Home Manager profiles are not evaluated.

The manual trigger accepts an open PR number. Reporter code comes from the
default branch, and obsolete runs cannot replace a newer head's comment.
The report describes metadata changes, not full system closures or runtime
service settings; unchanged versions do not prove unchanged package contents.

Package update PRs store their generated body in a file. Upstream release notes
are collapsed, line endings normalized, relative links point to the tagged
upstream repository, and long notes link to the complete release. A release
that only links to a Markdown changelog also includes the public file from its
release tag, while retaining the original link. Code fences
are preserved and closed before ending the collapsible section.

## Runner budget

Most checked-in workflow jobs share two repository-wide concurrency groups:

- `nixos-config-runner-nix`: one Nix evaluation, update or image job.
- `nixos-config-runner-light`: one merge or final-result job.

Each group allows one occupied runner across all PRs. The `Lint` jobs and the
aarch64 builds are outside the budget.
`queue: max` lets jobs wait without consuming runners or replacing other PRs'
pending jobs (up to GitHub's 100-job queue limit per group). Workflow-level
concurrency still cancels obsolete runs for the same PR/ref. Matrix limits alone
only apply inside one matrix and cannot enforce this repository-wide budget.

GitHub-managed default CodeQL setup and other automatically generated workflows
are outside this budget. CodeQL needs an explicit advanced-setup workflow using
these groups to join the limit. Already-running revisions keep their old policy;
existing PR branches acquire the budget when updated from main.
