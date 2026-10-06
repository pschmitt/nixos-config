{
  config,
  hostname,
  lib,
  pkgs,
  ...
}:
let
  luarocksConfig = builtins.listToAttrs (
    map
      (version: {
        name = "LUAROCKS_CONFIG_${lib.replaceStrings [ "." ] [ "_" ] version}";
        value = "${config.xdg.configHome}/luarocks/config-${version}.lua";
      })
      [
        "5.1"
        "5.2"
        "5.3"
        "5.4"
      ]
  );
  shellSessionVariables = {
    BROWSER = if (config.termux.enable or false) then "termux-open" else "firefox";
    EDITOR = "nvim";
    VISUAL = "nvim";
    SYSTEMD_EDITOR = "nvim";
    PAGER = "less";
    MANPAGER = "less";
    DOMAIN = config.domains.main;
    REPORTTIME = 10;
    KEYTIMEOUT = 1;
    CARGO_HOME = "${config.xdg.dataHome}/cargo";
    GOPATH = "${config.xdg.dataHome}/go";
    RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
    XDG_BIN_HOME = "${config.home.homeDirectory}/.local/bin";
    ANSIBLE_HOME = "${config.xdg.cacheHome}/ansible";
    ANSIBLE_GALAXY_CACHE_DIR = "${config.xdg.cacheHome}/ansible/galaxy";
    ASDF_CONFIG_FILE = "${config.xdg.configHome}/asdf/asdfrc";
    ASDF_DATA_DIR = "${config.xdg.dataHome}/asdf";
    ASDF_DEFAULT_TOOL_VERSIONS_FILENAME = "${config.xdg.configHome}/asdf/tool-versions";
    ASSH_CONFIG = "${config.xdg.configHome}/assh/assh.yml";
    DOCKER_CONFIG = "${config.xdg.configHome}/docker";
    MACHINE_STORAGE_PATH = "${config.xdg.dataHome}/docker-machine";
    GNUPGHOME = "${config.xdg.configHome}/gnupg";
    KREW_ROOT = "${config.xdg.dataHome}/krew";
    HTTPIE_CONFIG_DIR = "${config.xdg.configHome}/httpie";
    IPYTHONDIR = "${config.xdg.configHome}/ipython";
    JUPYTER_CONFIG_DIR = "${config.xdg.configHome}/jupyter";
    KUBECACHEDIR = "${config.xdg.cacheHome}/kubectl";
    LPASS_HOME = "${config.xdg.configHome}/lpass";
    LESSHISTFILE = "${config.xdg.cacheHome}/less-history";
    MPLAYER_HOME = "${config.xdg.configHome}/mplayer";
    NPM_CONFIG_PREFIX = "${config.xdg.dataHome}/npm";
    NPM_CONFIG_CACHE = "${config.xdg.cacheHome}/npm";
    NPM_CONFIG_INIT_MODULE = "${config.xdg.configHome}/npm/config/npm-init.js";
    PASSWORD_STORE_DIR = "${config.xdg.dataHome}/pass";
    PARALLEL_HOME = "${config.xdg.configHome}/parallel";
    PENTADACTYL_RUNTIME = "${config.xdg.configHome}/pentadactyl";
    PENTADACTYL_INIT = ":source ${config.xdg.configHome}/pentadactyl/pentadactylrc";
    PYLINTRC = "${config.xdg.configHome}/pylint/pylintrc";
    PYLINTHOME = "${config.xdg.cacheHome}/pylint";
    SCREENRC = "${config.xdg.configHome}/screen/screenrc";
    TASKRC = "${config.xdg.configHome}/taskwarrior/taskrc";
    TASKDATA = "${config.xdg.dataHome}/taskwarrior";
    TIMEWARRIORDB = "${config.xdg.configHome}/timewarrior";
    TMUX_PLUGIN_MANAGER_PATH = "${config.xdg.dataHome}/tpm";
    TMUX_CONFIG_HOME = "${config.xdg.configHome}/tmux";
    RANCHER_CONFIG_DIR = "${config.xdg.configHome}/rancher";
    UNISON = "${config.xdg.dataHome}/unison";
    VIMPAGER_RC = "${config.xdg.configHome}/vimpagerrc";
    VIMPERATOR_RUNTIME = "${config.xdg.configHome}/vimperator";
    VIMPERATOR_INIT = ":source ${config.xdg.configHome}/vimperator/vimperatorrc";
    LUAROCKS_CONFIG = "${config.xdg.configHome}/luarocks/config.lua";
    WORKON_HOME = "${config.xdg.dataHome}/virtualenvs";
    VIMDOTDIR = "${config.xdg.configHome}/nvim";
    ZSH_COMPDUMP = "${config.xdg.cacheHome}/zsh/zcompdump-${hostname}-${pkgs.zsh.version}";
    RXVT_SOCKET = "${config.xdg.dataHome}/urxvt/urxvt-${hostname}";
    GTK2_RC_FILES = "${config.home.homeDirectory}/.gtkrc-2.0";
    _Z_DATA = "${config.xdg.dataHome}/zsh/z";
    ZSHZ_DATA = "${config.xdg.dataHome}/zsh/z";
  }
  // luarocksConfig;
  sessionVariableInit = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: ''
      zsh::xdg-export ${lib.escapeShellArg name} ${lib.escapeShellArg (toString value)}
    '') shellSessionVariables
  );
in
{
  programs.zsh = {
    shellAliases = {
      irssi = "irssi --config=$XDG_CONFIG_HOME/irssi/config --home=$XDG_DATA_HOME/irssi";
      mc = "mc --config-dir $XDG_CONFIG_HOME/mc";
      tmux = "tmux -f $XDG_CONFIG_HOME/tmux/tmux.conf";
    };

    envExtra = lib.mkBefore ''
      zsh::xdg-export() {
        local name="$1" value="$2"
        if [[ -n "''${NO_XDG_ENV_OVERRIDE:-}" && -n "''${(P)name}" ]]
        then
          return 0
        fi
        export "$name=$value"
      }
      ${sessionVariableInit}
      unfunction zsh::xdg-export
    '';
  };

  programs.zsh.initContent = ''
    (( $+commands[synergys] )) && alias synergys="synergys -c $XDG_CONFIG_HOME/synergy/synergy.conf"
    (( $+commands[gcalcli] )) && alias gcalcli="gcalcli --config-folder $XDG_DATA_HOME/gcalcli"
  '';

  home.sessionPath = [
    "${config.home.homeDirectory}/bin"
    "${config.home.homeDirectory}/.nix-profile/bin"
    "${config.home.homeDirectory}/Applications"
    "${config.xdg.dataHome}/cargo/bin"
    "${config.xdg.dataHome}/go/bin"
    "${config.xdg.dataHome}/luarocks/bin"
    "${config.home.homeDirectory}/.local/bin"
    "${config.xdg.dataHome}/krew/bin"
    "${config.xdg.dataHome}/asdf/shims"
    "${config.xdg.dataHome}/npm/bin"
  ];
}
