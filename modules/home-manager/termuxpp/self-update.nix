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
  app = pkgs.writeShellApplication {
    name = "app";
    text = ''
      export TPP_APP_UPDATE=${update}/bin/update
      ${builtins.readFile ./scripts/app.sh}
    '';
  };
in
{
  home.file.".local/libexec/tpp/plugins/app".source = "${app}/bin/app";
}
