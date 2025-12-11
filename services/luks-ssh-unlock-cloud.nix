{
  config,
  inputs,
  lib,
  ...
}:

let
  # List of instance names
  instanceNames = [
    "oci-03"
    "rofl-10"
    "rofl-11"
    "rofl-12"
    "rofl-13"
    "rofl-14"
  ];

  # Define a function to create an instance with common defaults
  createInstance = name: {
    type = "dracut";
    hostname = "${name}.${config.domains.main}";
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
        inherit (config.custom) sopsFile;
      };
    }) instanceNames
  );
in
{
  imports = [ inputs.luks-ssh-unlock.nixosModules.default ];

  # Define sops secrets using the helper function
  sops.secrets = defineSopsSecrets;

  services.luks-ssh-unlock = {
    enable = true;
    instances = lib.listToAttrs (
      lib.lists.map (name: {
        inherit name;
        value = createInstance name;
      }) instanceNames
    );
  };
}
