{
  config,
  inputs,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;

  gpcConfigPath = "${config.xdg.configHome}/gpc/config.json";
  zhj = "${config.home.homeDirectory}/bin/zhj";

  # playconsole-cli hardcodes $HOME/.playconsole-cli/config.json as its config
  # default and has no XDG support, so pin --config to an XDG path instead.
  gpc = pkgs.symlinkJoin {
    name = "playconsole-cli-xdg";
    paths = [ pkgs.playconsole-cli ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/gpc --add-flags "--config ${gpcConfigPath}"
    '';
  };
in
{
  imports = [ inputs.declaroid.homeManagerModules.default ];

  sops.secrets."google-play/service-account-json" = {
    mode = "0600";
    sopsFile = ../../secrets/shared.sops.yaml;
  };

  sops.templates."gpc-config" = {
    path = gpcConfigPath;
    mode = "0600";
    content = builtins.toJSON {
      default_profile = "default";
      profiles.default = {
        name = "default";
        credentials_path = config.sops.secrets."google-play/service-account-json".path;
      };
    };
  };

  home.packages = with pkgs; [
    aapt # aapt2, e.g. `aapt2 dump badging some.apk`
    android-tools # adb + fastboot
    gpc # playconsole-cli — Google Play Console CLI, wrapped for XDG config
    inputs.tsvtool.packages.${system}.default # pretty TSV/JSON/YAML/TOML tables, used by declaroid's devices/diff output
    pmbootstrap
    scrcpy
  ];

  xdg.desktopEntries = {
    scrcpy-mp4 = {
      name = "scrcpy (mp4)";
      genericName = "Android Remote Control";
      comment = "Display and control the mp4 Android device";
      exec = "${zhj} \"scrcpy::mp4 --notify\"";
      icon = "scrcpy";
      terminal = false;
      categories = [
        "Utility"
        "RemoteAccess"
      ];
    };

    scrcpy-px5 = {
      name = "scrcpy (px5)";
      genericName = "Android Remote Control";
      comment = "Display and control the px5 Android device";
      exec = "${zhj} \"scrcpy::px5 --notify\"";
      icon = "scrcpy";
      terminal = false;
      categories = [
        "Utility"
        "RemoteAccess"
      ];
    };

    scrcpy-zf10 = {
      name = "scrcpy (zf10)";
      genericName = "Android Remote Control";
      comment = "Display and control the zf10 Android device";
      exec = "${zhj} \"scrcpy::zf10 --notify\"";
      icon = "scrcpy";
      terminal = false;
      categories = [
        "Utility"
        "RemoteAccess"
      ];
    };
  };

  # configPath must be the live checkout, not a Nix-store copy:
  # android/all.yaml's `configs:` entries (mp4.yaml/px5.yaml/zf10.yaml) are
  # relative paths resolved against the config file's own directory, which
  # only exists in the real repo. See the option's own description
  # (declaroid's home-manager-module.nix) for why this -- not
  # $DECLAROID_CONFIG -- is what actually keeps `apply --enforce` from
  # ever silently targeting the wrong config: confirmed as a real
  # incident, a stale-environment shell fell back to declaroid's own
  # small built-in default and offered to uninstall every real app on two
  # devices.
  programs.declaroid = {
    enable = true;
    configPath = "${config.home.homeDirectory}/devel/private/pschmitt/nixos-config.git/android/all.yaml";
  };
}
