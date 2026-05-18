{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./atuin.nix
    ./direnv.nix
    ./fzf.nix
    ./vivid.nix
    ./zoxide.nix
  ];

  programs.zsh = {
    enable = false;
    dotDir = "${config.xdg.configHome}/zsh/hm";
  };

  home = {
    shell.enableZshIntegration = true;

    activation.clearZshCompDump = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run rm -f ${config.xdg.cacheHome}/zcompdump
    '';

    packages = with pkgs; [
      gitstatus # used by p10k
      nix-your-shell
    ];
  };

  xdg.configFile = {
    "zsh/custom/os/nixos/system.zsh".text = ''
      if [[ -f "$HOME/.local/state/nix/profiles/home-manager/home-path/etc/profile.d/hm-session-vars.sh" ]]; then
        source "$HOME/.local/state/nix/profiles/home-manager/home-path/etc/profile.d/hm-session-vars.sh"
      fi

      # On non-NixOS hosts, prefer the system locale data.
      if [[ -f /usr/lib/locale/locale-archive ]]; then
        export LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
        export NIX_LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
        unset LOCPATH
      elif [[ -d /usr/lib/locale ]]; then
        export LOCPATH=/usr/lib/locale
        unset LOCALE_ARCHIVE LOCALE_ARCHIVE_2_27 NIX_LOCALE_ARCHIVE
      fi

      [[ -o interactive ]] || return

      # DEPRECATED: Use wezterm.sh instead
      # source ${pkgs.vte}/etc/profile.d/vte.sh

      # FIXME the osc7 shell func produces output which p10k complains about
      # on startup (hence the WEZTERM_SHELL_SKIP_CWD)
      # WEZTERM_SHELL_SKIP_CWD=1 source ${pkgs.wezterm}/etc/profile.d/wezterm.sh
    '';

    "zsh/custom/os/not-nixos/nix.zsh".text = lib.mkAfter ''
      [[ -r /etc/profile.d/nix.sh ]] || return
      source /etc/profile.d/nix.sh &>/dev/null
      (( $+commands[nix] )) || return

      if [[ -f "$HOME/.local/state/nix/profiles/home-manager/home-path/etc/profile.d/hm-session-vars.sh" ]]; then
        source "$HOME/.local/state/nix/profiles/home-manager/home-path/etc/profile.d/hm-session-vars.sh"
      fi

      if [[ -f /usr/lib/locale/locale-archive ]]; then
        export LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
        export NIX_LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
        unset LOCPATH
      elif [[ -d /usr/lib/locale ]]; then
        export LOCPATH=/usr/lib/locale
        unset LOCALE_ARCHIVE LOCALE_ARCHIVE_2_27 NIX_LOCALE_ARCHIVE
      fi

      nrb() {
        local repo="$HOME/devel/private/pschmitt/nixos-config.git"
        if [[ ! -d "$repo" ]]
        then
          echo "nixos-config repo not found at $repo" >&2
          return 1
        fi

        local current_gen
        current_gen=$(readlink -f "$HOME/.local/state/nix/profiles/home-manager")

        local nix_tmpdir="/nix/tmp"
        local build_parent_dir="$nix_tmpdir/build"
        if [[ ! -d "$build_parent_dir" ]]
        then
          if [[ -w "$nix_tmpdir" ]]
          then
            mkdir -p "$build_parent_dir"
          else
            build_parent_dir="''${TMPDIR:-/tmp}/hm-builds"
            mkdir -p "$build_parent_dir"
          fi
        fi

        local build_dir
        if ! build_dir=$(mktemp -d -p "$build_parent_dir" "hm-build-XXXXX")
        then
          echo "Failed to create temporary build directory in $build_parent_dir" >&2
          return 1
        fi
        trap "rm -rf '$build_dir'" EXIT

        # Use rsync to copy the repo, excluding .git and other build artifacts
        # similar to nixos::clone-config
        rsync -az \
          --delete --delete-excluded \
          --exclude '.git*' \
          --exclude 'build/' \
          --exclude 'result' \
          "$repo/" "$build_dir/"

        (
          cd "$build_dir"
          just hm "$@"
        )
        local rc=$?

        if [[ "$rc" -ne 0 ]]
        then
          return "$rc"
        fi

        local new_gen
        new_gen=$(readlink -f "$HOME/.local/state/nix/profiles/home-manager")

        if [[ "$current_gen" != "$new_gen" ]]
        then
          if (( $+commands[nvd] ))
          then
            nvd diff "$current_gen" "$new_gen"
          else
            nix store diff-closures "$current_gen" "$new_gen"
          fi
        fi

        return "$rc"
      }
    '';

    # completions
    "zsh/completions/source-me.zsh".text = ''
      # bashcompinit is not needed here since we already do this in zinit
      # autoload -U +X bashcompinit && bashcompinit
      # FIXME openbao is broken as of 2026-01-09
      # https://github.com/NixOS/nixpkgs/pull/478004
      # complete -C "${pkgs.openbao}/bin/bao" bao
      complete -C "${pkgs.vault}/bin/vault" vault
    '';
  };
}
