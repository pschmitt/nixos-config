{ config, lib, ... }:

let
  # List of instance names
  instanceNames = [ "fnuc" ];

  # Define a function to create an instance with common defaults
  createInstance = name: {
    type = "dracut";
    hostname = "${name}.lan";
    passphraseFile = config.sops.secrets.${"luks/" + name}.path;
    forceIpv4 = true;
    sleepInterval = 30;

    jumpHost = {
      # hostname = "turris.ts.brkn.lol";
      # hostname = "100.76.194.3";
      hostname = "turris.netbird.cloud";
    };

    healthcheck = {
      enable = true;
      command = "mount | grep luks";
    };
  };

  # Helper to define sops secrets for each instance
  defineSopsSecrets = lib.listToAttrs (
    lib.lists.map (name: {
      name = "luks/${name}";
      value = {
        sopsFile = config.custom.sopsFile;
      };
    }) instanceNames
  );
in
{
  # Define sops secrets using the helper function
  sops.secrets = defineSopsSecrets;

  services.luks-ssh-unlocker = {
    enable = true;
    instances = lib.listToAttrs (
      lib.lists.map (name: {
        name = name;
        value = createInstance name;
      }) instanceNames
    );
  };
}
