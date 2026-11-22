{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cli = inputs.circus.packages.${pkgs.stdenv.hostPlatform.system}.circus-cli;
  wrapper = pkgs.writeShellApplication {
    name = "circusctl";
    runtimeInputs = [
      pkgs.openssh
      pkgs.python3
      pkgs.rbw
    ];
    text =
      builtins.replaceStrings
        [ "@CIRCUSCTL@" "@VAULT_ENTRY@" ]
        [ "${cli}/bin/circusctl" (lib.escapeShellArg "circus.${config.domains.main}") ]
        (builtins.readFile ./scripts/circusctl.sh);
  };
in
{
  home-manager.users.${config.mainUser.username}.home.packages = [ wrapper ];
}
