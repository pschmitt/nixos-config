{ inputs, ... }:
{
  imports = [
    inputs.catppuccin.nixosModules.catppuccin
  ];

  catppuccin.enable = true;
  catppuccin.flavor = "mocha";

  # environment.sessionVariables = {
  #   GTK_THEME = "Colloid-Dark";
  # };
}
