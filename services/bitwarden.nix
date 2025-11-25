{ config, ... }:
{
  sops.secrets."bitwarden/password" = {
    inherit (config.custom) sopsFile;
    owner = config.custom.username;
  };
}
