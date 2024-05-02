{ config, lib, ... }:

let
  # List of instance names
  instanceNames = [ "fnuc" ];

  # Define a function to create an instance with common defaults
  createInstance = name: {
    type = "dracut";
    hostname = "${name}.lan";
    passphraseFile = config.age.secrets.${"passphrase-" + name}.path;
    forceIpv4 = true;
    sleepInterval = 30;

    jumpHost = {
      hostname = "turris-ts.heimat.dev";
    };

    healthcheck = {
      enable = true;
      command = "mount | grep luks";
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

