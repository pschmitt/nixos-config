{ config, ... }:
{
  services.netbird = {
    clients = {
      netbird-io = {
        environment = {
          NB_SETUP_KEY_FILE = config.sops.secrets."netbird-setup-key".path;
        };
      };
    };
  };
}
