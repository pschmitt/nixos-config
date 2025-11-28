{ config, ... }:
let
  secrets = [
    "ssh/host_keys/rsa/privkey"
    "ssh/host_keys/rsa/pubkey"
    "ssh/host_keys/ed25519/privkey"
    "ssh/host_keys/ed25519/pubkey"
  ];
in
{
  sops.secrets = builtins.listToAttrs (
    map (secret: {
      name = secret;
      value = {
        inherit (config.custom) sopsFile;
      };
    }) secrets
  );

  environment = {
    etc = {
      "ssh/ssh_host_rsa_key" = {
        source = config.sops.secrets."ssh/host_keys/rsa/privkey".path;
        user = "root";
        group = "root";
        mode = "0400";
      };
      "ssh/ssh_host_ed25519_key" = {
        source = config.sops.secrets."ssh/host_keys/ed25519/privkey".path;
        user = "root";
        group = "root";
        mode = "0400";
      };
      "ssh/ssh_host_rsa_key.pub" = {
        source = config.sops.secrets."ssh/host_keys/rsa/pubkey".path;
        mode = "0444";
        user = "root";
        group = "root";
      };
      "ssh/ssh_host_ed25519_key.pub" = {
        source = config.sops.secrets."ssh/host_keys/ed25519/pubkey".path;
        mode = "0444";
        user = "root";
        group = "root";
      };
    };
  };

  # services.openssh.hostKeys = [
  #   {
  #     path = config.sops.secrets."ssh/host_keys/ed25519/privkey".path;
  #     type = "ed25519";
  #   }
  #   {
  #     path = config.sops.secrets."ssh/host_keys/rsa/privkey".path;
  #     type = "rsa";
  #   }
  # ];
}
