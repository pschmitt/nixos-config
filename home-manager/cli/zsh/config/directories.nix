{
  config,
  lib,
  ...
}:
let
  home = config.home.homeDirectory;
  privateDevel = "${home}/devel/private/pschmitt";
  directories = {
    c = config.xdg.configHome;
    xdgc = config.xdg.configHome;
    l = config.xdg.dataHome;
    xdgl = config.xdg.dataHome;
    docs = config.xdg.userDirs.documents;
    notes = "${config.xdg.userDirs.documents}/notes";
    pics = config.xdg.userDirs.pictures;
    hypr = "${config.xdg.configHome}/hypr";
    nix = "${privateDevel}/nixos-config.git";
    nixp = "${privateDevel}/nixos-config-private.git";
    nvim = "${config.xdg.configHome}/nvim";
    vim = "${config.xdg.configHome}/nvim";
    obs = "${home}/.var/app/com.obsproject.Studio/config/obs-studio";
    prv = "${home}/devel/private";
    p = "${home}/devel/private";
    ssh = "${config.xdg.configHome}/ssh";
    sway = "${config.xdg.configHome}/sway";
    tmx = "${config.xdg.configHome}/tmux";
    work = "${home}/devel/work";
    wrk = "${home}/devel/work";
    w = "${home}/devel/work";
    ansible = "${privateDevel}/ansible-stuff.git";
    zpl = "${config.xdg.configHome}/zsh/plugins/local";
    zsh = "${config.xdg.configHome}/zsh";
  };
  staticDirectories = {
    turris = "/mnt/turris";
    trs = "/mnt/turris";
    home-assistant = "/mnt/ha";
    homeassistant = "/mnt/ha";
    hass = "/mnt/ha";
    ha = "/mnt/ha";
  };
  directoryRegistrations = lib.concatMapStringsSep "\n" (name: ''
    hashdir-if-exists ${lib.escapeShellArg directories.${name}} ${lib.escapeShellArg name}
  '') (builtins.attrNames directories);
in
{
  programs.zsh = {
    # Keep these shared locations as defaults so a host module can replace
    # paths that differ on that machine (for example fnuc's /srv/hass).
    dirHashes = lib.mapAttrs (_: value: lib.mkDefault value) staticDirectories;
    shellAliases = lib.mapAttrs' (name: directory: {
      name = "cd${name}";
      value = lib.mkDefault "cd ${lib.escapeShellArg directory}";
    }) staticDirectories;

    initContent = lib.mkOrder 610 ''
      hashdir() {
        local directory="$1"
        shift

        local -a names
        if [[ -z "''${1:-}" ]]
        then
          names=("''${directory:t}")
        else
          names=("''${(@s/,/)@}")
        fi

        local name
        for name in "''${names[@]}"
        do
          hash -d "$name=$directory"
          alias "cd$name=cd ''${(q)directory}"
        done
      }

      hashdir-if-exists() {
        local directory="$1"
        shift
        [[ -n "$directory" && -d "$directory" ]] || return 1
        hashdir "$directory" "$@"
      }

      ${directoryRegistrations}

      local directory firefox_profile
      directory="''${TMPDIR:-/tmp}"
      hashdir-if-exists "$directory" tmp

      if [[ -n "''${PREFIX:-}" ]]
      then
        hashdir-if-exists "$PREFIX" pref
      fi

      for firefox_profile in "$HOME/.mozilla/firefox"/*default(N)
      do
        hashdir-if-exists "$firefox_profile" ffx
        break
      done
    '';
  };
}
