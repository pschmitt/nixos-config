{ config, ... }:
{
  sops.secrets."nix/store/privkey" = {
    sopsFile = config.custom.sopsFile;
  };

  services.harmonia = {
    enable = true;
    signKeyPath = config.sops.secrets."nix/store/privkey".path;
    settings = {
      bind = "127.0.0.1:5000";
    };
  };

  services.nginx = {
    virtualHosts."cache.${config.networking.hostName}.nb.brkn.lol" = {
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;

      locations."/".extraConfig = ''
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_redirect http:// https://;
        proxy_http_version 1.1;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        zstd on;
        zstd_types application/x-nix-archive;
      '';
    };
  };
}
