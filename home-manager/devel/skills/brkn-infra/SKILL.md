---
name: brkn-infra
description: Use when you need to know which host does what in the user's own infrastructure (fnuc, lrz, rofl-*, oci-*, ge2, gk4, x13, Raspberry Pis, routers, APs, phones and tablets), which host to build, test or deploy on, or where a host's details live (NixOS config, Ansible inventory, NetBox). Also covers the Android devices and which skill handles them.
---

# brkn-infra

Host names, roles and purposes live here, not in the `AGENTS.md` of individual projects. Those
files say "a build host" or "the test workstation" and point to this skill.

## Where the truth is

| Question | Source |
|---|---|
| What is it, what hardware, role, status, purchase data | NetBox (`netbox` skill, `https://netbox.brkn.lol`). It wins on hardware and status. |
| How is a NixOS host configured | `nixos-config` `hosts/<host>/` and `profiles/` (`nix` skill) |
| Private parts of a host (secrets, private services) | `nixos-config-private` `hosts/<host>/` |
| Routers, APs, switches, Shelly devices, upgrade runbooks | `ansible-stuff` `inventory.yaml`, `host_vars/` (`ansible-stuff` skill) |
| Home Assistant, its VM and config | `/mnt/ha` (`ha` skill) |
| Phones and tablets | `references/android.md` |

## Reference map

- `references/hosts.md`: every host with its purpose, what runs there and what to use it for.
- `references/android.md`: the Android devices, their purpose and the skills and repos that manage
  them.

## Defaults worth knowing

- Evaluate and build on a build host (rofl-13, fallback rofl-14), never on the machine the agent
  runs on. Details and scripts: `nix` skill.
- The agent usually runs on fnuc, which hosts the Home Assistant VM. Keep it light.
- The interactive test workstation for desktop and UI work is gk4 (`ssh gk4`); ask which machine
  the user is working on first.
- `NetBox` and the repos can disagree (for example a host's status). Say so instead of picking
  silently, and fix the stale one when asked.
