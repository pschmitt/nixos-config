{
  inputs,
  pkgs,
  ...
}:
{
  home.packages = [
    inputs.nbx.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
