{ pkgs, ... }:
{
  # FIXME This should not be necessary, but as of today (2023.12.16) qt5ct must
  # be installed a systemPackage (home manager is not enough!)
  # https://github.com/NixOS/nixpkgs/issues/239909#issuecomment-1766317147
  environment.systemPackages = with pkgs; [
    qt5ct
    qt6ct
  ];

  catppuccin.enable = true;
  catppuccin.flavor = "mocha";

  environment.sessionVariables = {
    GTK_THEME = "Colloid-Dark-Nord";
  };
}
