{ pkgs, ... }:
let
  permissions = pkgs.writeShellApplication {
    name = "permissions";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.jq
      pkgs.util-linux
    ];
    text = builtins.readFile ./scripts/setup-permissions.sh;
  };
in
{
  home.file.".local/libexec/tpp/plugins/permissions".source = "${permissions}/bin/permissions";
}
