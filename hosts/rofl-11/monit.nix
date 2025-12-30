{
  lib,
  config,
  pkgs,
  ...
}:
let
  mullvadExpiration = pkgs.writeShellScript "mullvad-expiration" ''
    export PATH=${
      pkgs.lib.makeBinPath [
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
      ]
    }
    ${builtins.readFile ../../services/monit/mullvad-expiration.sh}
  '';

  monitExtraConfig = ''
    check program "dockerd" with path "${pkgs.systemd}/bin/systemctl is-active docker"
      group docker
      if status > 0 then alert

    check program mullvad with path "${mullvadExpiration} --warning 15 ${
      config.sops.secrets."mullvad/account".path
    }"
      group piracy
      every "11-13 3,6,12,18,23 * * *"
      if status != 0 then alert
  '';
in
{
  sops.secrets."mullvad/account".sopsFile = config.custom.sopsFile;

  services.monit.config = lib.mkAfter monitExtraConfig;
}
