{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  enableNvidiaOffload = config.host.nvidiaPrimeOffload;
  # OBS 33 expects the existing Nixpkgs plugin layout through legacy paths.
  # Remove this wrapper when the pinned Nixpkgs includes the wrapOBS fix:
  # https://github.com/NixOS/nixpkgs/pull/591735
  # Keeping it then would overwrite the upstream legacy plugin paths.
  obsWithLegacyPlugins = pkgs.symlinkJoin {
    name = "${pkgs.master.obs-studio.name}-legacy-plugins";
    paths = [ pkgs.master.obs-studio ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/obs" \
        --run 'export OBS_LEGACY_PLUGINS_PATH="$OBS_PLUGINS_PATH" OBS_LEGACY_PLUGINS_DATA_PATH="$OBS_PLUGINS_DATA_PATH"'
    '';
  };
  registrar = import ./obs-register-script.nix { inherit pkgs; };
  obsAutostart = pkgs.writeShellApplication {
    name = "obs-hyprland-autostart";
    runtimeInputs = with pkgs; [
      config.programs.obs-studio.finalPackage
      coreutils
      curl
      jq
      procps
      registrar
      systemd
    ];
    text = builtins.readFile ./obs-autostart.sh;
  };
  obsAutostartExec = "${obsAutostart}/bin/obs-hyprland-autostart";
  obs-nvidia = pkgs.writeShellScriptBin "obs-nvidia" ''
    ${registrar}/bin/obs-register-script --quiet || true
    nvidia-offload ${config.programs.obs-studio.finalPackage}/bin/obs "$@"
  '';
  obs-nvidia-custom = pkgs.writeShellScriptBin "obs-nvidia-custom" ''
    ${obs-nvidia}/bin/obs-nvidia \
        --minimize-to-tray \
        --startvirtualcam \
        --scene "Joining soon" \
        "$@"
  '';
in
{
  imports = [ ./obs-broadcast-audio.nix ];

  home.packages = [
    inputs.obs-cli.packages.${pkgs.stdenv.hostPlatform.system}.obs-cli
    obsAutostart

    (pkgs.writeShellScriptBin "obs-studio-ustreamer" ''
      ${pkgs.ustreamer}/bin/ustreamer -d /dev/video10 "$@"
    '')
  ]
  ++ lib.optionals enableNvidiaOffload [
    obs-nvidia
    obs-nvidia-custom
  ];

  programs.obs-studio = {
    enable = true;
    package = obsWithLegacyPlugins;
    plugins = with pkgs.obs-studio-plugins; [
      droidcam-obs
      obs-text-pthread
      obs-freeze-filter
      obs-replay-source
    ];
  };

  xdg.desktopEntries = {
    "obs-studio-custom" = {
      name = "OBS Studio (Custom)";
      comment = "Start OBS with our custom flags";
      icon = "com.obsproject.Studio";
      exec = obsAutostartExec;
      terminal = false;
    };

    # Autostart-only variant: bails out on weekends and public holidays.
    # Hidden from launchers so manually starting OBS always works, whatever
    # the day.
    "obs-studio-autostart" = {
      name = "OBS Studio (Autostart)";
      comment = "Start OBS with our custom flags, but only on workdays";
      icon = "com.obsproject.Studio";
      exec = "${obsAutostartExec} --workdays-only";
      terminal = false;
      noDisplay = true;
    };
  };

  home.file.".config/obs-studio/scripts/bounce.lua".source = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/pschmitt/obs-bounce/4a01d2096a3ffa886d6bbfb97c27301065e33f55/bounce.lua";
    sha256 = "1w1ks5nf4icgbqmbcp8cvmv30426srhcspjad3gmkiin6vxz42ny";
  };
}
