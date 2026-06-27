{ pkgs, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  upstreamPlugins = inputs.calibre-plugins.packages.${system};

  mkPlugin =
    name: zip:
    pkgs.runCommand "calibre-plugin-${name}" { } ''
      mkdir -p $out
      cp ${zip} $out/${name}.zip
    '';
in
{
  programs.calibre = {
    enable = true;
    plugins = [
      (mkPlugin "acsm-calibre-plugin" upstreamPlugins.acsm-calibre-plugin)
      (mkPlugin "DeDRM" upstreamPlugins.dedrm-plugin)
    ];
  };
}
