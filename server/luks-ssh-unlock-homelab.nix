{ config, lib, ... }:

let
  # List of instance names
  instances = [
    {
      name = "fnuc";
      host = "10.5.0.14";
    }
  ];

  # Define a function to create an instance with common defaults
  createInstance = instance: {
    type = "dracut";
    hostname = instance.host;
    passphraseFile = config.sops.secrets.${"luks/" + instance.name}.path;
    forceIpv4 = true;
    sleepInterval = 30;

    jumpHost = {
      # hostname = "turris.ts.brkn.lol";
      # hostname = "100.76.194.3";
      hostname = "turris.netbird.cloud";
    };

    healthcheck = {
      enable = true;
      command = "mount | grep -v tmpfs | grep luks";
    };
  };

  # Helper to define sops secrets for each instance
  defineSopsSecrets = lib.listToAttrs (
    lib.lists.map (instance: {
      name = "luks/${instance.name}";
      value = {
        sopsFile = config.custom.sopsFile;
      };
    }) instances
  );
in
{
  # Define sops secrets using the helper function
  sops.secrets = defineSopsSecrets;

  services.luks-ssh-unlocker = {
    enable = true;
    instances = lib.listToAttrs (
      lib.lists.map (instance: {
        name = instance.name;
        value = createInstance instance;
      }) instances
    );
  };
}
