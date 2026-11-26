# Moving dotfiles from yadm to Home Manager

The user's dotfiles still partly live in yadm (`~/.local/share/yadm/repo.git`,
work tree `$HOME`; run `yadm ls-files` from `~`, it lists paths relative to
the current directory). Moving one tool's config to Home Manager:

1. **Inventory.** `cd ~ && yadm ls-files .config/<tool>`. Check that the tool
   is still installed on the hosts that use it (fnuc is headless; check GUI
   tools on a laptop) and whether a Home Manager module already covers part of
   it (`rg` the repo for the tool's name, `programs.<tool>`, `xdg.configFile`).
   Dead configs are deleted from yadm, not ported.
2. **Split public/private.** Scan for credentials by key name only
   (`secret-hygiene`), and for private identifiers: work hosts and emails,
   self-hosted endpoints, network or device names. Those go to
   `nixos-config-private/hm/` (imported by its `homeManagerModules.default`),
   the rest to `nixos-config/home-manager/`. Credentials go to SOPS.
3. **Port.** Keep files as files: `xdg.configFile."<tool>" = { source = ./dir;
   recursive = true; }` links file by file, so untracked runtime files in the
   same directory survive; scripts keep their executable bit. Use a native
   `programs.<tool>` module where it exists (git, direnv), with the same
   settings. Symlinks yadm tracked become
   `config.lib.file.mkOutOfStoreSymlink`; `##distro.nixos` alternates become
   the NixOS variant with store paths (`lib.getExe pkg`) instead of
   `/etc/profiles/...`. TermuxPP imports a hand-picked module list
   (`profiles/specializations/termuxpp/home.nix`) and its tests assert parts
   of it.
4. **Verify on a worker.** Build the host's
   `home-manager.users.<user>.home-files`, check every migrated path is there
   (and executable where needed), and smoke-test the tool against the built
   files with `HOME`/`XDG_CONFIG_HOME` pointing into a temp dir. For Zsh
   autoloaded functions, also test a fresh noninteractive shell: Home Manager
   installs individual symlinks, so a Zsh glob that selects regular files must
   follow symlinks (for example `*(N-.)`, not `*(N.)`). A link-existence check
   alone does not show whether the autoloader discovers the functions.
5. **Order of the rollout.** Commit and push nixos-config-private, `bump my
   privates`, commit and push nixos-config. Then untrack in yadm with
   `yadm rm -r --cached <paths>` (files stay on this host until the switch)
   and push; a removed submodule also needs its `.gitmodules` section
   (`git config -f ~/.gitmodules --remove-section ...`, yadm's `config` has
   no `-f`). On other hosts run `yadm pull` **before** they switch: a host
   that switches first has the tracked files replaced by links, and the
   `yadm-pull` timer (`--autostash`) then leaves a stash conflict behind.
   **Exception: files the deploy itself needs** (ssh `ProxyCommand` or
   `Match exec` helpers, anything an upgrade or `rworker` connection runs):
   pulling their removal before the host switched breaks the upgrade
   (2026-11-20: TermuxPP `nixpp upgrade --rworker` failed on missing
   `~/.config/ssh/bin/*`). Leave them in yadm until every host switched, or
   restore them untracked (`yadm show REV:path > path`) before the upgrade;
   nixpp's `--backup` then moves them to `*.nixpp.bak`, which can be deleted
   when identical.
6. **First switch.** Home Manager backs up differing files as `*.hm-backup`,
   but stops on a yadm alternate symlink ("would be clobbered") and skips
   identical copies without linking them. Fix as in the `deploy` skill's
   traps: `cmp` each skipped file with the new `home-manager-files`, delete
   the identical ones, move alternates aside, restart
   `home-manager-<user>.service`, then check the paths are links into
   `home-manager-files`.
