# Full-Nix Android host profiles

Experimental Linux/glibc Home Manager configurations for `zf10` and `p11`, for
the isolated TermuxPP full-Nix runtime. These are **not** native nixpp bundles,
NixOS systems, or nix-on-droid configurations. Both use `aarch64-linux` packages
and the runtime's persistent `/home/pschmitt`.

The existing `hosts/*/default.nix`, native bundle outputs, SSH daemons and recovery
shells are unchanged. Only the host-owned prompt settings are imported from those
hosts: their native cache/SSH modules target a different activation mechanism.

## Build and check

Run on a disposable build worker, from this repository root with its pinned
private input available. Do not evaluate/build these on the workstation.

```sh
nix build --impure --option restrict-eval true \
  --option allowed-uris 'github: gitlab: https: git+https:' -I . --expr '
  let f = builtins.getFlake (toString ./.);
      homes = import ./android/full-nix { inputs = f.inputs; };
  in homes.zf10.activationPackage' -o zf10-home

nix build --impure --option restrict-eval true \
  --option allowed-uris 'github: gitlab: https: git+https:' -I . --expr '
  let f = builtins.getFlake (toString ./.);
      homes = import ./android/full-nix { inputs = f.inputs; };
  in homes.p11.activationPackage' -o p11-home

nix eval --impure --option restrict-eval true \
  --option allowed-uris 'github: gitlab: https: git+https:' -I . --json --expr '
  import ./android/full-nix/tests.nix {
    inputs = (builtins.getFlake (toString ./.)).inputs;
  }'

nix develop --command nixfmt --check android/full-nix/*.nix
nix develop --command statix check android/full-nix
nix develop --command deadnix android/full-nix
```

Restricted evaluation keeps the upstream editor module from scanning the build
host's real home for user plugins. Only repository inputs should affect the build;
private runtime dotfiles must not become evaluation inputs.

The invariants check guest identity/home, host-specific colors, Linux package
architecture, an empty native APT dependency list and no systemd service startup.

## Interactive Nix and remote builds

The guest pins both `<nixpkgs>` and the `nixpkgs` flake registry to this
configuration's input. Use `nix-shell -p iputils` or
`nix shell nixpkgs#iputils` for `ping`; the package is named `iputils`, not `ping`.
The installed `iputils` disables Linux capability setup to avoid the `prctl:
Operation not permitted` failure observed in SSH-launched sessions. Stock
`iputils` also works in the user's interactive app session; the failure is
context-dependent, not a universal Android limitation. Android still controls
ICMP permissions, so verify actual probes in the intended execution context.
`NIX_CONF_DIR` points to the guest's user configuration directory to avoid the
runtime's `/etc` mapping during flake-registry lookup.

`max-jobs = 0` disables local builds. Cached outputs can be downloaded; uncached
derivations require a reachable remote builder and fail rather than compiling on
the phone when none is available. Runtime builder entries belong in
`~/.config/nix/machines` (standard Nix machines-file format). Provision that file
and the corresponding SSH configuration, authorized identity and trusted host
keys privately before activating this profile. Do not embed worker addresses or
host keys in the public configuration. An ephemeral worker entry must be replaced
or removed when that worker expires. The builder must support `aarch64-linux`,
natively or through configured emulation.

## Included

- Shared portable Zsh settings and plugins, Atuin, direnv/nix-direnv, zoxide,
  vivid, bat, eza, fd and ripgrep.
- Host identity and prompt color. A usable fallback prompt works without an
  existing yadm checkout or `p10k.zsh`.
- The shared Linux Zsh core, including local yadm plugin/function loading and
  `zhj`. Generated startup files live in `~/.config/zsh-nix`, separate from the
  writable yadm configuration in `~/.config/zsh`. A managed root `.zshenv` also
  selects this configuration in nested shells and tmux.
- The shared Linux Neovim/LazyVim configuration, its Nix-managed plugins,
  Tree-sitter parsers, language servers and formatter dependencies.
