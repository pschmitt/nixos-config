# Whole host closures on a large worker

Build `nixosConfigurations.<host>.config.system.build.toplevel`
on a `--profile large-builder` worker (32 vCPU / 62 GiB / 500 GiB), not the
default one: uncached heavy derivations (llvm, kernels, browsers) can take
hours. Give it `--ttl 8h` or more (`extend` later; max 24 h) and run
`nix build` on the worker itself (`rworker start "$w" -- 'cd repo &&
NIX_USER_CONF_FILES=... nix build --accept-flake-config --max-jobs 4
--cores 0 -L -o ~/<host>-system .#nixosConfigurations.<host>.config.system.build.toplevel'`).
Several hosts can build on one worker: shared derivations are built once.
Afterwards push the closure to the S3 cache from the worker and let the
targets substitute (or `nix copy` between datacenter hosts); do not pull it
home.

**Keep big closures off the home link.** The user's home connection is DSL
and slow: copying a large result back to the agent's host wastes their
bandwidth and time. Fetch only small artifacts home. For a closure that
other hosts will deploy, have it go from the worker to the S3 cache and let
the targets substitute, or build on the target itself.


## Uploading a closure from the worker to the S3 cache

The S3 bucket is managed by the niks3 server (`https://niks3.<main domain>`,
on the host that runs `services.niks3`, currently rofl-10), which signs and
pins what it receives. Push **through niks3**, not with `nix copy --to s3://`:
the `niks3` AWS profile that `nix-cache` copies to a worker is read-only, so a
raw `nix copy` fails with HTTP 403 `AccessDenied`, and it would bypass signing
and the server's garbage-collection bookkeeping.

1. Read the server's API token on its host (`sudo -n cat
   /run/secrets/niks3/api-token`) and pipe it over SSH into the *same*
   `rworker ssh` session that consumes it (the worker may delete `/dev/shm`
   files when the last login ends). Never print it or put it in arguments.
2. Run the client from nixpkgs with `--auth-token-path` (`--auth-token` takes
   the token itself and is deprecated):

```bash
ssh <niks3-host> 'sudo -n cat /run/secrets/niks3/api-token' \
  | rworker ssh "$w" 'umask 077; d=$(mktemp -d /dev/shm/rworker-secret.XXXXXXXX); trap "rm -rf $d" EXIT; cat > $d/token; nix shell nixpkgs#niks3 -c niks3 push --server-url https://niks3.<main domain> --auth-token-path $d/token ~/<host>-system; echo PUSH_RC=$?'
```

   `All N paths already cached` means there is nothing to do: targets can
   substitute the closure. After a successful push the targets fetch it from
   S3 (`nixos-upgrade` or `just deploy`), so nothing travels over the home
   link. The token is the server's admin token: it is fine on the private,
   temporary worker, but `down` the worker afterwards.
