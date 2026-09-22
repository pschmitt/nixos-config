{
  config,
  inputs,
  ...
}:
{
  sops.secrets."hass/sshfs/private-key" = config.custom.mkSecret {
    mode = "0400";
  };

  sops.secrets."luks-ssh-unlock/rofl-10-identity" = {
    sopsFile = inputs.nixos-config-private.outPath + "/hosts/rofl-10/secrets.sops.yaml";
    key = "luks-ssh-unlock-identity";
    mode = "0400";
  };

  custom = {
    luksSshUnlockFleet.selfKeyPath = config.sops.secrets."luks-ssh-unlock/rofl-10-identity".path;
    homeAssistant.sshfs.identityFile = config.sops.secrets."hass/sshfs/private-key".path;
    homeAssistant.sshfs.host = "homeassistant.snake-eagle.ts.net";
  };
}
