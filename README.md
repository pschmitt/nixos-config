# pschmitt's nixos book of horrors

Description: tdb.


## Deploying a new host

To create a new host:

1. Add it to [flake.nix](./flake.nix)
2. Create the config files:

```shell
./init-host-config.sh $NEW_HOST
```

3. Update [./tofu/dns-dynamic.tf](./tofu/dns-dynamic.tf)

4. Add to `/srv/luks-ssh-unlock/docker-compose.yaml` (@fnuc)

5. Deploy:

```shell
./tofu/tofu.sh init
./tofu/tofu.sh apply -target=module.nix-${NEW_HOST}
```

## Removing a host

1. Remove its config from:
- [flake.nix](./flake.nix)
- [./tofu/dns-dynamic.tf](./tofu/dns-dynamic.tf)

2. Remove from `/srv/luks-ssh-unlock/docker-compose.yaml` (@fnuc)

3.
```shell
HOST_TO_REMOVE=xxx
rm -rf "./host/$HOST_TO_REMOVE" "./tofu/${HOST_TO_REMOVE}.tf"
./secrets/sops-config-gen.sh --github-username pschmitt --auto
```

## Updating custom packages

- Use `just nix-update --list` to see the available package attributes.
- Run `just nix-update --package <name>` to refresh a single package or omit
  the flag to sweep all custom packages. Add `--build` to verify builds or
  `--commit` to let `nix-update` create commits.
- Packages skipped by nix-update are listed in `pkgs/nix-update.json`.
- The scheduled workflow in [`.github/workflows/nix-update.yaml`](.github/workflows/nix-update.yaml)
  runs daily and opens a pull request with automated updates when changes are
  detected.
