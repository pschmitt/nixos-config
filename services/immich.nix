{
  config,
  lib,
  pkgs,
  ...
}:
let
  hostnames = [
    "img.${config.domains.main}"
    "img.${config.networking.hostName}.${config.domains.main}"
    "immich.${config.domains.main}"
    "immich.${config.networking.hostName}.${config.domains.main}"
  ];
  primaryHost = builtins.head hostnames;
  serverAliases = lib.remove primaryHost hostnames;
in
{
  imports = [ ./immich-face-to-album.nix ];

  services = {
    immich = {
      enable = true;
      # immich fails to build on unstable as of 2024-12-29
      # Fix:
      # https://github.com/NixOS/nixpkgs/pull/369042
      # https://nixpkgs-tracker.ocfox.me/?pr=369042
      package = pkgs.master.immich;
      # NOTE listening on "localhost" leads to immich only listening on IPv6
      host = "127.0.0.1";
      port = 2283;
      mediaLocation = "/mnt/data/srv/immich/media";
    };

    nginx.virtualHosts."${primaryHost}" = {
      inherit serverAliases;
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://${config.services.immich.host}:${toString config.services.immich.port}";
        recommendedProxySettings = true;
        proxyWebsockets = true;
        # Allow uploading large files
        # https://immich.app/docs/FAQ/#why-are-only-photos-and-not-videos-being-uploaded-to-immich
        extraConfig = ''
          client_max_body_size 50000M;
        '';
      };
    };

    monit.config = lib.mkAfter ''
      check host "immich" with address "${primaryHost}"
        group services
        depends on postgresql
        restart program = "${pkgs.systemd}/bin/systemctl restart immich-server"
        if failed
          port 443
          protocol https
          with timeout 15 seconds
          and certificate valid for 5 days
        then restart
        if 5 restarts within 10 cycles then alert
    '';
  };

}
