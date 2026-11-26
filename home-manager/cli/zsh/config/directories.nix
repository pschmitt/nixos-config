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
    turris = "/mnt/turris";
    trs = "/mnt/turris";
    home-assistant = "/mnt/ha";
    homeassistant = "/mnt/ha";
    hass = "/mnt/ha";
    ha = "/mnt/ha";
  };
in
{
  programs.zsh = {
    # Named directories (~nix, ~zpl, ...) and their cd<name> aliases. Defaults,
    # so a host module can replace paths that differ on that machine.
    dirHashes = lib.mapAttrs (_: lib.mkDefault) directories;
    shellAliases = lib.mapAttrs' (
      name: directory: lib.nameValuePair "cd${name}" (lib.mkDefault "cd ${lib.escapeShellArg directory}")
    ) directories;

    # Only known at runtime. Before p10k.zsh (order 891), whose dir classes
    # use ~tmp.
    initContent = lib.mkOrder 610 ''
      () {
        local name directory
        local -a firefox_profiles=("$HOME/.mozilla/firefox"/*default(N/))
        for name directory in \
          tmp "''${TMPDIR:-/tmp}" \
          pref "''${PREFIX:-}" \
          ffx "''${firefox_profiles[1]:-}"
        do
          [[ -n "$directory" && -d "$directory" ]] || continue
          hash -d "$name=$directory"
          alias "cd$name=cd ''${(q)directory}"
        done
      }
    '';
  };
}
