{ config, pkgs, ... }:
{
  home.packages = [ pkgs.tea ];

  # tea (Gitea/Forgejo CLI) login for Codeberg. The token is rendered from
  # sops at activation, so config.yml never hits the Nix store.
  sops = {
    secrets."codeberg/token".sopsFile = config.host.sopsDefaultFile;

    templates."tea-config.yml" = {
      path = "${config.xdg.configHome}/tea/config.yml";
      mode = "0600";
      content = ''
        logins:
          - name: codeberg
            url: https://codeberg.org
            token: ${config.sops.placeholder."codeberg/token"}
            default: true
            ssh_host: codeberg.org
            user: pschmitt
            version_check: false
      '';
    };
  };
}
