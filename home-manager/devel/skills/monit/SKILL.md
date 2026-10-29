---
name: monit
description: Inspect live Monit alerts on the rofl-* and oci-* VMs, plus fnuc, turris, and brkn-ap, over SSH; identify root causes, fix clear low-risk issues, and report unresolved incidents with a concrete plan.
---

# Monit

Use live SSH state as the source of truth. For a Monit investigation, read the
[triage runbook](references/runbook.md) before checking hosts. It covers inventory,
diagnosis, bounded repairs, verification, and incident reporting.

The runbook permits one specific recovery that crosses the usual no-deploy boundary:
restart a failed `nixos-upgrade.service` when logs confirm the root user activation
failed because its D-Bus session was unavailable. Do not reboot hosts or make other
configuration, secret, network, or monitoring-policy changes without authorization.
