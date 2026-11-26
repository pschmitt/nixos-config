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
    BROWSER =
      if (config.programs.ssh-client-browser.enable or false) then
        lib.getExe config.programs.ssh-client-browser.package
      else
        "firefox";
    EDITOR = "nvim";
    VISUAL = "nvim";
    SYSTEMD_EDITOR = "nvim";
    PAGER = "less";
    MANPAGER = "less";
    DOMAIN = config.domains.main;
    # Plugins use this at load time (aliases).
    EMAIL = config.mainUser.email.personal or null;
    REPORTTIME = 10;
    KEYTIMEOUT = 1;
    CARGO_HOME = "${config.xdg.dataHome}/cargo";
    GOPATH = "${config.xdg.dataHome}/go";
    RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
    XDG_BIN_HOME = "${config.home.homeDirectory}/.local/bin";
    ANSIBLE_HOME = "${config.xdg.cacheHome}/ansible";
    ANSIBLE_GALAXY_CACHE_DIR = "${config.xdg.cacheHome}/ansible/galaxy";
    ASSH_CONFIG = "${config.xdg.configHome}/assh/assh.yml";
    DOCKER_CONFIG = "${config.xdg.configHome}/docker";
    GNUPGHOME = "${config.xdg.configHome}/gnupg";
    KREW_ROOT = "${config.xdg.dataHome}/krew";
    HTTPIE_CONFIG_DIR = "${config.xdg.configHome}/httpie";
    IPYTHONDIR = "${config.xdg.configHome}/ipython";
    JUPYTER_CONFIG_DIR = "${config.xdg.configHome}/jupyter";
    KUBECACHEDIR = "${config.xdg.cacheHome}/kubectl";
    LESSHISTFILE = "${config.xdg.cacheHome}/less-history";
    NPM_CONFIG_PREFIX = "${config.xdg.dataHome}/npm";
    NPM_CONFIG_CACHE = "${config.xdg.cacheHome}/npm";
    NPM_CONFIG_INIT_MODULE = "${config.xdg.configHome}/npm/config/npm-init.js";
    PASSWORD_STORE_DIR = "${config.xdg.dataHome}/pass";
    PARALLEL_HOME = "${config.xdg.configHome}/parallel";
    PYLINTRC = "${config.xdg.configHome}/pylint/pylintrc";
    PYLINTHOME = "${config.xdg.cacheHome}/pylint";
    TASKRC = "${config.xdg.configHome}/taskwarrior/taskrc";
    TASKDATA = "${config.xdg.dataHome}/taskwarrior";
    TIMEWARRIORDB = "${config.xdg.configHome}/timewarrior";
    TMUX_PLUGIN_MANAGER_PATH = "${config.xdg.dataHome}/tpm";
    TMUX_CONFIG_HOME = "${config.xdg.configHome}/tmux";
    RANCHER_CONFIG_DIR = "${config.xdg.configHome}/rancher";
    LUAROCKS_CONFIG = "${config.xdg.configHome}/luarocks/config.lua";
    WORKON_HOME = "${config.xdg.dataHome}/virtualenvs";
    VIMDOTDIR = "${config.xdg.configHome}/nvim";
    ZSH_COMPDUMP = "${config.xdg.cacheHome}/zsh/zcompdump-${hostname}-${pkgs.zsh.version}";
    GTK2_RC_FILES = "${config.home.homeDirectory}/.gtkrc-2.0";
  }
  // luarocksConfig;
  sessionVariableInit = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: ''
      zsh::xdg-export ${lib.escapeShellArg name} ${lib.escapeShellArg (toString value)}
    '') (lib.filterAttrs (_: value: value != null) shellSessionVariables)
  );
in
{
  imports = [ ../../../../modules/home-manager/ssh-client-browser.nix ];

  programs.zsh = {
    shellAliases = {
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

  home.sessionPath = [
    "${config.home.homeDirectory}/bin"
    "${config.home.homeDirectory}/.nix-profile/bin"
    "${config.home.homeDirectory}/Applications"
    "${config.xdg.dataHome}/cargo/bin"
    "${config.xdg.dataHome}/go/bin"
    "${config.xdg.dataHome}/luarocks/bin"
    "${config.home.homeDirectory}/.local/bin"
    "${config.xdg.dataHome}/krew/bin"
    "${config.xdg.dataHome}/npm/bin"
  ];
}
