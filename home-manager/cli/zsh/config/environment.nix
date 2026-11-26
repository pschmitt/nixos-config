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
  # Every program's environment: login shells (hm-session-vars.sh), the
  # systemd user manager and what it starts (environment.d), and zsh (below).
  sessionVariables = {
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
    RUSTUP_HOME = "${config.xdg.dataHome}/rustup";
    XDG_BIN_HOME = "${config.home.homeDirectory}/.local/bin";
    ANSIBLE_HOME = "${config.xdg.cacheHome}/ansible";
    ANSIBLE_GALAXY_CACHE_DIR = "${config.xdg.cacheHome}/ansible/galaxy";
    ASSH_CONFIG = "${config.xdg.configHome}/assh/assh.yml";
    DOCKER_CONFIG = "${config.xdg.configHome}/docker";
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
  }
  // luarocksConfig;

  # Only for zsh and what it starts
  zshSessionVariables = {
    DOMAIN = config.domains.main;
    # Plugins use this at load time (aliases).
    EMAIL = config.mainUser.email.personal or null;
    REPORTTIME = 10;
    KEYTIMEOUT = 1;
    ZSH_COMPDUMP = "${config.xdg.cacheHome}/zsh/zcompdump-${hostname}-${pkgs.zsh.version}";
  };
in
{
  imports = [ ../../../../modules/home-manager/ssh-client-browser.nix ];

  home.sessionVariables = sessionVariables;
  systemd.user.sessionVariables = sessionVariables;

  programs.zsh = {
    sessionVariables = lib.filterAttrs (_: value: value != null) zshSessionVariables;
    # hm-session-vars.sh only runs once per session (__HM_SESS_VARS_SOURCED is
    # inherited): fill in what is missing, e.g. in a tmux server started before
    # a variable was added, without overriding inherited values.
    envExtra = lib.mkBefore (
      lib.concatStrings (
        lib.mapAttrsToList (name: value: ''
          [[ -n "''${${name}-}" ]] || export ${name}=${lib.escapeShellArg (toString value)}
        '') sessionVariables
      )
    );
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
