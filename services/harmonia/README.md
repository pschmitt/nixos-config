# Retained CI cache

rofl-14 is the primary publication store; rofl-13 holds a replica of retained
main outputs. Both serve their local store through Harmonia. CI uploads complete
signed closures to the primary, then registers direct GC roots through
`nix-cache-retain publish`. Successful publication requires valid local closures
and valid signatures from Harmonia's HTTP endpoint.

Roots live under `/nix/var/nix/gcroots/nixos-config/<scope>/<target>/`.
Publication metadata lives under `/var/lib/nixos-config-cache/`. Main retains
one successful output set per target until replaced; older commit timestamps
cannot replace newer ones. PR/manual outputs expire three days after publication.
Temporary roots protect incoming outputs while verification runs. Failed
verification preserves the previous successful output set.

The root-owned `nix-cache-populate` service on rofl-14:

- Resolves and pins main once per pass, using its locked private input.
- Rotates through eight exported package/architecture, host and Android targets
  per pass, preserving its cursor across commits. Existing outputs are retained
  without rebuilding; missing outputs are built one at a time with two cores.
- Pauses missing builds/copies below 15 GiB available space on either node.
- Signs complete retained main closures with the primary’s runtime key, then
  replicates them directly to rofl-13 and creates roots there. The key remains
  on the cache host.
  PR outputs stay on the primary to bound replica storage.
- Imports a small canary closure through HTTP into an empty temporary store and
  verifies its contents and signatures. The temporary store is removed afterward.

The timer runs again 15–20 minutes after a pass finishes. A pass has a bounded
runtime and reports build, publication and replication failures; unsupported or
credential-dependent failures are not silently counted as coverage. Proprietary
sources still need to be supplied by the existing credentialed CI jobs. Store
and authenticated HTTP access continue to use the existing Nix/SOPS credentials;
no signing keys or credentials are added here.

Inspect progress with:

```console
systemctl status nix-cache-populate.service
journalctl -u nix-cache-populate.service
cat /var/lib/nixos-config-cache-populate/state.json
nix-cache-retain list
```

This provides eventual coverage and explicit retention, not unlimited history.
Low disk space or failed builds leave visible gaps to resolve; they do not evict
current main roots automatically. Increasing the retained target set can require
more storage. Both machines currently use their root filesystem for `/nix`.
