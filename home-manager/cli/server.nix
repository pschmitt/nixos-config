{
  inputs,
  pkgs,
  ...
}:
{
  imports = [
    ./zsh
    ./todoist
  ];

  home.packages = with pkgs; [
    atuin
    bat
    direnv
    eget
    eza
    fd
    fzf
    inputs.bunq-sh.packages.${pkgs.stdenv.hostPlatform.system}.bunq
    inputs.tdc.packages.${pkgs.stdenv.hostPlatform.system}.tdc
    todoist-cli
    linkding-cli
  ];
}
