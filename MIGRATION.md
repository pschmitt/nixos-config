# OCI `oci-01` to NixOS migration

## Current state

- `oci-01` is an OCI `VM.Standard.A1.Flex` instance with 2 OCPUs and 12 GiB
  RAM in `eu-frankfurt-1`, availability domain 2.
- The current public address is ephemeral, not reserved. It is referenced by
  the Terraform-managed Cloudflare records in `tofu/dns-dynamic.tf`,
  `tofu/dns-brkn-lol.tf`, and `tofu/dns-email.tf`.
- OCI reverse DNS is attached to the current public address. Replacing the
  instance would normally allocate a different address and require a new OCI
  support request for the PTR record.
- The data disk is a separate 50 GiB OCI block volume, managed as
  `oci_core_volume.oci_01_data` in `tofu/data-volumes.tf`. It is attached
  paravirtualized and protected by `prevent_destroy` on both the volume and
  attachment.
- On Ubuntu the disk is `/dev/sdb1`, LUKS2, opened as `data`, and mounted as
  Btrfs at `/mnt/data`. The mount is managed by the custom
  `/usr/local/bin/luks-mount` and `/etc/luks-mount.yaml`, not by `fstab` or
  `crypttab`.
- Persistent application data is primarily under `/mnt/data/srv`. Stalwart,
  Roundcube, autodiscover, the static sites, and Healthchecks are now
  Nix-managed services. The final reverse-proxy cutover is implemented with
  `services.nginx`; the legacy Traefik Compose project is retained only until
  the controlled runtime cutover is verified.
- The repository now has an `oci-01` NixOS host configuration following the
  `oci-03` cloud-host pattern. Root is Disko-managed LUKS+Btrfs; the existing
  data disk is also Disko-declared with `destroy = false`, its stable OCI
  `/dev/disk/by-id` path, existing LUKS UUID, and raw Btrfs root mount.
- M/Monit is intentionally not part of `oci-01`; it remains an `oci-03`
  service only.
- The normal Ubuntu SSH host RSA and Ed25519 keypairs were imported into the
  new host's SOPS file, so the server's normal SSH identity remains stable.
  Separate generated initrd host keys are used for remote LUKS unlocking.
- The old Ubuntu unlock-manager service remains commented out in the `fnuc`
  compose configuration. The active NixOS unlocker is now the canonical
  `oci-01` service/container (`luks-ssh-unlock-oci-01`); its NixOS-specific
  material remains under `config/oci-01-nixos` so it cannot be confused with
  the old Ubuntu material under `config/oci-01`. The old container was removed
  only after the renamed container passed its remote health check.

## Backup status

### Restic / Autorestic

The Ubuntu cron job runs Autorestic daily at 06:00. Its `main` location backs
up:

- `/mnt/data/srv`
- `/etc`
- `/home/ubuntu`

It does not back up the complete root volume. In particular, `/var/lib/docker`,
`/root`, installed packages, and other root-filesystem state are not covered.

On 2026-08-08 a manual backup completed successfully:

- snapshot: `1fa296e6`
- processed: 80,255 files / 1.893 GiB
- added: 226 MiB
- retention result: 19 snapshots retained
- repository integrity check: passed with no errors

The Nix-managed Restic configuration now uses the existing Wasabi repository
and password from Ubuntu Autorestic, with the repository URL, OCI credentials,
and Healthchecks URL populated through the repository's standard Restic secret
helper. This avoids starting a separate backup repository during cutover.

The first Nix-managed backup was re-run on 2026-08-08 after transferring the
working Ubuntu Autorestic repository password into the OCI-01 SOPS secret. It
completed successfully, including the configured retention/prune step; the
Healthchecks callback also returned `OK`.

### OCI volume backups

The data volume previously had an OCI `gold` policy with daily, weekly,
monthly, and yearly schedules. The investigation found 25 backup records;
the OCI API did not expose a reliable free-tier marker for these records, so
the cleanup retained the four newest available data backups and terminated
the 21 older records.

The boot-volume backup `oci-01-root-before-nixos-2026-08-08` is available and
must be retained until the migration is stable:

`ocid1.bootvolumebackup.oc1.eu-frankfurt-1.abtheljrjs5nwoc6xbkhb5x6k4bxjndocrmhgctivyzny6ehk6rfpfvevgaa`

