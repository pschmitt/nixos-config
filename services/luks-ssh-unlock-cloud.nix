{ config, lib, ... }:

let
  # List of instance names
  instanceNames = [
    "oci-03"
    "rofl-08"
    "rofl-10"
    "rofl-11"
    "rofl-12"
    "rofl-13"
    "rofl-14"
  ];

  # Define a function to create an instance with common defaults
  createInstance = name: {
    type = "dracut";
    hostname = "${name}.brkn.lol";
    key = "/home/pschmitt/.ssh/id_ed25519";
    passphraseFile = config.sops.secrets.${"luks/" + name}.path;
    sleepInterval = 30;

    healthcheck = {
      enable = true;
      command = "mount | grep encrypted";
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
