{
  inputs,
  pkgs,
  ...
}:
let
  termuxTools =
    pkgs.runCommand "termux-shell-tools"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.gnused
        ];
      }
      ''
        mkdir -p "$out/bin"
        DEST="$out/bin" ${pkgs.bash}/bin/bash ${inputs.termux-tools}/install.sh
      '';
in
{
  home.packages = [ termuxTools ];
}
