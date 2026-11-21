# Circus CI

[Circus](https://github.com/manic-systems/circus) evaluates and builds the
configured repositories. It reports build statuses to GitHub under
`circus/<job>` and keeps a summary comment updated on each pull request.

## Layout

| Host | Units | Notes |
| --- | --- | --- |
| rofl-15 | `circus-server`, `circus-evaluator`, `circus-queue-runner`, `postgresql`, nginx | `default.nix` |
| rofl-15, rofl-16 | `circus-agent` | `agent.nix` |
| GitHub Actions (opt-in) | ephemeral aarch64 `circus-agent` | `.github/workflows/circus-builder.yml` |
| rworker (on demand) | one x86_64 QEMU `circus-agent` for delayed ARM overflow | `hosts/rworker-circus-qemu` |

Server, evaluator and queue-runner must share one Nix store, so they run on
one host. The server's `/nix-cache/` reads `.drv` files from the local Nix
database, and the queue-runner reads them from disk. The evaluator has no
remote-store option.

The queue-runner never builds: `workers = 0` and `local_systems = []`, enforced
by an assertion (`services.circus.allowLocalBuilds`). Every build goes to an
agent.

| Endpoint | Where | Access |
| --- | --- | --- |
| `https://circus.brkn.lol` | nginx, rofl-15 | Authelia |
| `https://circus.brkn.lol/api/v1/webhooks/` | nginx, rofl-15 | public, HMAC (`githubWebhook.enable`) |
| `https://circus.rofl-15.nb.brkn.lol/nix-cache/` | nginx, rofl-15 | NetBird and Tailscale addresses only |
| `circus://rofl-15.nb.brkn.lol:8443` (agent RPC) | queue-runner | trusted tailnet interfaces only |
| `127.0.0.1:3000` | circus-server | local |

Sign in to [the build dashboard](https://build.brkn.lol/dash) through Authelia
OIDC. For `circusctl` and API access, the admin API key is in the "API Token"
field of the rbw entry `circus.brkn.lol`. Dashboard sessions use secure cookies
over TLS.

## Evaluation

The evaluator is pure and restricted, like nixbot (`restrict_eval`,
`pure-eval = true`, IFD allowed). With an impure evaluator, the lazyvim-nix
Home Manager module stats `/home/<user>/.config/nvim/lua/plugins` at
evaluation time (`pfassina/lazyvim-nix`, `nix/module.nix`), so hosts with the
nvim module failed with EACCES. The unit also runs with `ProtectHome`.

## Resources (rofl-15: 62 GiB, 32 cores)

| Unit | Limit |
| --- | --- |
| `circus-evaluator` | One 24 GiB worker and one evaluation at a time. `MemoryHigh` 26G, `MemoryMax` 30G, `CPUQuota` 800% |
| `circus-queue-runner` | `MemoryMax` 4G, `CPUQuota` 200% (verifies and signs agent outputs) |
| `circus-server` | `MemoryMax` 2G |
| `circus-agent` (each) | 4 builds, 4 cores each; the queue-runner skips a builder above 60% PSI |

Agent builds run in the Nix daemon's cgroup. The slot limits and PSI threshold
leave capacity for other services on the build hosts.

## Secrets (host SOPS files)

| Key | Host | Source |
| --- | --- | --- |
| `circus/admin-api-key` | rofl-15 | generated |
| `circus/users/pschmitt-password` | rofl-15 | dashboard password (rbw `circus.brkn.lol`) |
| `circus/cache-signing-key` | rofl-15 | generated, public key in `default.nix` |
| `circus/webhook-encryption-key` | rofl-15 | generated |
| `circus/github-webhook-secret` | rofl-15 | the GitHub App's webhook secret |
| `circus/agent-join-token`, `…-sha256` | rofl-15, rofl-16 | generated |
| `circus/github-app/app-id`, `circus/github-app/private-key` | rofl-15 | GitHub App `circus-pschmitt` (id, PEM key) |
| `circus/github-status-token` | rofl-15 | only without `githubApp`: fine-grained token, commit statuses read/write on `pschmitt/nixos-config` |
| `circus/s3/access-key-id`, `circus/s3/secret-access-key` | rofl-15 | private `tofu/circus-cache.tf` output |
| `circus/github-dispatch-token` | rofl-15 | only without `githubApp`: fine-grained token, actions read/write on `pschmitt/nixos-config` |

## Opt-in parts

Each needs its secret first; a missing SOPS key fails activation.

- `services.circus.githubStatuses.enable`: commit statuses, as the GitHub App
  with `githubApp.enable`, else with `circus/github-status-token`.
- `services.circus.githubApp.enable`: the GitHub App `circus-pschmitt`
  (statuses write; contents and metadata read; pull requests read/write;
  installed on `pschmitt/nixos-config` and the four public pilot repositories).
  `circus-github-token.timer` mints an installation
  token every 45 minutes (the installation is looked up via
  `GET /repos/<githubApp.repository>/installation`) into
  `/run/circus-github-token/token` (root:circus-github-token, 0440). The
  evaluator and queue-runner read it on every status: our fork
  `github:pschmitt/circus` re-reads token files instead of caching them at
  startup, and the path is passed as `CIRCUS_NOTIFICATIONS__GITHUB_TOKEN_FILE`
  because the upstream module copies `*_file` settings once, at service start.
  A failed mint keeps the previous token; Monit restarts the minter when the
  token is older than 70 minutes. Check with
  `systemctl status circus-github-token`.
- `services.circus.githubWebhook.enable` enables pull-request evaluations.
  The App sends signed push and pull request events to
  `https://circus.brkn.lol/api/v1/webhooks/github`. Circus selects the project by
  repository and verifies the delivery using `circus/github-webhook-secret`.
  With the GitHub App and status reporting enabled, Circus keeps one comment
  current with evaluation and build results for the PR head.
- `services.circus.s3Upload.enable`: agents upload outputs to niks3's
  `nix-cache-brkn-lol` under the `circus/` prefix. Without it, outputs stream
  to the queue-runner.
- `services.circus.rworkerPool.enable`: ephemeral agents on rworkers. The
  autoscaler on rofl-10 (private `services/rworker-circus-pool.nix`) polls
  `/api/v1/operator/queue` on the tailnet-only vhost with a read-only API key
  and creates up to 3 `circus-*` VMs from the `rworker-circus` image
  (`hosts/rworker-circus`) when more than 8 builds stay queued for two minutes.
  Each worker gets the pool's join token (`rworker-pool`) in its user-data;
  only root on the worker can reach the metadata service. Idle workers are
  deleted after 15 minutes. A separate one-worker QEMU pool handles feature-free
  ARM jobs only after they have waited 120 seconds and the native ARM pool has
  no matched live or launched capacity. Its x86_64 image uses qemu-user/binfmt,
  advertises only `aarch64-linux`, and never advertises `big-parallel`. The
  queue-runner rechecks native agents first when it reserves a job.
- `services.circus.githubActionsAgents.enable` with `agentBinaryUrl` and
  `agentBinarySha256`: aarch64 agents on GitHub's arm runners for the
  aarch64 hosts and packages of `circusJobs` (nixbot builds x86_64 only).
  - Dispatch: the queue-runner starts `.github/workflows/circus-builder.yml`
    via `workflow_dispatch` with the App's installation token (the App has
    Actions: write; the token file is read in place, `runtimeFiles`).
  - Agent binary: a static `circus-agent-aarch64-linux` released from our
    fork by its `release-agent-aarch64.yml` on `v*-pschmitt.*` tags; the
    workflow checks the `#sha256=` fragment before running it. Cut a new
    tag and update both options whenever the `circus` input moves.
  - Network: runners join NetBird with `NB_SETUP_KEY` (setup key "GitHub
    Actions", auto-group `🐙 github-actions`); policy `github-actions →
    circus` allows TCP 443 and 8443 to rofl-15.
  - Substitution: `.github/actions/nix-setup` with the read-only niks3
    secrets `NIKS3_S3_*`.
  - The main pool builds trusted branch commits. A separate workflow and OIDC
    identity build current same-repository PR heads from GitHub accounts listed
    in `pullRequestAuthorIdsFile`. The PR workflow uploads outputs through
    Circus's per-build S3 URLs.

## Effects (`services.circus.effects`)

`circus-effects` runs the flake's push effects with `nbo effects run` in the
same sandbox and with the same secrets format as nixbot. It resolves the ISO
and worker image store paths for the current `main` commit and checks the Circus
cache once a minute. Each effect can run as soon as its own artifact is
cached or restored from S3 into the local Nix store. A commit check immediately
before publishing prevents an older commit
from replacing a newer artifact.

- Effects respect `after` dependencies, `lock` and `when.changed`. The runner
  records completed effects per commit in `/var/lib/circus-effects`.
- `dryRun = true` logs the effects that would run and tracks them separately
  from live publishing.
- Cutover requires a dry run with cached artifacts, then stopping nixbot before
  enabling live Circus effects. Keep `herculesCI.onPush.publish` so Circus can
  discover the effects. Check the first live run in the journal and in the
  `circus-effects/<effect>` commit statuses.

The effects' inputs (ISOs, images) are fetched by rofl-15's Nix daemon through
the local Circus HTTP cache. The effects module registers that substituter
and trusts the configured Circus signing key.

The LAN mirror polls Git for the current `main` commit and resolves each
configured host's successful output through Circus over NetBird. It fetches
the signed closure through Nix and keeps its previous GC root while a new
build is pending or a fetch fails.

## Disable or remove

Disable: remove `../../services/circus` from `hosts/rofl-15/default.nix` and
`../../services/circus/agent.nix` from `hosts/rofl-16/default.nix`. The
database stays in PostgreSQL on rofl-15 (`circus`), preserving build history.
