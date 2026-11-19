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
nix build '.#homeConfigurations.zf10.activationPackage' -o zf10-home
nix build '.#homeConfigurations.p11.activationPackage' -o p11-home

nix eval --impure --option restrict-eval true \
  --option allowed-uris 'github: gitlab: https: git+https:' -I . --json --expr '
  import ./profiles/specializations/termuxpp/tests.nix {
    inputs = (builtins.getFlake (toString ./.)).inputs;
  }'

nix develop --command nixfmt --check profiles/specializations/termuxpp/*.nix
nix develop --command statix check profiles/specializations/termuxpp
nix develop --command deadnix profiles/specializations/termuxpp
nix shell --inputs-from . 'nixpkgs#shellcheck' -c shellcheck modules/home-manager/termuxpp/scripts/*.sh
bash modules/home-manager/termuxpp/scripts/rworker-nix-test.sh
nix shell --inputs-from . 'nixpkgs#python3' -c bash modules/home-manager/termuxpp/scripts/test-check-runtime.sh
```

After building the generated Nixpkgs source, check both its legacy and flake
entry points on the worker. This forces evaluation of rsync, Neovim and the
transitive rsync dependency of `nixos-rebuild-ng`, including their patch paths:

```sh
nix build --impure --expr \
  '(builtins.getFlake (toString ./.)).homeConfigurations.zf10.config.home.file.".local/share/full-nix/nixpkgs".source' \
  -o full-nix-nixpkgs
nix eval --impure --json --file profiles/specializations/termuxpp/package-set-tests.nix \
  --apply "test: test { source = $(readlink -f full-nix-nixpkgs); }"
```

Standard flake builds use pure evaluation, so the editor module cannot scan the
build host's home for user plugins. The expression-based assertions above use
restricted evaluation for the same reason. Private runtime dotfiles must not
become build inputs.

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

### Disposable workers (opt-in per command)

`rworker-nix build`, `rworker-nix shell` and `rworker-nix develop` lease a worker
for that command and delete it afterwards, including command failure and ordinary
termination signals. They do not rewrite the normal machines file. A lost network
connection or an uncatchable kill can prevent cleanup; the worker TTL remains the
backstop, and `rworker-nix --down NAME` retries explicit cleanup.

Configure a trusted controller SSH alias privately in
`~/.config/rworker-nix/local.conf` (`controller=rworker-controller`), or pass it
in the environment. The managed `config` supplies defaults; `local.conf`
overrides them and is never sourced as shell code. For example:

```sh
RWORKER_NIX_CONTROLLER=rworker-controller rworker-nix --ttl 1h build '.#package'
RWORKER_NIX_CONTROLLER=rworker-controller rworker-nix shell nixpkgs#hello -c hello
```

The public key defaults to `~/.ssh/id_ed25519.pub`; override it with
`RWORKER_NIX_KEY`. The matching private key and pinned controller host key must
already be available. No cloud credentials are needed on the phone. The optional
Home Manager module exposes `fullNix.rworker` defaults; environment variables
supply private runtime values without putting them in the Nix store.

The phone-packaged controller client disables SSH multiplexing because Android's
translated app-private control-socket paths exceed Unix socket limits.

The command checks the worker's pinned host key and refuses an x86 worker unless
its image advertises `aarch64-linux` and enables the corresponding qemu binfmt
handler. Local compilation remains disabled. Nix evaluation still runs on the
phone; this helper offloads builds, not evaluation. To offload expensive profile
evaluations, sync the source and run Nix on a worker as described above.

### Targeted signal-stack compatibility

The guest wraps `eza`, `bat`, `fd`, `ripgrep`, `rbw` (including its agent),
`openstack-rs`, `vivid`, and `zoxide` with an interposer that increases alternate signal stacks to
128 KiB in every thread. Real-device probes found crashes in these packages
that disappear with enlarged stacks; this implicates the runtime's SIGSYS
translation, but is not a complete symbolic root-cause trace. In particular,
`rg` and `fd` version probes pass even when actual searches crash. For `eza`,
enlarging only the main thread is insufficient for threaded listings.
The shim retains at most one mapping per participating thread until process
exit. It is not a global preload and does not modify other package outputs or
the launcher. The agent is wrapped so `rbw` subprocesses retain the same stack
policy; this does not qualify real vault authentication or long-running agent
behavior. The source filename and derivation name retain their historical eza
names to avoid an unnecessary rebuild of the interposer.

The glibc `nixpp` executable reserves its own main-thread alternate signal stack
at startup: 128 KiB plus the kernel's minimum signal-frame requirement, rounded
to pages, with a lower guard page. The mapping remains allocated until exit.
This is embedded in the Rust binary, not a wrapper or inherited preload; the
Android/Bionic controller is unchanged. Production guest commands are currently
single-threaded. Any future guest worker threads need equivalent reservations.
On-device preparation succeeds with the existing enlarged-stack preload where
the unmodified binary crashes; final acceptance of the embedded reservation is
required separately. The launcher still does not enforce a global minimum.

`overlay.nix` centralizes these targeted variants and capability-free `iputils`. A generated Nixpkgs facade with an explicitly locked local input supplies
the pinned registry and
`<nixpkgs>`, so `nix shell nixpkgs#eza` and `nix-shell -p eza` select the same
Android-aware variant. Explicit upstream URLs or another registry bypass this
overlay and are not covered by the compatibility guarantee.

Run `python3 -I modules/home-manager/termuxpp/scripts/check-eza.py` inside the activated guest
for 60 real listings covering threads, long/icon/tree/Git output and symlinks.
It creates and removes its own fixture. Linux builds and profile assertions do
not replace this Android acceptance check. Keep future runtime-specific package
fixes here, separate from the native Android/Bionic package profiles.

## Runtime gate and generation management

`full-nix-check-runtime` checks shell startup, bare/configured Neovim, repeated
fixture-based eza listings, the local Nix registry, Unix sockets, tmux and an
already-built Go executable (`kubectl`). It also checks real `bat` plain,
numbered and highlighted rendering, nine `rg` cases including PCRE and no-match,
seven `fd` searches, isolated `rbw version` / `osc --version` startup,
`vivid` theme generation, `zoxide` database add/query, and recursive `rsync`
copies with content, mode, symlink and update verification. These
additional checks use generated fixtures and scratch HOME/XDG directories even
in active mode; they do not access a real vault or authenticate to a service.
It never compiles a probe on the phone.
Use `--thorough` for 60 eza listings, 20 consecutive bare Neovim starts and an
offline pinned Nixpkgs evaluation. Neovim uses LuaJIT built with JIT disabled:
Android guest executable-memory allocation made JIT-enabled startup intermittently
fail. The gate asserts the actual runtime's `jit.status()` is false, rather than
relying on a build flag. A test-only upstream patch waits for asynchronous
Tree-sitter work without changing production parsing or weakening its assertions.
The corrected unwrapped executable passed 100 consecutive starts on the second
phone; configured-editor and full-generation acceptance are separate checks.
Candidate mode uses a scratch home; active mode checks the real configuration.
Neither mode is a sandbox or proof that every installed package works.

The ordinary `homeConfigurations.zf10` and `homeConfigurations.p11` remain
available for the Home Manager layer. The [declarative guest system](system.md)
coordinates system and matching Home Manager generations through `nixpp`;
use that interface on migrated devices. For Home Manager-only environments,
the source-based interface remains:

```sh
home-manager switch --flake '.#zf10'
home-manager generations
full-nix-check-runtime --thorough
```

`max-jobs = 0` still prevents phone compilation, but `home-manager switch`
evaluates on the machine running it. For remote evaluation as well as building,
run the standard build on a worker, then fetch the result directly on the phone:

```sh
# Worker, after syncing the source and configuring private-input authentication:
nix build '.#homeConfigurations.zf10.activationPackage' -o zf10-home
readlink -f zf10-home

# Guest, using a privately configured SSH alias and pinned host key:
nix copy --from ssh://build-worker /nix/store/HASH-home-manager-generation
/nix/store/HASH-home-manager-generation/activate
home-manager generations
```

A signed binary cache is an alternative to direct SSH transfer. Do not route
large closures through the workstation. This is the same build/copy/activate
workflow used for prebuilt Home Manager configurations on ordinary Linux hosts.
The worker is disposable; its provisioning/authentication is separate from Home
Manager and must not be embedded in the public configuration.

For a new guest with no Nix package profile, initialize a standard modern profile
before the first activation:

```sh
nix profile add /nix/store/HASH-home-manager-generation/home-path
```

Otherwise Home Manager selects its legacy `nix-env` path, which needs to build a
profile environment and correctly fails with phone compilation disabled.

Activation hooks run the isolated candidate gate before Home Manager's
`writeBoundary`, then the real-home gate after linking files and installing packages. A preflight
failure prevents activation; a postcheck failure reports an unsuccessful
activation. Activation is **not atomic** and there is no automatic rollback.
Use `home-manager generations` and run a retained generation's `activate` script
for normal Home Manager recovery. Preserve native recovery independently.

## Android integration

`android-bridge ping|status|battery-status|toast` talks to a native broker through
`/tmp/android-bridge/bridge.sock`. Start it outside the Linux guest using the
runtime's `start-android-bridge.sh`; opt-in login startup uses `bridge.enabled`.
The guest cannot directly execute Android/Bionic helpers. The bridge accepts
only the four listed operations, validates requests and same-UID peers, bounds
helper execution/output, and uses a private directory/socket. It is not a
security boundary against other processes of the Android app UID. There is no
arbitrary command, clipboard, location, contact or credential interface.

Both test phones passed guest-to-native ping, filtered battery status and toast.
Those probes do not establish background-service lifetime or every companion's
compatibility. Native recovery and native SSH configuration remain independent.

### Shizuku shell

Run `rish` or `rish -c 'id -u'` from an interactive TermuxPP terminal. The
wrapper enters the native Android environment and extracts the matching
launcher and read-only DEX from the installed Shizuku APK. Start Shizuku
and grant TermuxPP access when prompted. A supervised TermuxPP terminal or
an SSH connection with a PTY can run an interactive Shizuku shell. Update
the Shizuku app through Android. The next `rish` invocation reads the new
APK and caches its matching assets automatically.

### Native shell and shared storage

From a fresh TermuxPP app terminal, run `nixpp enter --outer` for a native
shell, or `nixpp enter --outer -- /system/bin/id` for a single command.

SSH and tmux sessions use the native controller's same-UID socket at
`/run/nixpp-runtime/outer.sock`. Update both guest and native nixpp to use it.
Interactive commands get a native PTY. Commands without a PTY keep separate
stdin, stdout and stderr:

```sh
ssh -t phone 'nixpp enter --outer'
ssh -t phone 'rish'
ssh phone 'nixpp enter --outer -- /system/bin/id -u'
```

Run `termux-setup-storage` there to request Android storage access. After
granting access, run it again to create `~/storage/shared`, `~/storage/downloads`,
and the other media shortcuts inside the guest. The shortcuts also work from
SSH and tmux once Android grants access. Existing paths are preserved.

### Tasker execution

The TermuxPP Tasker plug-in remains a native Android entry point; selecting a
full-Nix login does not automatically move existing Tasker scripts into the
guest. Keep a native launcher in `~/.config/termuxpp/tasker/`, the plug-in's
allowlisted script directory, and explicitly enter the managed guest:

```sh
#!/system/bin/sh
exec /system/bin/sh "$HOME/.local/share/termuxpp-nix/login.sh" -lc \
  'exec "$HOME/.local/bin/my-job"'
```

Here the outer `HOME` is the native home; the quoted job uses the guest home.
Select the launcher's filename in the plug-in, run in background mode, enable
wait-for-result, and use an absolute native working directory. Check `%result`
for the command exit status; `%stdout` and `%stderr` carry its output. Keep the
arguments field in the plug-in bundle even when it is null. A guest job should
use `exec` or propagate failures explicitly rather than hide them behind a
successful final command.

Scratch Tasker jobs on both test phones successfully entered the managed guest,
ran local version/rendering probes, and returned stdout, stderr and deliberate
exit status 7. On the second phone the plug-in correctly rejected an executable
outside its allowlisted directory; using that directory passed without enabling
`allow-external-apps`. Existing saved tasks, schedules and native recovery were
not changed. This does not qualify unattended maintenance, vault authentication,
Android background lifetime or arbitrary native helpers inside the guest.

### Nightly maintenance

The managed profile installs a native Tasker launcher at
`~/.config/termuxpp/tasker/nightly-update.sh`. Configure the bundled TermuxPP
Tasker action to run it in the background and wait up to 3,600 seconds. The job
runs on Wi-Fi while the phone is charging, and needs 512 MiB of free space.

The job activates the signed cache pin with `nixpp upgrade --from-cache`,
runs `nixpp gc --keep-generations 3`, and fast-forwards yadm. The cache check
also recognises older generations that GC has pruned. It syncs Atuin when signed in,
then syncs and updates each
configured mani workspace. Git runs without prompting. The latest two runs
are logged under `~/.local/state/termuxpp-nightly/` in the guest. To check the
current cache and readiness without activating anything, run
`termuxpp-nightly-update --check`.

Use `nixpp gc --keep-generations 3 --dry-run` to preview cleanup. GC preserves
the active and rollback generations and any generation used by a running
session. It defers cleanup while activation is unfinished or a session is
still running with a launcher that predates generation leases.
When a generation is pruned, GC also drops its unused Home Manager profile
links so they release the old closure.

Run `nixpp diff` to compare the previous generation with the active one.
To compare two retained generations, get their numbers with
`nixpp list-generations` and pass them in order, for example `nixpp diff 12 14`.
Use `nixpp --json diff` to include the generation paths with the diff output.

### Functional audit qualification

The overlay now wraps `vivid` and `zoxide` with the targeted signal-stack shim.
The `rsync` patch uses search-only ancestor descriptors while retaining symlink
and ownership checks. The runtime gate covers these previously failing operations.
On the test phone, the thorough active gate and a separate 90-probe offline
fixture audit passed after migration to the declarative guest system plus HM.
Both profiles have now activated the final declarative system plus matching HM
and passed the thorough runtime gate, including configured Neovim, `vivid`,
`zoxide` and `rsync`. The separate 90-probe audit above was on the test phone,
not a repeated 90-probe result for both final generations.
The audit used disposable HOME/XDG directories, no real vault or remote cloud
operations, and no compilation on the phones.

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

Both configurations have been built through the standard flake outputs and
activated in their Linux guests. Candidate and active gates passed on both test
phones, including configured Neovim and 60 eza listings per gate. The primary
phone uses the full-Nix login; the second phone retains its native default shell.
These checks do not establish long-running/background reliability. Do not switch
the native nixpp profile or run these activation scripts in the native Android home.

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
current launcher accepts only AArch64/4096-byte-page devices. Both test phones
passed the basic runtime and Unix-socket probes; this alone does not qualify a
Home Manager generation or prove a completed default-shell migration.

## Secrets (sops-nix)

`sops.nix` reuses the pinned upstream Home Manager sops-nix module for options,
assertions, manifest generation and the installer, but replaces its activation:
upstream restarts a systemd user unit, which does not exist here. Upstream's
installer script instead runs from `home.activation.sops-nix` (after
`linkGeneration`, before `androidAcceptance`), so a failed decryption fails the
activation. The upstream unit files are disabled. Like upstream, nothing is added
without secrets, so existing generations and guests are unaffected.

```nix
sops = {
  defaultSopsFile = ./secrets.yaml;       # in the store; contains only ciphertext
  age.keyFile = "/home/pschmitt/.config/sops/age/keys.txt";  # outside the store
  secrets.example = { };
};
```

Home Manager generations live in `$XDG_RUNTIME_DIR/secrets.d`. The launcher
sets `XDG_RUNTIME_DIR` to `/run/user/<uid>`. Override the fallback for an unset
variable with `fullNix.sops.runtimeDir`. Cleanup is upstream's and nothing more: a secret that is
dropped from a still-configured set disappears with the pruned generation, but a
custom `path` symlink of it dangles, and removing every secret runs nothing, so the
previously installed data stays until removed by hand. The declarative system layer
has its own `sops.*` and activation executable, run by the controller before this
one; see [system configuration](system.md) for the contract and the limits (same Android UID,
persistent `/run`, rollback to generations without the hook). Test with
`sops-tests.nix`.

## Deliberately not migrated

This is the declarative shell/package baseline, not complete feature parity:

- Native SSH host identities/daemon ports and read-only cache credentials remain
  owned by native recovery. No credentials are copied into the guest or Nix store.
- Beyond the four allowlisted bridge operations, Android API/Tasker helpers and
  shared storage bindings need separate runtime integration; Linux binaries are
  not substitutes for the Bionic helpers.
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
