{
  config,
  inputs,
  ...
}:
{
  sops.secrets."hass/sshfs/private-key" = config.sops.mkHostSecret {
    mode = "0400";
  };

  sops.secrets."luks-ssh-unlock/rofl-10-identity" = {
    sopsFile = inputs.nixos-config-private.outPath + "/hosts/rofl-10/secrets.sops.yaml";
    key = "luks-ssh-unlock-identity";
    mode = "0400";
  };

  services = {
    luks-ssh-unlock-fleet.selfKeyPath = config.sops.secrets."luks-ssh-unlock/rofl-10-identity".path;
    home-assistant.sshfs.identityFile = config.sops.secrets."hass/sshfs/private-key".path;
    home-assistant.sshfs.host = "homeassistant.snake-eagle.ts.net";
  };
}
