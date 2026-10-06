{
  config,
  lib,
  pkgs,
  ...
}:
let
  nixDotDir = "${config.xdg.configHome}/zsh-nix";
  nixDotDirTarget = lib.removePrefix "${config.home.homeDirectory}/" nixDotDir;
  completionLinks = lib.concatMapStringsSep "\n" (name: ''
    ln -s ${lib.escapeShellArg (toString config.xdg.configFile.${name}.source)} \
      "$out/completions/${lib.removePrefix "zsh/completions/" name}"
  '') (builtins.filter (lib.hasPrefix "zsh/completions/") (builtins.attrNames config.xdg.configFile));
  previewFiles = {
    zshenv = config.home.file."${nixDotDirTarget}/.zshenv".source;
    zprofile = config.home.file."${nixDotDirTarget}/.zprofile".source;
    zshrc = config.home.file."${nixDotDirTarget}/.zshrc".source;
  };
  previewConfig = pkgs.runCommand "zsh-nix-dotdir" { } ''
    mkdir -p "$out/plugins" "$out/completions"
    substitute ${previewFiles.zshenv} "$out/.zshenv" \
      --replace-fail ${lib.escapeShellArg nixDotDir} "$out"
    ln -s ${previewFiles.zprofile} "$out/.zprofile"
    ln -s ${previewFiles.zshrc} "$out/.zshrc"
    ln -s ${config.xdg.configHome}/zsh/plugins/local "$out/plugins/local"
    ln -s ${config.xdg.configHome}/zsh/custom "$out/custom"
    ${completionLinks}

  '';
  zshNix = pkgs.writeShellApplication {
    name = "zsh-nix";
    runtimeInputs = [ pkgs.zsh ];
    text = ''
      unset ZHJ __HM_SESS_VARS_SOURCED __HM_ZSH_SESS_VARS_SOURCED
      unset ZINIT_HOME
      export ZDOTDIR=${lib.escapeShellArg (toString previewConfig)}
      exec ${pkgs.zsh}/bin/zsh "$@"
    '';
  };
  # Escape hatch back to the yadm/zinit shell when the Nix config is the
  # default ZDOTDIR (dotfiles.zsh.nixShell.default).
  zshYadm = pkgs.writeShellApplication {
    name = "zsh-yadm";
    runtimeInputs = [ pkgs.zsh ];
    text = ''
      unset ZHJ __HM_SESS_VARS_SOURCED __HM_ZSH_SESS_VARS_SOURCED
      export ZDOTDIR="$HOME/.config/zsh"
      exec ${pkgs.zsh}/bin/zsh "$@"
    '';
  };
in
{
  imports = [ ./base.nix ];

  home.packages = [
    zshNix
    zshYadm
  ];

  # Let $ZDOTDIR/completions resolve when ~/.config/zsh-nix is used directly
  # as ZDOTDIR (the launcher links these into its store copy instead).
  xdg.configFile."zsh-nix/completions".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/zsh/completions";

  # The regular yadm-managed shell owns ~/.zshenv. Keep its dotDir separate
  # while the launcher uses a store-backed copy for pre-activation testing.
  home.file.".zshenv".enable = lib.mkForce false;

  programs.zsh = {
    enable = true;
    dotDir = nixDotDir;
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
      # Mirror the yadm custom.zsh loader: OS and per-host overrides such as
      # custom/hosts/<host>/zprompt (host_color) must precede p10k.zsh.
      (lib.mkOrder 700 ''
        () {
          setopt localoptions nullglob extendedglob
          local custom_dir="${config.xdg.configHome}/zsh/custom"

          is_distrobox && multisrc "$custom_dir/os/distrobox"/*
          source "$custom_dir/hostname" 2>/dev/null
          is_nixos || multisrc "$custom_dir/os/not-nixos"/*.zsh

          multisrc \
            "$custom_dir/os/$__OS_KIND"/^zboot.zsh \
            "$custom_dir/hosts/$HOST"/^zboot.zsh
        }
      '')
      (lib.mkOrder 1400 ''
        if [[ -o interactive && -z "$NO_PLUGINS" ]]
        then
          zsh::source-local-plugins
          __init_custom_completions
        fi
      '')
    ];
  };

}
