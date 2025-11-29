{ inputs, pkgs, ... }:
{
  imports = [
    inputs.catppuccin.nixosModules.catppuccin
  ];

  catppuccin.enable = true;
  catppuccin.flavor = "mocha";

  # environment.sessionVariables = {
  #   GTK_THEME = "Colloid-Dark";
  # };

  environment.systemPackages = with pkgs; [
    gtk3 # gtk-update-icon-cache
    gtk4 # gtk4-update-icon-cache
  ];
}
