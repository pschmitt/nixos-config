# Packages

Custom packages live in [`pkgs`](../pkgs) and are exported through the
`packages` and `overlays` flake outputs.

## Update packages

```sh
just nix-update --list           # list the package attributes
just nix-update PACKAGE          # update one package
just nix-update                  # update all packages
just nix-update --build PACKAGE  # also build it
just nix-update --commit         # create one commit per update
```

Other flags are in `just nix-update --help`.

A package that needs special handling defines `passthru.updateScript` next to
its derivation. The helper uses it unless you pass `--no-update-script`. Packages
to skip are listed in [`pkgs/nix-update.json`](../pkgs/nix-update.json).

## Automated updates

[`nix-update.yaml`](../.github/workflows/nix-update.yaml) runs daily and opens a
pull request when a package changes. See [CI](ci.md) for how these get merged.

## Build a package

```sh
just build-pkg PACKAGE [HOST]
```
