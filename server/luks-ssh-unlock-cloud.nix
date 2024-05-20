{ config, lib, ... }:

let
  # List of instance names
  instanceNames = [ "oci-03" "rofl-02" "rofl-03" "rofl-04" "rofl-05" ];

  # Define a function to create an instance with common defaults
  createInstance = name: {
    type = "dracut";
    hostname = "${name}.heimat.dev";
    key = "/home/pschmitt/.ssh/id_ed25519";
    passphraseFile = config.age.secrets.${"passphrase-" + name}.path;
    sleepInterval = 30;

    healthcheck = {
      enable = true;
      command = "mount | grep encrypted";
    };
  };

  # Helper to define age secrets for each instance
  defineAgeSecrets = lib.listToAttrs (lib.lists.map
    (name:
      {
        name = "passphrase-${name}";
        value = { file = ../secrets/${name}/luks-passphrase-root.age; };
      })
    instanceNames);

in
{
  # Define age secrets using the helper function
  age.secrets = defineAgeSecrets;

  services.luks-ssh-unlocker = {
    enable = true;
    instances = lib.listToAttrs (lib.lists.map
      (name:
        { name = name; value = createInstance name; })
      instanceNames);
  };
}

