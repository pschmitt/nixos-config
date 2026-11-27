# Build the x86_64 prerequisites

Use the exact **nixos-config** commit that pins the TermuxPP change. Its
locked inputs select the same TermuxPP source and Nixpkgs as the phone build.
The NDK builds more than the runtime: build and push the runtime, the
bootstrap seed, `rbw-termux` and every host's `system.nativeLauncher` (it
depends on the host's `system.launcherStub`). Run this on the x86_64 worker,
in a checkout of that commit (or `--sync` the local tree, `.git` removed):

```bash
set -o pipefail
b() { nix build --accept-flake-config --no-link --print-out-paths --impure \
  --expr "let f = builtins.getFlake (toString ./.); in $1"; }
A='(f.inputs.termuxpp.lib.nixpp.packagesFor f.inputs.nixpkgs.legacyPackages.x86_64-linux)'
for a in nixpp-runtime-termux nixpp-runtime-termux-seed rbw-termux; do
  out=$(b "$A.$a") && nix path-info -r "$out" | niks3 push --stdin
done
for h in p11 zf10; do
  out=$(b "f.termuxppConfigurations.$h.config.system.nativeLauncher") &&
    nix path-info -r "$out" | niks3 push --stdin
done
```

Do the termuxpp bump in the same worker job: `nix flake update termuxpp`
there, build and push the above, `jq '.nodes.termuxpp' flake.lock` into the
fetched results, then merge only that node locally (step 2 above) and push.
The nightly then finds everything cached; pushing the bump first makes the
nightly's ARM build fail on the missing x86_64 parts.
