# pschmitt's nixos book of horrors

Description: tdb.

## Home Manager on `fnuc`

`fnuc` is a standalone Home Manager target for a headless Fedora host.

Apply it with:

```shell
NIX_CONFIG='experimental-features = nix-command flakes' \
nix run github:nix-community/home-manager -- switch --flake '.#fnuc'
```

To verify that the configuration evaluates:

```shell
nix --extra-experimental-features 'nix-command flakes' \
  eval '.#homeConfigurations.fnuc.activationPackage.drvPath'
```

## Nix-on-Droid on `zf10`

`zf10` is a minimal phone profile wired through `nixOnDroidConfigurations`. It
keeps Home Manager as the main layer and reuses the portable CLI/devel modules
instead of trying to mirror the full desktop stack from day one.

### First switch on the phone

1. Install Nix-on-Droid from F-Droid and let the bootstrap finish.
2. Activate the profile straight from GitHub:

```shell
nix-on-droid switch --flake 'github:pschmitt/nixos-config#zf10'
```

Because `default` points to the same config, this also works:

```shell
nix-on-droid switch --flake 'github:pschmitt/nixos-config'
```

### Working from a local checkout on Android

```shell
git clone https://github.com/pschmitt/nixos-config.git ~/devel/private/pschmitt/nixos-config.git
cd ~/devel/private/pschmitt/nixos-config.git
nix-on-droid switch --flake '.#zf10'
```

The Home Manager profile lives in
[./home-manager/nix-on-droid.nix](./home-manager/nix-on-droid.nix) and the
device entrypoint lives in
[./hosts/zf10/default.nix](./hosts/zf10/default.nix).

## Deploying a new host

The public checkout and private configuration repository are separate. Set
`PRIVATE_CONFIG_DIR` to the local `nixos-config-private` checkout when using
host-initialization, SOPS, or Tofu tooling.

Host-specific SOPS payloads (`hosts/*/*.sops.yaml`) and generated SSH host
data are stored in the private repository and consumed through the
`nixos-config-private` flake input; the public checkout intentionally contains
no host secret ciphertexts.

To create a new host:

1. Add it to [flake.nix](./flake.nix)
2. Create the config files:

```shell
PRIVATE_CONFIG_DIR=/path/to/nixos-config-private \
  ./scripts/init-host-config.sh "$NEW_HOST"
```

3. Update `tofu/dns-dynamic.tf` in the private configuration repository.

4. Add to `/srv/luks-ssh-unlock/docker-compose.yaml` (@fnuc)

5. Deploy:

```shell
PRIVATE_CONFIG_DIR=/path/to/nixos-config-private just tofu init
PRIVATE_CONFIG_DIR=/path/to/nixos-config-private \
  just tofu apply -target=module.nix-${NEW_HOST}
```

## Removing a host

1. Remove its config from:
- [flake.nix](./flake.nix)
- `tofu/dns-dynamic.tf` in the private configuration repository

2. Remove from `/srv/luks-ssh-unlock/docker-compose.yaml` (@fnuc)

3.
```shell
HOST_TO_REMOVE=xxx
rm -rf "./hosts/$HOST_TO_REMOVE" "/path/to/nixos-config-private/tofu/${HOST_TO_REMOVE}.tf"
PRIVATE_CONFIG_DIR=/path/to/nixos-config-private just sops-config-gen --github-username pschmitt --auto
```

## Updating custom packages

- Use `just nix-update --list` to see the available package attributes.
- Run `just nix-update --package <name>` to refresh a single package or omit
  the flag to sweep all custom packages. Add `--build` to verify builds or
  `--commit` to let `nix-update` create commits.
- Packages that need bespoke handling should define a `passthru.updateScript`
  alongside the derivation; the helper will use it automatically (disable with
  `--no-update-script`). Lingering skips live in `pkgs/nix-update.json`.
- The scheduled workflow in [`.github/workflows/nix-update.yaml`](.github/workflows/nix-update.yaml)
  runs daily and opens a pull request with automated updates when changes are
  detected.
