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

