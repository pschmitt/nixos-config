# Hosts

Host tooling needs the private checkout. Set `PRIVATE_CONFIG_DIR` to its path:

```sh
export PRIVATE_CONFIG_DIR=/path/to/nixos-config-private
```

The OpenTofu and SOPS recipes live in the private `justfile`. Run them from the
private checkout.

## Add a host

1. Add the host to `hostConfigs` in [`flake.nix`](../flake.nix).
2. Create its configuration. The flag selects a template from
   [`templates/nix`](../templates/nix) (`--openstack` is the default,
   `--openstack-legacy`, `--oci` and `--laptop` are the others):

   ```sh
   just init-host --laptop NEW_HOST
   ```

   This creates `hosts/NEW_HOST`, its SOPS file and known hosts data in the
   private checkout and, for cloud templates, `tofu/NEW_HOST.tf`.
3. Stage the new files with `git add -N hosts/NEW_HOST`. Flake evaluation does
   not see untracked files.
4. Add its DNS entry to `tofu/dns-dynamic.tf` in the private checkout.
5. If other hosts should unlock its LUKS root over SSH, add it to `targets` in
   [`services/luks-ssh-unlock/fleet.nix`](../services/luks-ssh-unlock/fleet.nix).
6. Commit and push the private checkout, then update the `nixos-config-private`
   input of this flake.

## Install a host

Cloud hosts install through OpenTofu, from the private checkout:

```sh
just tofu init
just tofu apply -target=module.nix-NEW_HOST
```

`just tofu-remote BUILD_HOST ...` does the same with the evaluation on a build
host.

Other machines install from this checkout, with `-k` for a dry run:

```sh
just nixos-remote NEW_HOST                 # over SSH, with nixos-anywhere
just nixos-anywhere NEW_HOST /dev/nvme0n1  # to a local disk, with disko-install
```

Install media:

```sh
just iso  # installer ISO
just rpi  # Raspberry Pi SD image
```

## Remove a host

1. Remove the host from `hostConfigs` in [`flake.nix`](../flake.nix), and from
   `targets` in
   [`services/luks-ssh-unlock/fleet.nix`](../services/luks-ssh-unlock/fleet.nix)
   if it is listed there.
2. Delete its directory: `rm -rf hosts/OLD_HOST`.
3. From the private checkout, remove its OpenTofu configuration and regenerate
   the SOPS configuration:

   ```sh
   just host-delete OLD_HOST
   just sops-config-gen --auto
   ```

   `host-delete` edits the configuration and prints a plan. It never applies.
   Review the plan, then run the apply command it prints.

Do not run `tofu destroy -target` for a host that is still in the configuration.
It can remove the DNS records of every host. See `tofu/AGENTS.md` in the private
checkout.
