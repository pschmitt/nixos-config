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

      hm_profile_link() {
        local profile="$HOME/.local/state/nix/profiles/home-manager"

        if [[ ! -e "$profile" ]]
        then
          return 1
        fi

        readlink "$profile"
      }

      hm_profile_target() {
        local profile="$HOME/.local/state/nix/profiles/home-manager"

        if [[ ! -e "$profile" ]]
        then
          return 1
        fi

        readlink -f "$profile"
      }

      hm_show_generation_diff() {
        local current_link="$1"
        local current_target="$2"
        local new_link="$3"
        local new_target="$4"
        local diff_log

        if [[ -z "$current_target" || -z "$new_target" ]]
        then
          echo "Unable to determine Home Manager generations for diff" >&2
          return 1
        fi

        if [[ "$current_link" == "$new_link" && "$current_target" == "$new_target" ]]
        then
          echo "Home Manager profile unchanged:"
          echo "  link: $new_link"
          echo "  target: $new_target"
          return 0
        fi

        if [[ "$current_target" == "$new_target" ]]
        then
          echo "Home Manager generation advanced, but the built result is unchanged:"
          echo "  old link: $current_link"
          echo "  new link: $new_link"
          echo "  target: $new_target"
          return 0
        fi

        echo "Home Manager generation changed:"
        echo "  old link: $current_link"
        echo "  new link: $new_link"
        echo "  old target: $current_target"
        echo "  new target: $new_target"

        if (( $+commands[nvd] ))
        then
          if ! diff_log=$(mktemp)
          then
            echo "Failed to create temporary file for nvd output" >&2
            return 1
          fi

          if nvd diff "$current_target" "$new_target" >"$diff_log" 2>&1
          then
            if [[ -s "$diff_log" ]]
            then
              cat "$diff_log"
              rm -f "$diff_log"
              return 0
            fi

            echo "nvd produced no diff output; falling back to nix store diff-closures" >&2
          else
            cat "$diff_log" >&2
            echo "nvd diff failed; falling back to nix store diff-closures" >&2
          fi

          rm -f "$diff_log"
        fi

        nix store diff-closures "$current_target" "$new_target"
      }

      nrb() {
        local repo="$HOME/devel/private/pschmitt/nixos-config.git"
        local target_host
        local current_link=""
        local current_gen=""
        local new_link=""
        local new_gen=""

        if [[ ! -d "$repo" ]]
        then
          echo "nixos-config repo not found at $repo" >&2
          return 1
        fi

        if [[ $# -gt 0 && "$1" != -* ]]
        then
          target_host="$1"
          shift
        else
          target_host="''${HOSTNAME:-$(hostname)}"
        fi

        if current_link=$(hm_profile_link)
        then
          :
        else
          current_link=""
        fi

        if current_gen=$(hm_profile_target)
        then
          :
        else
          current_gen=""
        fi

        local build_parent_dir="/nix/tmp/hm-builds"
        local build_group
        build_group=$(id -gn)

        if [[ ! -d "$build_parent_dir" ]]
        then
          if ! mkdir -p "$build_parent_dir" 2>/dev/null
          then
            if (( ! $+commands[sudo] ))
            then
              echo "Failed to create $build_parent_dir and sudo is unavailable" >&2
              return 1
            fi

            sudo install -d -m 0775 -o "$USER" -g "$build_group" "$build_parent_dir"
          fi
        fi

        if [[ ! -w "$build_parent_dir" ]]
        then
          if (( ! $+commands[sudo] ))
          then
            echo "$build_parent_dir is not writable and sudo is unavailable" >&2
            return 1
          fi

          sudo chown "$USER:$build_group" "$build_parent_dir"
          sudo chmod 0775 "$build_parent_dir"
        fi

        local build_dir
        if ! build_dir=$(mktemp -d -p "$build_parent_dir" "hm-build-XXXXX")
        then
          echo "Failed to create temporary build directory in $build_parent_dir" >&2
          return 1
        fi

        # Use rsync to copy the repo, excluding .git and other build artifacts,
        # similar to nixos::clone-config.
        rsync -az \
          --delete --delete-excluded \
          --exclude '.git*' \
          --exclude 'build/' \
          --exclude 'result' \
          "$repo/" "$build_dir/"
        local rsync_rc=$?
        if [[ "$rsync_rc" -ne 0 ]]
        then
          rm -rf "$build_dir"
          return "$rsync_rc"
        fi

        (
          cd "$build_dir"
          NIX_CONFIG='experimental-features = nix-command flakes' \
            nix run github:nix-community/home-manager -- \
              -b hm-backup \
              switch \
              --flake ".#''${target_host}" \
              "$@"
        )
        local rc=$?
        rm -rf "$build_dir"

        if [[ "$rc" -ne 0 ]]
        then
          return "$rc"
        fi

        if new_link=$(hm_profile_link)
        then
          :
        else
          new_link=""
        fi

        if new_gen=$(hm_profile_target)
        then
          :
        else
          new_gen=""
        fi

        if [[ -n "$current_gen" && -n "$new_gen" ]]
        then
          hm_show_generation_diff "$current_link" "$current_gen" "$new_link" "$new_gen"
        elif [[ -n "$new_gen" ]]
        then
          echo "Activated Home Manager generation: $new_gen"
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