The old assignment was replaced with a ToFu-managed daily incremental policy
with three-day retention. Four data backups are currently `AVAILABLE`; the
older 21 records are `TERMINATED`. Together with the temporary root rollback
backup, this is currently five available OCI backups. The policy must remain
in place so scheduled data backups cannot grow beyond four while the root
rollback exists.

## Migration decision

The preferred path is an in-place NixOS installation on the existing OCI
instance:

1. Preserve the instance, VNIC, private address, public address, and PTR.
2. Create and verify a root-volume rollback backup. **Done:** the backup above
   is `AVAILABLE`.
3. Stop application services and perform a final Autorestic backup.
4. Install NixOS with `nixos-anywhere`/Disko, targeting the existing root and
   explicitly preserving the existing data disk.
5. Recreate the LUKS unlock and `/mnt/data` mount explicitly in NixOS.
6. Start the legacy Stalwart and Traefik Compose projects from `/srv`; the
   static sites and Healthchecks are now native Nix services.
7. Verify mail, HTTP, Docker/application state, backups, DNS, and monitoring.

The Nix Disko declaration identifies the data disk by its stable OCI SCSI
`/dev/disk/by-id` path, retains its existing LUKS UUID, and sets
`destroy = false`. It must not be changed to a destructive/reformatting
declaration.

Creating `oci-04` is a fallback, not the first choice. The existing data volume
is in availability domain 2, so a replacement instance must be placed there to
attach it directly. A new instance would also need a new public address unless
an already-reserved address is available, which would require a new reverse-DNS
request for the existing mail PTR. A temporary second A1 instance may also
exceed the tenancy's Always Free compute allocation.

## Traefik to native Nginx investigation

The active Traefik configuration was inspected on `oci-01` on 2026-08-08.
Archived files under `/srv/traefik/config/archive` are not loaded and are not
part of this migration. The active route set is:

| Route | Current backend | Native-Nginx migration notes |
| --- | --- | --- |
| `pschmitt.dev`, `p.schmi.tt`, `philipp.schmi.tt`, `github.pschmitt.dev`, `gh.pschmitt.dev`, `schmitt.co` | Nix Nginx static vhosts | Native Nginx owns the public TLS vhosts and ACME certificates. |
| `hc.brkn.lol`, `healthchecks.brkn.lol` | Nix Healthchecks via loopback | Native Nginx proxies directly to Healthchecks and preserves HTTPS forwarding headers. |
| `mail.brkn.lol`, `mail.pschmitt.dev` | Native Roundcube/PHP-FPM | Existing SQLite data is reused unchanged; Nginx serves the native Roundcube vhost. |
| `stalwart.brkn.lol`, `autoconfig.brkn.lol`, `autodiscover.brkn.lol`, `autoconfig.pschmitt.dev`, `autodiscover.pschmitt.dev` | Native Stalwart HTTP listener | Nginx proxies to `127.0.0.1:8080`; no Docker-network address is involved. |
| `autoconfig.schmitt.co`, `autodiscover.schmitt.co` | Native go-autoconfig | Nginx proxies to the native `127.0.0.1:8081` service. |
| Home Assistant aliases under `ber.schmi.tt`, `ovm5.de`, `brkn.lol`, and `dieppe.schmi.tt` | Native Nginx HTTPS proxy | Nginx uses the system resolver and reachable upstreams; the old Traefik active failover chain is not retained. |
| `grafana.ovm5.de`, `graphana.ovm5.de`, `graph.ovm5.de`, `gr.ovm5.de` | Native Nginx HTTPS proxy | Nginx preserves upstream TLS SNI and runtime DNS resolution. |
| `oci-yum.brkn.lol` | Native Nginx HTTPS proxy | Nginx disables upstream compression and applies the equivalent `sub_filter` rewrite. |
| Turris SSH on public 443 | Native Nginx `stream` | Nginx uses `ssl_preread` to send TLS to the internal HTTPS listener and non-TLS SSH to `127.0.0.1:22887`. |
| `traefik.brkn.lol` | Intentionally retired | The old dashboard route returns HTTP 410 after Traefik removal. |

