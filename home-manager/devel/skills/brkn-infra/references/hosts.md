# Hosts

Roles are taken from `nixos-config` (`hosts/`, `profiles/specializations/`), the services each host
imports, the `ansible-stuff` inventory and NetBox (checked 2026-10-30). Hardware and status are
NetBox's. Re-check a row against the source before you rely on it for something risky.

## NixOS servers and VMs

| Host | Purpose | Notes |
|---|---|---|
| fnuc | Home server (homelab-server profile). Runs the Home Assistant VM, a binary cache (harmonia) with a LAN mirror, the agent hosts' warmup jobs and go-hass-agent. Where the agent normally runs. | Intel NUC (NetBox: NUC10i7FNH, status `inventory`). Keep load low: HA is mission critical. Deploy: `just deploy` without a target when on it; see `nix` skill for prebuilt closures. |
| lrz | Second home server (homelab-server profile) with its own HA VM definition and a LAN cache, set up as fnuc's NixOS-install replacement. | NetBox: ThinkCentre M75q-1, status `inventory`. The profile comment calls it the same box as fnuc; NetBox lists different hardware. Treat that as unresolved. |
| rofl-10 | Main service VM: auth (Authelia), NetBox, Nextcloud, Immich, Paperless-ngx, Vaultwarden, n8n, Forgejo, Matrix, Glance, nixbot, the public browser handoff, teams-live and many more. | Cloud VM (`cloud` group). Biggest blast radius; check `hosts/rofl-10/services.nix`. |
| rofl-11 | Media and NFS: Audiobookshelf, NFS server, Tor. | Cloud VM. |
| rofl-12 | NFS client and Tor. | Cloud VM. |
| rofl-13, rofl-14 | Build nodes (rofl-build-node profile): nixbot workers, harmonia store serving, Forgejo runner, ESPHome builds, headless browsers. Preferred hosts for agent builds and Nix evaluation. | Cloud VMs. Do not leave long jobs running; they are shared. Build dirs under `~/build/<project>`. |
| rofl-15, rofl-16 | More build nodes with the same profile. | Not in the Ansible inventory. |
| oci-01 | Public mail and web: Stalwart mail, Roundcube, healthchecks, mail autoconfig, public nginx. | Oracle Cloud. |
| oci-03 | Monitoring: M/Monit, monarch, parsedmarc. | Oracle Cloud. |
| test-delete-oci, test-delete-os | Throwaway test VMs for provisioning. | Safe to rebuild or remove. |
| falcon-sensor-vm | VM that runs the work endpoint-security sensor, used from ge2. | Work requirement; do not remove. |
| iso, iso-private | Installer images. | Built with `just build-iso`. |

Ansible runs against the same fleet (`cloud` and `nixos` groups). Playbooks of note:
`nixos-upgrade`, `luks-unlock`, `reboot-all`, `reboot-cloud`, `netbox-reconcile`.

## Workstations

| Host | Purpose | Notes |
|---|---|---|
| ge2 | Main desktop (workstation profile): Nvidia GPU, Stream Deck, OBS capture, lan-mouse, the work sensor VM. | NetBox: Dell Precision 5680. Often powered off; check before a deploy. |
| gk4 | Handheld laptop and the designated interactive test machine for desktop UI, Hyprland and browser-extension work. | NetBox: GPD Pocket 4. Often powered off. |
| x13 | Older ThinkPad (workstation profile). | NetBox: ThinkPad X13 AMD Gen1, status `failed`. Check it is alive before use. |

## Small boards and network gear

| Host | Purpose | Notes |
|---|---|---|
| pica4 | Raspberry Pi 4 server with a camera and power monitoring (`rpi` profile). | NixOS. |
| picaz | Raspberry Pi with a camera and console (`rpi` profile). | NixOS. |
| pikvm | KVM-over-IP for the servers. | Ansible `homelab` group. |
| turris | Router (Turris Omnia, OpenWrt). Upgrade it last, after enabling Fritzbox Wi-Fi first (`ansible-stuff` runbook). | Ansible `openwrt_router`. |
| brkn-ap, wax610, wrt1900ac | Access points. | OpenWrt, Ansible `openwrt_ap`/`access_points`. Upgrade order: wrt1900ac, wax610, turris. |
| brkn-switch, brkn-wwan, fritzbox | Switch, mobile uplink and the ISP box. | Ansible `homelab`. |
| shelly-* | Shelly relays: lights, ventilation, power sockets, covers, appliances. | Ansible `shelly*` groups; surface in Home Assistant. |

Phones and tablets: `android.md`.