- Nix-managed tmux, Git, Python, rbw, SOPS, GnuPG, OpenSSH and standard shell
  tools. tmux optionally sources `~/.config/tmux/user.conf` after managed defaults.
- Operations tools: OpenStack clients, kubectl, kubecolor, Helm, Kustomize,
  k9s, kubeconform, kubectl-neat, OIDC login, stern, OpenTofu, Ansible,
  GitHub/GitLab clients, DNS/network tools, age and yq.
- Home Manager generations, with no attempt to launch systemd user services.
- Lightweight fzf integration rather than the desktop image/video preview
  closure. This is an intentional mobile-specific composition choice.
- Stable configured Neovim without the optional second `nvim-nightly` executable.
  Terminal clipboard copies use OSC 52; pastes use the editor's current register
  rather than querying the Android clipboard. The guest selects `nixd` instead of
  `nil` (which crashed during on-device language-server startup), and includes
  `statix` for the shared Nix formatting configuration.
- A short writable `/tmp/run` runtime directory: Android's translated app-private
  paths can otherwise exceed Unix-domain socket limits.

## Activation boundary

The two generations have been built on a worker. Building them is not proof of
activation or Android acceptance. Do not switch the phone's native nixpp profile
or run these activation scripts in the native Android home.

Once the closure is available in the guest's virtual store, run its `activate`
script **inside** `session.sh --`, with guest `HOME=/home/pschmitt`. Preserve the
previous Home Manager generation and any conflicting guest files first. Then
start `session.sh -- zsh -l` to test the managed shell before changing runtime
startup. The generic runtime defaults to Bash; its optional `login.sh` selects
Home Manager's Zsh. Prepare a new runtime with `TERMUXPP_NIX_USER=pschmitt` so its
identity and home match these profiles.

For an existing `nix` guest, back up runtime launchers, user records and yadm
configuration before moving its home. Update `SESSION_USER`/`SESSION_HOME`,
`/etc/passwd`, `/etc/group` and the yadm worktree together, then activate the
matching generation. Keep `/home/nix` as a compatibility symlink for historical
generations and existing sessions. Do not change the Android app UID or native
recovery identity. Validate a fresh login with `id -un`, `$HOME`, nested Zsh,
yadm and the actual editor before considering the migration complete.

Large closures must be imported directly on the device from a signed cache or
built remotely; do not shuttle them through the workstation. The runtime must
already be qualified for the device's ABI and page size. In particular, the
current launcher accepts only AArch64/4096-byte-page devices; the tablet has not
been qualified by this configuration change.

## Deliberately not migrated

This is the declarative shell/package baseline, not complete feature parity:

- Native SSH host identities/daemon ports and read-only cache credentials remain
  owned by native recovery. No credentials are copied into the guest or Nix store.
- Android API/Tasker helpers, shared storage bindings and native command bridges
  need separate runtime integration; Linux binaries are not substitutes for the
  Bionic helpers.
- Existing dotfiles must be migrated device-locally; they are not build inputs.
  Back up the guest home, copy tracked files from the native worktree without
  overwriting Home Manager links, and clone the yadm repository with independent
  objects and index. Set its worktree to `/home/pschmitt`, initialize its index with
  `git read-tree HEAD`, and preserve its upstream remote. Do not run the native
  bootstrap, activate Android-specific alternatives, or enable automatic
  alternative relinking over Nix-owned files.
- Copy the actual prompt and private shell additions only inside app-private
  storage. Reuse existing device credentials through runtime paths, never through
  Nix sources or the store. Native recovery files remain untouched.
- Put the original tmux configuration at `~/.config/tmux/user.conf`, retaining
  sibling keybinding/helper files. The desktop Linux Neovim module supplies the
  editor configuration; do not activate the native Android editor alternative.
- Android integrations, runtime authentication, desktop-only commands in local
  helpers, and full host acceptance need separate verification. Keep the native
  shell usable throughout.
