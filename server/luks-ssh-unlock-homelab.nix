{ config, lib, ... }:

let
  # List of instance names
  instances = [
    {
      name = "fnuc";
      host = "fnuc.lan";
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
      hostname = "turris.nb.brkn.lol";
    };

    healthcheck = {
      enable = true;
      command = "mount | grep -v tmpfs | grep luks";
    };

    emailNotifications = {
      enable = true;
      recipient = config.custom.email;
      sender = "luks-ssh-unlock <${config.networking.hostName}@${config.custom.mainDomain}>";
      subject = "LUKS SSH Unlocker: ${instance.name} -> #event_type";
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
