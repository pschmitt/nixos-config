{ inputs, ... }:
{
  imports = [

    inputs.flatpaks.nixosModule
  ];
  xdg.portal = {
    enable = true; # required for flatpak
    xdgOpenUsePortal = true; # fix xdg-open
  };
  services.flatpak = {
    enable = true;
    remotes = {
      "flathub" = "https://dl.flathub.org/repo/flathub.flatpakrepo";
      "flathub-beta" = "https://dl.flathub.org/beta-repo/flathub-beta.flatpakrepo";
    };
    packages = [ ];
  };
}
