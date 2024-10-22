{ config, ... }:
{
  sops.secrets."bitwarden/password" = {
    sopsFile = config.custom.sopsFile;
    owner = config.custom.username;
  };
}
