{ config, lib, ... }:

let
  # List of instance names
  instanceNames = [
    "oci-03"
    "rofl-02"
    "rofl-03"
    "rofl-04"
    "rofl-05"
  ];

  # Define a function to create an instance with common defaults
  createInstance = name: {
    type = "dracut";
    hostname = "${name}.heimat.dev";
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
