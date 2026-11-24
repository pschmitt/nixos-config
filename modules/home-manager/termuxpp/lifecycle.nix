{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixpp.lifecycle;
  check-runtime = pkgs.writeShellApplication {
    name = "nixpp-check-runtime";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec python3 -I ${./scripts/check-runtime.py} "$@"
    '';
  };
in
{
  options.nixpp.lifecycle.enable = lib.mkEnableOption "Android acceptance checks during standard Home Manager activation";

  config = lib.mkIf cfg.enable {
    home = {
      packages = [ check-runtime ];
      activation = {
        androidPreflight = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
          if [[ -f /etc/ssh/sshd_config ]]
          then
            run ${pkgs.openssh}/bin/sshd -t -f /etc/ssh/sshd_config
          fi
          run ${check-runtime}/bin/nixpp-check-runtime --isolated --generation "$newGenPath" --thorough
        '';

        androidAcceptance = lib.hm.dag.entryAfter [ "linkGeneration" "onFilesChange" "installPackages" ] ''
          run env NIX_CONF_DIR=${lib.escapeShellArg "${config.xdg.configHome}/nix"} \
            ${check-runtime}/bin/nixpp-check-runtime --generation "$newGenPath" --thorough
        '';
      };
    };
  };
}
