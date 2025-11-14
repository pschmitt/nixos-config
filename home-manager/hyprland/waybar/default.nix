{ lib, pkgs, config, ... }:
let
  # Gather scripts from the scripts directory.
  scriptsDir = ./scripts;
  scripts = lib.filterAttrs (_: type: type == "regular") (builtins.readDir scriptsDir);
  mkScriptFile = name: {
    name = "waybar/${name}";
    value = {
      source = "${scriptsDir}/${name}";
      executable = true;
    };
  };
in
{
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    systemd.enableDebug = true;
    style = builtins.readFile ./style.css;
    settings = import ./config.nix;
  };

  xdg.configFile =
    {
      "waybar/cava.config".source = ./cava.config;
    }
    // (lib.mapAttrs' (name: _: {
      name = "waybar/custom_modules/${name}";
      value = {
        source = "${./custom_modules}/${name}";
        executable = true;
      };
    }) (lib.filterAttrs (_: t: t == "regular") (builtins.readDir ./custom_modules)))
    // (lib.listToAttrs (map mkScriptFile (builtins.attrNames scripts)));
  
  home.packages = lib.mkAfter [
    pkgs.ComicCode
    pkgs.ComicCodeNF
  ];

  home.activation."waybar-font-cache" = lib.hm.dag.entryAfter [ "installPackages" ] ''
    ${pkgs.fontconfig}/bin/fc-cache -r "${config.home.homeDirectory}/.local/share/fonts" || true
  '';
}
