---
name: circus-build
description: Queue, prioritize, and monitor Circus builds of local or pushed NixOS configurations, especially aarch64 phone configurations on GitHub ARM runners.
---

# Circus builds

Use the `nixos-config` project's `main` jobset for phone configurations.
The phone guest closure is `termuxppConfigurations.<host>.system`.
Standard NixOS host closures use `nixosConfigurations.<host>.config.system.build.toplevel`. Resolve the requested phone host names from the configuration or
the private brkn-infra skill. For uncommitted changes, submit the local public checkout. For a requested
pushed revision, verify it is reachable from remote `main` before using the
trusted jobset.

## API access

Find the API access details in `services/circus/README.md` in the NixOS
repository. If the public endpoint redirects to Authelia, use an SSH
local forward to the Circus server's loopback listener. If already on the
server, use loopback directly. Follow secret-hygiene and rbw when retrieving
the API key. Pass it through `CIRCUS_API_KEY` for `circusctl`, or feed the
Bearer header to curl on stdin with `--header @-`. Keep tracing off and
scope credentials and any SSH forward to this task.

The API paths below are relative to `/api/v1`.

1. Find the project and jobset IDs with `GET /projects` and
   `GET /projects/<project-id>/jobsets`. Check existing evaluations with
   `GET /evaluations?jobset_id=<jobset-id>`. Reuse an evaluation for the
   exact SHA with the requested jobs already queued, running, or successful,
   or one that is still evaluating that SHA. Follow pagination where needed.
2. If a fresh evaluation is needed, use
   `circusctl --json evaluations trigger --jobset-id <jobset-id> --commit-hash <sha>`.
   The API equivalent is `POST /evaluations/trigger` with JSON fields
   `jobset_id` and `commit_hash`. Save the returned evaluation ID. A manual
   trigger evaluates the whole jobset and can queue other uncached jobs.
3. Check `GET /evaluations/<evaluation-id>` and find the requested builds with
   `GET /builds?evaluation_id=<evaluation-id>&system=aarch64-linux&job_name=<job>`.
   Use `hosts.<host>` for NixOS or `packages.aarch64-linux.termuxpp-system-<host>`
   for a pushed phone guest.
   If a job is absent after evaluation completes, check the evaluation
   detail and job history for an error or a reused build for that revision.

## Submit a local checkout

Use a Circus client and server that support snapshot submission. The client
package in the Circus flake is `circus-cli` and its executable is `circusctl`.
Find the same `main` jobset ID as above and run:

```bash
circusctl --json evaluations submit --jobset-id "$jobset_id" \
  --checkout "$checkout" --termuxpp --hosts "$comma_separated_hosts" \
  --pool gha-aarch64-linux
```

Omit `--termuxpp` for standard NixOS host closures. Snapshot phone jobs are
named `termuxpp-system-<host>`.

Use `--pool gha-aarch64-linux` to require a native GitHub ARM worker from
that pool. Use `--agent <machine-id>` to require one worker. Find agent
machine IDs via `GET /admin/builders/sessions/connected`. Add `--fallback`
with `--agent` only when another compatible worker is acceptable.
Prerequisites can use other systems.

Pass `--front` when asked to put the snapshot ahead of ordinary pending
evaluations and eligible builds. Active work continues.

This snapshots tracked and non-ignored untracked files with their working-tree
contents. Inspect new files for private material before submission. The
snapshot uses the checkout's lock file and supports changes to the public tree.
Use the rworker skill for an uncommitted private checkout override.
The server queues just the selected hosts and their prerequisites. Snapshot
builds start with a 10-point priority increase by default. Pass
`--normal-priority` to skip it. Track the returned evaluation ID and do not
bump these builds a second time.

## Priority and builder

For a pushed revision, bump each requested pending host build and its pending
prerequisite builds once. Skip the bump when the user asks for normal
priority. Walk `GET /builds/<build-id>/dependencies` and deduplicate IDs
across the requested hosts. Recheck state before running
`circusctl builds bump <build-id>` or `POST /builds/<build-id>/bump`.
A bump adds 10 priority points. Higher-priority ready work is considered
first, subject to matching capacity. Running work continues, and a build
that starts during the bump can be left alone.

The queue-runner can dispatch eligible `aarch64-linux` jobs from the
trusted jobset to the GitHub ARM pool. Let Circus dispatch the workflow.
Priority affects queue order. Builder selection follows pool eligibility,
capacity and fallback policy, so check the assigned builder before
reporting where it ran.

Return the commit, evaluation and build links, priority changes, and
current status for each requested host. If asked to wait, track the selected
builds to their terminal states and report the output store paths or the
specific failed prerequisite. Keep the operation build-only unless the
user also requests deployment.
