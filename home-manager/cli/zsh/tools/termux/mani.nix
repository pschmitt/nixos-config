{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  termuxMode = config.termux.enable or false;
  termuxPackageSet = import ../../../../../pkgs/termux-native/package-set.nix {
    inherit inputs pkgs;
  };
  inherit (termuxPackageSet.termuxPackages) mani;
  maniArtifacts = pkgs.runCommand "mani-zsh-artifacts" { } ''
    mkdir -p "$out/completions" "$out/man/man1"
    ${pkgs.buildPackages.mani}/bin/mani completion zsh > "$out/completions/_mani"
    ${pkgs.buildPackages.mani}/bin/mani gen --dir "$out/man/man1"
  '';
in
{
  home.packages = [ (if termuxMode then mani else pkgs.mani) ];
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
