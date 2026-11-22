{ pkgs, ... }:
let
  update = pkgs.writeShellApplication {
    name = "update";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = builtins.readFile ./scripts/self-update.sh;
  };
in
{
  home.file.".local/libexec/tpp/plugins/update".source = "${update}/bin/update";
}
