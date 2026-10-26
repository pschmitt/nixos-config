# CI cache delivery

nixbot builds x86_64 outputs and uploads their closures to niks3. GitHub's
native ARM runners build aarch64 outputs and upload with short-lived OIDC
tokens. Default-branch outputs are pinned; PR outputs remain unpinned and
expire according to the cache server's GC policy.

nixbot's post-build pin step is required: an upload or pin failure fails the
attribute. A pin protects its closure, and replacing it releases the previous
closure for eventual collection. Pin names distinguish nixbot outputs
(`nixbot-*`) from GitHub ARM outputs (`gh-main-*`). Server credentials and
retention settings live in the private configuration repository.

Harmonia continues to serve each host's local store as an additional
substituter. The former `nix-cache-populate`, `nix-cache-retain` and S3 mirror
services are retired; CI no longer publishes over SSH to the cache hosts.

## LAN mirror

`services/harmonia-lan-mirror.nix` reads selected default-branch outputs from
nixbot's `/nix-outputs` endpoint, fetches their closures using the configured
substituters and creates local GC roots. LAN clients can then substitute from
that host's Harmonia. A failed fetch preserves the previous root. The mirror
also reserves free space before fetching and releases roots of removed targets.

```console
systemctl status nix-cache-lan-mirror.timer
journalctl -u nix-cache-lan-mirror.service
```

## Verification

Before retiring a cache path, compare its replacement pin with nixbot's
published output, download a small pinned closure from S3 into an empty store,
and verify its signatures and contents. Check that the LAN mirror fetched and
rooted its configured outputs. A rejected pin request must fail the required
post-build step while preserving the previous pin.

Legacy `main-*` pins and `/nix/var/nix/gcroots/nixos-config` roots can be
removed after every retained target has a replacement. Keep Harmonia and its
signing keys while hosts still use it as a substituter.
