{ ... }:
{
  services.flatpak = {
    remotes = {
      "flathub" = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      "flathub-beta" = "https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo";
    };
    # packages = [
    #   # NOTE The "//" are here cause we omitted the cpu arch
    #   "flathub:app/com.obsproject.Studio//stable"
    #   "flathub:runtime/com.obsproject.Studio.Plugin.DroidCam//stable"
    # ];
    # overrides = {
    #   "com.obsproject.Studio" = {
    #     filesystems = [
    #       "/nix:ro"
    #       "/run/current-system/sw/bin:ro"
    #     ];
    #   };
    # };
  };
}
