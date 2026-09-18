{
  config,
  inputs,
  lib,
  ...
}:

let
  targets = [
    {
      name = "fnuc";
      hostname = "fnuc.lan";
      hasInitrdCheck = false;
      healthcheckCmd = "mount | grep -v tmpfs | grep luks";
    }
    {
      name = "ge2";
      hostname = "ge2.lan";
      hasInitrdCheck = true;
      healthcheckCmd = "mount | grep encrypted";
    }
    {
      name = "gk4";
      hostname = "gk4.lan";
      hasInitrdCheck = true;
      healthcheckCmd = "mount | grep luks-root";
    }
    {
      name = "oci-01";
      hostname = "oci-01.brkn.lol";
      configDir = "/srv/luks-ssh-unlock/config/oci-01-nixos";
      hasInitrdCheck = false;
      healthcheckCmd = "mount | grep encrypted";
    }
    {
      name = "oci-03";
      hostname = "oci-03.brkn.lol";
      hasInitrdCheck = true;
      healthcheckCmd = "mount | grep encrypted";
    }
    {
      name = "rofl-10";
      hostname = "rofl-10.brkn.lol";
      hasInitrdCheck = true;
      healthcheckCmd = "mount | grep encrypted";
    }
    {
      name = "rofl-11";
      hostname = "rofl-11.brkn.lol";
      hasInitrdCheck = true;
      healthcheckCmd = "mount | grep encrypted";
    }
    {
      name = "rofl-12";
      hostname = "rofl-12.brkn.lol";
      hasInitrdCheck = true;
      healthcheckCmd = "mount | grep encrypted";
    }
    {
      name = "rofl-13";
      hostname = "rofl-13.brkn.lol";
      hasInitrdCheck = true;
      healthcheckCmd = "mount | grep encrypted";
    }
    {
      name = "rofl-14";
      hostname = "rofl-14.brkn.lol";
      hasInitrdCheck = true;
      healthcheckCmd = "mount | grep encrypted";
    }
  ];

  cfgDirFor = target: target.configDir or "/srv/luks-ssh-unlock/config/${target.name}";

  createInstance =
    target:
    let
      cDir = cfgDirFor target;
    in
    {
      type = "systemd";
      inherit (target) hostname;
      key = "/home/pschmitt/.ssh/id_ed25519";
      passphraseFile = config.sops.secrets."luks/${target.name}/passphrase".path;
      sshKnownHostsFile = "${cDir}/known_hosts";
      initrdKnownHostsFile = "${cDir}/known_hosts_initrd";

      forceIpv4 = true;
      sleepInterval = 30;

      initrdCheck = {
        enable = target.hasInitrdCheck;
        file = "/srv/luks-ssh-unlock/data/initrd-checksum/${target.hostname}/initrd-checksum/checksum";
        paranoid = true;
        requireSignature = true;
      };

      healthcheck = {
        enable = true;
        command = target.healthcheckCmd;
      };

      notifications = {
        enable = true;
        mail = {
          enable = true;
          recipient = config.mainUser.email;
          from = "luks-ssh-unlock <${config.networking.hostName}@${config.domains.main}>";
          subject = "LUKS SSH Unlocker: #hostname -> #event_type";
        };
      };
    };
in
{
  imports = [ inputs.luks-ssh-unlock.nixosModules.default ];

  # SOPS secrets: read LUKS passphrases from each target host's own luks.sops.yaml file
  sops.secrets = lib.listToAttrs (
    map (target: {
      name = "luks/${target.name}/passphrase";
      value = {
        sopsFile = ../hosts/${target.name}/luks.sops.yaml;
        key = "luks/root";
      };
    }) targets
  );

  services.luks-ssh-unlock = {
    enable = true;
    instances = lib.listToAttrs (
      map (target: {
        inherit (target) name;
        value = createInstance target;
      }) targets
    );
  };
}
