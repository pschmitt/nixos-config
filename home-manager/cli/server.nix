{
  inputs,
  pkgs,
  ...
}:
{
  imports = [
    ./eget.nix
    ./zsh
  ];

  home.packages = with pkgs; [
    atuin
    bat
    direnv
    eza
    fd
    fzf
    inputs.bunq-sh.packages.${pkgs.stdenv.hostPlatform.system}.bunq
    linkding-cli
  ];
}
