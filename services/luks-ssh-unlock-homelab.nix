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

  secretSuffixes = [
    "passphrase"
    "knownHosts"
    "initrdKnownHosts"
  ];

  # Define a function to create an instance with common defaults
  createInstance = instance: {
    type = "systemd";
    hostname = instance.host;
    passphraseFile = config.sops.secrets.${"luks/" + instance.name + "/passphrase"}.path;
    sshKnownHostsFile = config.sops.secrets.${"luks/" + instance.name + "/knownHosts"}.path;
    initrdKnownHostsFile = config.sops.secrets.${"luks/" + instance.name + "/initrdKnownHosts"}.path;

    debug = true;
    eventsFile = "/var/log/luks-ssh-unlock/${instance.name}.events.log";

    forceIpv4 = true;
    sleepInterval = 30;

    initrdCheck = {
      enable = false;
    };

    jumpHost = {
      enable = true;
      hostname = "turris.${config.domains.vpn}";
    };

    healthcheck = {
      enable = true;
      command = "mount | grep -v tmpfs | grep luks";
    };

    notifications = {
      enable = true;
      mail = {
        enable = true;
        recipient = config.mainUser.email;
        from = "luks-ssh-unlock <${config.networking.hostName}@${config.domains.main}>";
        subject = "LUKS SSH Unlocker: ${instance.name} -> #event_type";
      };
    };
  };

  # Helper to define sops secrets for each instance
  defineSopsSecrets = lib.listToAttrs (
    lib.lists.concatMap (
      instance:
      lib.lists.map (suffix: {
        name = "luks/${instance.name}/${suffix}";
        value = {
          inherit (config.custom) sopsFile;
        };
      }) secretSuffixes
    ) instances
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

  systemd.services = lib.listToAttrs (
    lib.lists.map (instance: {
      name = "luks-ssh-unlock-${instance.name}";
      value = {
        wants = [
          "network-online.target"
          "sops-install-secrets.service"
        ];
        after = [
          "network-online.target"
          "sops-install-secrets.service"
        ];
        serviceConfig = {
          LogsDirectory = "luks-ssh-unlock";
          Restart = "always";
          RestartSec = "10s";
        };
      };
    }) instances
  );
}
