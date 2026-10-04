{
  config,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxMani = pkgs.callPackage ../../../../../pkgs/termux-native/go-binary.nix {
    package = pkgs.mani;
    binary = "mani";
    skipPostInstall = true;
  };
  maniArtifacts = pkgs.runCommand "mani-zsh-artifacts" { } ''
    mkdir -p "$out/completions" "$out/man/man1"
    ${pkgs.buildPackages.mani}/bin/mani completion zsh > "$out/completions/_mani"
    ${pkgs.buildPackages.mani}/bin/mani gen --dir "$out/man/man1"
  '';
in
{
  home.packages = [ (if termuxMode then termuxMani else pkgs.mani) ];
  xdg.configFile."zsh/completions/_mani".source = "${maniArtifacts}/completions/_mani";
  xdg.dataFile."man/man1/mani.1".source = "${maniArtifacts}/man/man1/mani.1";

  programs.zsh.initContent = lib.mkIf termuxMode (
    lib.mkOrder 1500 ''
      if [[ -o interactive && -n "''${_comps+x}" ]]
      then
        autoload -Uz _mani
        compdef _mani mani
      fi
    ''
  );
}
