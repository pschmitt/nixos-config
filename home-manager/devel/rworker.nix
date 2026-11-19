# rworker, the client for ad-hoc build workers (github:pschmitt/rworker):
# its Home Manager module, with this flake's nixpkgs build of the package.
# The control host and key are the client's defaults.
{ inputs, pkgs, ... }:
{
  imports = [ inputs.rworker.homeModules.default ];

  programs.rworker = {
    enable = true;
    package = pkgs.rworker;
    aliases = [ "rk" ];
  };
}
