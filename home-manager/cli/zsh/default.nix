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
      if [[ -f "$HOME/.local/state/nix/profiles/home-manager/home-path/etc/profile.d/hm-session-vars.sh" ]]
      then
        source "$HOME/.local/state/nix/profiles/home-manager/home-path/etc/profile.d/hm-session-vars.sh"
      fi

      # On non-NixOS hosts, prefer the system locale data.
      if [[ -f /usr/lib/locale/locale-archive ]]
      then
        export LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
        export NIX_LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
        unset LOCPATH
      elif [[ -d /usr/lib/locale ]]
      then
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

      if [[ -f "$HOME/.local/state/nix/profiles/home-manager/home-path/etc/profile.d/hm-session-vars.sh" ]]
      then
        source "$HOME/.local/state/nix/profiles/home-manager/home-path/etc/profile.d/hm-session-vars.sh"
      fi

      if [[ -f /usr/lib/locale/locale-archive ]]
      then
        export LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
        export NIX_LOCALE_ARCHIVE=/usr/lib/locale/locale-archive
        unset LOCPATH
      elif [[ -d /usr/lib/locale ]]
      then
        export LOCPATH=/usr/lib/locale
        unset LOCALE_ARCHIVE LOCALE_ARCHIVE_2_27 NIX_LOCALE_ARCHIVE
      fi

      hm::profile-link() {
        local profile="$HOME/.local/state/nix/profiles/home-manager"

        if [[ ! -e "$profile" ]]
        then
          return 1
        fi

        ${pkgs.coreutils}/bin/readlink "$profile"
      }

      hm::profile-target() {
        local profile="$HOME/.local/state/nix/profiles/home-manager"

        if [[ ! -e "$profile" ]]
        then
          return 1
        fi

        ${pkgs.coreutils}/bin/readlink -f "$profile"
      }

      hm::show-generation-diff() {
        local current_link="$1"
        local current_target="$2"
        local new_link="$3"
        local new_target="$4"

        if [[ -z "$current_target" || -z "$new_target" ]]
        then
          echo_error "Unable to determine Home Manager generations for diff"
          return 1
        fi

        if [[ "$current_link" == "$new_link" && "$current_target" == "$new_target" ]]
        then
          echo_info "Home Manager profile unchanged:"
          echo "  link: $new_link"
          echo "  target: $new_target"
          return 0
        fi

        if [[ "$current_target" == "$new_target" ]]
        then
          echo_info "Home Manager generation advanced, but the built result is unchanged:"
          echo "  old link: $current_link"
          echo "  new link: $new_link"
          echo "  target: $new_target"
          return 0
        fi

        echo_info "Home Manager generation changed:"
        echo "  old link: $current_link"
        echo "  new link: $new_link"
        echo "  old target: $current_target"
        echo "  new target: $new_target"

        ${pkgs.nvd}/bin/nvd diff --color=auto "$current_target" "$new_target"
      }

      hm::rebuild() {
        local repo="$HOME/devel/private/pschmitt/nixos-config.git"
        local target_host
        local current_link current_gen new_link new_gen

        zparseopts -D -E -K -- \
          {-host,-target,-target-host}:=target_host

        target_host="''${target_host[2]}"

        if [[ -z "$target_host" ]]
        then
          if [[ $# -gt 0 && "$1" != -* ]]
          then
            target_host="$1"
            shift
          else
            target_host="''${HOSTNAME:-$(hostname)}"
          fi
        fi

        current_link=$(hm::profile-link) || current_link=""
        current_gen=$(hm::profile-target) || current_gen=""

        local build_parent_dir="/nix/tmp/hm-builds"
        local build_group
        build_group=$(${pkgs.coreutils}/bin/id -gn)

        if [[ ! -d "$build_parent_dir" ]]
        then
          if ! ${pkgs.coreutils}/bin/mkdir -p "$build_parent_dir" 2>/dev/null
          then
            sudo ${pkgs.coreutils}/bin/install -d -m 0775 -o "$USER" -g "$build_group" "$build_parent_dir"
          fi
        fi

        if [[ ! -w "$build_parent_dir" ]]
        then
          sudo ${pkgs.coreutils}/bin/chown "$USER:$build_group" "$build_parent_dir"
          sudo ${pkgs.coreutils}/bin/chmod 0775 "$build_parent_dir"
        fi

        local build_dir
        if ! build_dir=$(${pkgs.coreutils}/bin/mktemp -d -p "$build_parent_dir" "hm-build-XXXXX")
        then
          echo_error "Failed to create temporary build directory in $build_parent_dir"
          return 1
        fi

        trap "${pkgs.coreutils}/bin/rm -rf '$build_dir'" EXIT

        # Use rsync to copy the repo, excluding .git and other build artifacts,
        # similar to nixos::clone-config.
        ${pkgs.rsync}/bin/rsync -az \
          --delete --delete-excluded \
          --exclude '.git*' \
          --exclude 'build/' \
          --exclude 'result' \
          "$repo/" "$build_dir/"
        local rsync_rc=$?
        if [[ "$rsync_rc" -ne 0 ]]
        then
          return "$rsync_rc"
        fi

        NIX_CONFIG='experimental-features = nix-command flakes' \
          ${pkgs.nix}/bin/nix run github:nix-community/home-manager -- \
            -b hm-backup \
            switch \
            --flake "''${build_dir}#''${target_host}" \
            "$@"

        local rc=$?
        if [[ "$rc" -ne 0 ]]
        then
          return "$rc"
        fi

        new_link=$(hm::profile-link) || new_link=""
        new_gen=$(hm::profile-target) || new_gen=""

        if [[ -n "$current_gen" && -n "$new_gen" ]]
        then
          hm::show-generation-diff "$current_link" "$current_gen" "$new_link" "$new_gen"
        elif [[ -n "$new_gen" ]]
        then
          echo_info "Activated Home Manager generation: $new_gen"
        fi

        return "$rc"
      }
      alias nrb="hm::rebuild"
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
