{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./base.nix ];

  # NixOS sets ZDOTDIR system-wide (/etc/zshenv.local, profiles/base/dotfiles.nix),
  # so no ~/.zshenv is needed.
  home.file.".zshenv".enable = lib.mkForce false;

  # Migration (2026-11): yadm used to own ~/.config/zsh/.zsh{env,rc} and
  # .zprofile as relative symlinks to zshenv/zshrc/zprofile. Remove them
  # before Home Manager links its own, on hosts where the yadm pull that
  # deletes them has not run yet. Drop once every host has pulled yadm.
  home.activation.dropYadmZshStartupLinks = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    for name in zshenv zshrc zprofile
    do
      link=${lib.escapeShellArg config.programs.zsh.dotDir}/.$name
      if [[ -L "$link" && "$(readlink "$link")" == "$name" ]]
      then
        run rm -f "$link"
      fi
    done
  '';

  programs.zsh = {
    enable = true;
    # The startup files come from Nix; yadm still owns the local plugins,
    # functions, custom/ overlays, completions and p10k.zsh beside them.
    dotDir = "${config.xdg.configHome}/zsh";
    enableCompletion = false;
    profileExtra = ''
      [[ -r /etc/zsh/zprofile ]] && source /etc/zsh/zprofile 2>/dev/null
    '';
    envExtra = ''
      setopt NO_GLOBAL_RCS
      export LC_ALL="''${LC_ALL:-en_US.UTF-8}"
      unset VIMINIT
      if [[ -z "''${XDG_RUNTIME_DIR:-}" && "$OSTYPE" != *android* ]]
      then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      fi
      if [[ ! -e /etc/NIXOS && -r /etc/profile.d/nix.sh ]]
      then
        source /etc/profile.d/nix.sh &>/dev/null
      fi
      if [[ ! -e /etc/NIXOS ]]
      then
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
      fi
      for profile_script in \
        /etc/profile.d/apps-bin-path.sh \
        /etc/profile.d/flatpak.sh \
        /etc/profile.d/snapd.sh
      do
        [[ -r "$profile_script" ]] && source "$profile_script" 2>/dev/null
      done
      unset profile_script
      fpath=(
        "${pkgs.zsh}/share/zsh/${pkgs.zsh.version}/functions"
        "$ZDOTDIR/completions"
        $fpath
      )
      typeset -gA DOMAINS
      DOMAINS[main]="$DOMAIN"
      DOMAINS[netbird]="${config.domains.netbird}"
      DOMAINS[tailscale]="${config.domains.tailscale}"
      if [[ -z "''${NETWORK_LOCATION:-}" && -r "${config.xdg.cacheHome}/network-location.txt" ]]
      then
        NETWORK_LOCATION="$(<"${config.xdg.cacheHome}/network-location.txt")"
      fi
      export XDG_DATA_DIRS="$HOME/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
      [[ -d "${config.xdg.cacheHome}/zsh" ]] || mkdir -p -- "${config.xdg.cacheHome}/zsh"
      export ZSH_CACHE_DIR="${config.xdg.cacheHome}/zsh"
      if [[ -n "''${TERM_SSH_CLIENT:-}" ]] && infocmp "''${TERM_SSH_CLIENT}" &>/dev/null
      then
        export TERM="$TERM_SSH_CLIENT"
      fi
      if [[ "$OSTYPE" == *android* ]]
      then
        export TMPDIR="${config.xdg.cacheHome}/tmpdir"
        mkdir -p "$TMPDIR"
        export PREFIX="''${PREFIX:-/data/data/com.termux/files/usr}"
        export LD_PRELOAD="''${LD_PRELOAD:-''${PREFIX}/lib/libtermux-exec.so}"
        export BROWSER=termux-open
        [[ -d "''${PREFIX}/lib/go" ]] && export GOROOT="''${PREFIX}/lib/go"
      fi

      if [[ -n "''${ZSH_EXECUTION_STRING:-}" && ! -o interactive && ! -o login && -z "''${ZHJ:-}" ]]
      then
        # Only ZHJ is exported (like the yadm zhjrc); exporting NO_* would
        # leak into shells spawned from here (ssh -t host tmux, zhj tmux::attach).
        export ZHJ=1
        NO_COMPLETIONS=1 NO_PLUGINS=1
        source "$ZDOTDIR/.zshrc"
        zsh::source-local-plugins
        export ZHJ_MODE=eval
      fi
    '';
    initContent = lib.mkMerge [
      # OS and per-host overlays from yadm's custom/ dir. Overrides such as
      # custom/hosts/<host>/zprompt (host_color) must precede p10k.zsh.
      (lib.mkOrder 700 ''
        () {
          setopt localoptions nullglob extendedglob
          local custom_dir="${config.xdg.configHome}/zsh/custom"

          is_distrobox && multisrc "$custom_dir/os/distrobox"/*
          is_nixos || multisrc "$custom_dir/os/not-nixos"/*.zsh

          multisrc \
            "$custom_dir/os/$__OS_KIND"/*(-.) \
            "$custom_dir/hosts/$HOST"/*(-.)

          # Like the yadm dirs.zsh: a cd<name> alias for every named
          # directory, including the host overlays' `hash -d` entries.
          local name
          for name in ''${(k)nameddirs}
          do
            (( $+aliases[cd$name] )) || alias "cd$name=cd ''${(q)nameddirs[$name]}"
          done
        }
      '')
      (lib.mkOrder 1400 ''
        if [[ -o interactive && -z "$NO_PLUGINS" ]]
        then
          zsh::load-local-plugins
        fi
      '')
    ];
  };

}
