{ inputs, pkgs, ... }:
{
  home.packages = [
    inputs.slack-react.packages.${pkgs.stdenv.hostPlatform.system}.slack-react
  ];
}
