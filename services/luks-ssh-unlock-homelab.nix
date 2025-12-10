{
  config,
  inputs,
  lib,
  ...
}:

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
    type = "systemd";
    hostname = instance.host;
    passphraseFile = config.sops.secrets.${"luks/" + instance.name}.path;
    forceIpv4 = true;
    sleepInterval = 30;

    jumpHost = {
      enable = true;
      hostname = "turris.nb.brkn.lol";
    };

    healthcheck = {
      enable = true;
      command = "mount | grep -v tmpfs | grep luks";
    };

    emailNotifications = {
      enable = true;
      recipient = config.mainUser.email;
      sender = "luks-ssh-unlock <${config.networking.hostName}@${config.domains.main}>";
      subject = "LUKS SSH Unlocker: ${instance.name} -> #event_type";
    };
  };

  # Helper to define sops secrets for each instance
  defineSopsSecrets = lib.listToAttrs (
    lib.lists.map (instance: {
      name = "luks/${instance.name}";
      value = {
        inherit (config.custom) sopsFile;
      };
    }) instances
  );
in
{
  imports = [ inputs.luks-ssh-unlock.nixosModules.default ];

  # Define sops secrets using the helper function
  sops.secrets = defineSopsSecrets;

  services.luks-ssh-unlock = {
    enable = true;
    instances = lib.listToAttrs (
      lib.lists.map (instance: {
        inherit (instance) name;
        value = createInstance instance;
      }) instances
    );
  };
}