The public DNS check showed that most of these names resolve to the OCI-01
address `130.61.215.245`, but `homeassistant.brkn.lol` and
`home-assistant.brkn.lol` resolve to `89.163.172.112`, while `turris.brkn.lol`
resolves to `84.173.60.212`. Those names must not be assumed to be served by
OCI-01 during a cutover.

The current host resolver uses Cloudflare DNS. The overlay names used by the
Home Assistant routes are instead available through the local NetBird resolver
(`127.0.0.20`) and Tailscale DNS (`100.100.100.100`). A future Nginx module
should set `services.nginx.resolver` accordingly and enable
`proxyResolveWhileRunning` for those dynamic upstreams.

The Nix implementation is in `hosts/oci-01/nginx-public.nix`. It keeps the
public HTTP redirect listener on port 80, terminates TLS on loopback port 8443,
and uses Nginx `stream`/`ssl_preread` on public port 443 so the existing Turris
SSH tunnel remains possible. The old Traefik `acme.json` and configuration are
kept on the data disk as a rollback copy until the route tests are complete.

## Terraform safety requirements

Before any replacement or termination operation, boot-volume retention is
explicit in `tofu/oci-01.tf`:

```hcl
preserve_boot_volume = true
```

The instance also has `prevent_destroy = true`. A targeted apply from
`rofl-10` set `preserve_boot_volume` in place (`0 destroyed`). The safety bits
are committed as `45df0577`.

The separately managed data volume must retain `prevent_destroy = true`. Do not
remove that protection during the migration. Terminating the instance should
detach the data volume, not delete it, but the cloud-side behavior must still
be checked after every operation.

Terraform/OpenTofu operations should run from `rofl-10`, using the repository's
`tofu/tofu.sh` wrapper. The local `nixos::tofu-from-rofl` helper cleans and
updates `/etc/nixos` on the remote host before running `nix develop --command
./tofu/tofu.sh`; it assumes the desired changes are available on the selected
branch. Targeted plans/applies are required so unrelated NixOS builds are not
started.

Now that `oci-01` is running NixOS, a normal committed NixOS configuration
change can be deployed directly by restarting its `nixos-upgrade.service`.
The `rofl-10` deployment path remains useful for remote builds, but is not
required for routine changes to this host.

## Cutover checklist

### Before cutover

- [x] Create a full OCI boot-volume backup and wait for `AVAILABLE`.
- [x] Record its OCID and verify the source boot volume and size.
- [x] Change the OCI data-volume backup policy to a bounded strategy.
- [x] Delete the 20 old data-volume backups and retain four newest data
      backups plus the root rollback snapshot.
- [x] Add `preserve_boot_volume = true` and apply it in place from `rofl-10`.
- [x] Add an `oci-01` NixOS host definition and an explicit, data-safe Disko
      layout.
- [x] Prepare the data-volume LUKS secret and mount configuration in NixOS.
- [x] Trigger and verify the final pre-migration Autorestic backup.

### During cutover

- [ ] Stop Docker and mail/application services.
- [ ] Ensure `/mnt/data` is cleanly unmounted or otherwise quiesced before any
      OCI volume backup.
- [ ] Reconfirm the target disk passed to Disko is the root disk only.
- [ ] Install NixOS in place and reboot.
- [ ] Confirm the data volume is attached, unlocked, mounted, and untouched.

### After cutover

- [x] Migrate the static sites from Caddy to Nix-managed Nginx, preserving the
      `schmitt.co` document root.
- [x] Migrate Healthchecks to the native Nix service, reusing its existing
      SQLite database/configuration and persistent image data.
- [x] Verify native Stalwart, Roundcube, and autodiscover units and their
      persistent SQLite stores.
- [ ] Verify the native Nginx public routes and remove the legacy Traefik
      container.
- [ ] Verify the public IP/PTR and all Cloudflare records.
- [x] Verify a Nix-managed Restic backup, retention/pruning, and its
      Healthchecks callback.
- [ ] Keep the boot-volume backup until the migration has been stable for an
      agreed period.
- [ ] Recheck OCI billing and Always Free resource tags.

## Diagnostic caveat

Autorestic's `check` command is not read-only. During investigation it
initialized the local backend and attempted to initialize the Scaleway backend
before failing. It did not modify the Wasabi repository or the OCI data disk.
Use the backend-specific `restic check` operation for future integrity checks.
