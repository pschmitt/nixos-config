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

  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";
    enableCompletion = false;
    envExtra = ''
      setopt NO_GLOBAL_RCS
      export LC_ALL="''${LC_ALL:-en_US.UTF-8}"
      unset VIMINIT
      if [[ -z "''${XDG_RUNTIME_DIR:-}" ]]
      then
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      fi
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
      if [[ -n "''${ZSH_EXECUTION_STRING:-}" && ! -o interactive && ! -o login && -z "''${ZHJ:-}" ]]
      then
        # Only ZHJ is exported; exporting NO_* would
        # leak into shells spawned from here (ssh -t host tmux, zhj tmux::attach).
        export ZHJ=1
        NO_COMPLETIONS=1 NO_PLUGINS=1
        source "$ZDOTDIR/.zshrc"
        zsh::source-local-plugins
        export ZHJ_MODE=eval
      fi
    '';
    initContent = lib.mkOrder 1400 ''
      if [[ -o interactive && -z "$NO_PLUGINS" ]]
      then
        zsh::load-local-plugins
      fi
    '';
  };
}
