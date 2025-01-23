{
  lib,
  osConfig,
  pkgs,
  ...
}:

let
  enableNvidiaOffload = osConfig.hardware.nvidia.prime.offload.enable;
  obs-nvidia = pkgs.writeShellScriptBin "obs-nvidia" ''
    nvidia-offload ${pkgs.obs-studio}/bin/obs "$@"
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
  home.packages =
    [
      pkgs.obs-cli
      (pkgs.writeShellScriptBin "obs-studio" ''
        ${pkgs.flatpak}/bin/flatpak run com.obsproject.Studio "$@"
      '')
      (pkgs.writeShellScriptBin "obs-studio-custom" ''
        ${pkgs.flatpak}/bin/flatpak run com.obsproject.Studio \
          --minimize-to-tray \
          --startvirtualcam \
          --scene "Joining soon" \
          --disable-shutdown-check \
          "$@"
      '')
      (pkgs.writeShellScriptBin "obs-studio-ustreamer" ''
        ${pkgs.ustreamer}/bin/ustreamer -d /dev/video10 "$@"
      '')
    ]
    ++ lib.optional enableNvidiaOffload obs-nvidia
    ++ lib.optional enableNvidiaOffload obs-nvidia-custom;

  programs.obs-studio = {
    enable = true;
    # package = pkgs.obs-studio;
    plugins = with pkgs.obs-studio-plugins; [
      droidcam-obs
      obs-text-pthread
      obs-freeze-filter
      obs-replay-source
    ];
  };

  services.flatpak = {
    remotes = {
      "flathub" = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      "flathub-beta" = "https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo";
    };
    packages = [
      # NOTE The "//" are here cause we omitted the cpu arch
      "flathub:app/com.obsproject.Studio//stable"
      "flathub:runtime/com.obsproject.Studio.Plugin.DroidCam//stable"
    ];
    overrides = {
      "com.obsproject.Studio" = {
        filesystems = [
          "/nix:ro"
          "/run/current-system/sw/bin:ro"
        ];
      };
    };
  };

  # FIXME Below plugins do not work anymore as of 2024-10-07
  # see https://github.com/Blackstareye/obs-plugin-freeze-filter-flatpak
  # WARNING The directory names DO matter. The freeze-filter for instance will
  # not load if the directory is named obs-freeze-filter.
  home.file.".var/app/com.obsproject.Studio/config/obs-studio/plugins/text-pango" = {
    source = "${pkgs.obs-studio-plugins-flatpak-obs-text-pango-bin}/obs-plugins/obs-text-pango";
  };
  home.file.".var/app/com.obsproject.Studio/config/obs-studio/plugins/obs-text-pthread" = {
    source = "${pkgs.obs-studio-plugins-flatpak-obs-text-pthread-bin}/obs-plugins/obs-text-pthread";
  };
  home.file.".var/app/com.obsproject.Studio/config/obs-studio/plugins/freeze-filter" = {
    source = "${pkgs.obs-studio-plugins-flatpak-obs-freeze-filter-bin}/obs-plugins/obs-freeze-filter";
  };
  home.file.".var/app/com.obsproject.Studio/config/obs-studio/plugins/replay-source" = {
    source = "${pkgs.obs-studio-plugins-flatpak-obs-replay-source-bin}/obs-plugins/obs-replay-source";
  };

  home.file.".config/obs-studio/scripts/bounce.lua".source = (
    builtins.fetchurl {
      url = "https://raw.githubusercontent.com/pschmitt/obs-bounce/4a01d2096a3ffa886d6bbfb97c27301065e33f55/bounce.lua";
      sha256 = "1w1ks5nf4icgbqmbcp8cvmv30426srhcspjad3gmkiin6vxz42ny";
    }
  );
}
