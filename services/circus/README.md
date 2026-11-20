# Circus CI (trial)

[Circus](https://github.com/manic-systems/circus) runs next to nixbot to compare
the two. It reports to GitHub under its own `circus/<job>` contexts, which are
never required checks. nixbot stays the CI of record.

## Layout

| Host | Units | Notes |
| --- | --- | --- |
| rofl-15 | `circus-server`, `circus-evaluator`, `circus-queue-runner`, `postgresql`, nginx | `default.nix` |
| rofl-15, rofl-16 | `circus-agent` | `agent.nix` |
| GitHub Actions (opt-in) | ephemeral aarch64 `circus-agent` | `.github/workflows/circus-builder.yml` |

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

Sign in at `https://circus.brkn.lol` (after Authelia) with the rbw entry
`circus.brkn.lol`: user `pschmitt`, whose admin API key (for `circusctl` and
the API) is in its "API Token" field. The session cookie is always `Secure`
(`force_secure_cookies`), which is fine since nginx serves the dashboard only
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
| `circus-evaluator` | 2 workers, 10 GiB each, one evaluation at a time; `MemoryHigh` 12G, `MemoryMax` 16G, `CPUQuota` 400% |
| `circus-queue-runner` | `MemoryMax` 4G, `CPUQuota` 200% (verifies and signs agent outputs) |
| `circus-server` | `MemoryMax` 2G |
| `circus-agent` (each) | 4 builds, 4 cores each; the queue-runner skips a builder above 60% PSI |

nixbot's remote evaluation (up to 2 × 2 × 8 GiB) and its 16 build slots share
these hosts. Agent builds run in the Nix daemon's cgroup, so the PSI threshold
and the low slot count are what keep nixbot ahead.

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
| `circus/github-dispatch-token` | rofl-15 | fine-grained token, actions read/write on `pschmitt/nixos-config` |

## Opt-in parts

Each needs its secret first; a missing SOPS key fails activation.

- `services.circus.githubStatuses.enable`: commit statuses, as the GitHub App
  with `githubApp.enable`, else with `circus/github-status-token`.
- `services.circus.githubApp.enable`: the GitHub App `circus-pschmitt`
  (statuses write; contents, metadata and pull requests read; installed on
  `pschmitt/nixos-config`). `circus-github-token.timer` mints an installation
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
- `services.circus.githubWebhook.enable`: pull-request evaluations. The App's
  webhook (events push and pull request) points at
  `https://circus.brkn.lol/api/v1/webhooks/a17bcd61-5372-4d1f-8bba-f32bcb011f97/github`
  (project `nixos-config`) and is signed with `circus/github-webhook-secret`.
- `services.circus.s3Upload.enable`: agents upload outputs to niks3's
  `nix-cache-brkn-lol` under the `circus/` prefix. Without it, outputs stream
  to the queue-runner.
- `services.circus.githubActionsAgents.enable` with `agentBinaryUrl`: aarch64
  agents on GitHub's arm runners. The runners join NetBird with the existing
  `NB_SETUP_KEY`; that key's group needs a NetBird policy to rofl-15 TCP 443
  and 8443. Circus only gives them builds of `main`, never pull requests.

## Disable or remove

Disable: remove `../../services/circus` from `hosts/rofl-15/default.nix` and
`../../services/circus/agent.nix` from `hosts/rofl-16/default.nix`. The
database stays in PostgreSQL on rofl-15 (`circus`); drop it with
`sudo -u postgres dropdb circus` once the trial is over. Then remove the
`circus` input from `flake.nix`, this directory, the workflow, the SOPS keys
and the private `tofu/circus-cache.tf`.
