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
      hasInitrdCheck = true;
      # fnuc/lrz's dm-crypt mappers are named "encrypted"/"data-encrypted"
      # (see their disk-config.nix), not "luks-*" like gk4 -- "grep luks"
      # never matches, so the healthcheck (and therefore
      # fetch_initrd_checksum) never succeeds.
      healthcheckCmd = "mount | grep -v tmpfs | grep encrypted";
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
      name = "lrz";
      hostname = "lrz.lan";
      hasInitrdCheck = true;
      healthcheckCmd = "mount | grep -v tmpfs | grep encrypted";
      dhcpListener = {
        enable = true;
        interface = "any";
        clientHostname = "lrz";
      };
    }
    {
      name = "oci-01";
      hostname = "oci-01.brkn.lol";
      # oci-01 was migrated from Ubuntu to full NixOS; it now has its own
      # initrd SSH host keys and is unlockable like the rest of the fleet.
      hasInitrdCheck = true;
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

  # By default, each importing host unlocks every other fleet member.
  fleetConfig = config.services.luks-ssh-unlock-fleet;
  otherTargets = lib.filter (
    target:
    target.name != config.networking.hostName
    && (fleetConfig.targetNames == null || lib.elem target.name fleetConfig.targetNames)
  ) targets;

  # Most importers authenticate as themselves with the personal key. Cloud
  # hosts that shouldn't hold a copy of it override this option instead (see
  # hosts/rofl-10/default.nix); its public half is trusted below via
  # users.users.root.openssh.authorizedKeys.keys.
  selfSshKey = config.services.luks-ssh-unlock-fleet.selfKeyPath;

  # Every target's own secrets.sops.yaml already backs up its regular and
  # initrd SSH host public keys (recorded there for disaster recovery), but
  # that file also holds unrelated per-host secrets (personal SSH private
  # key, tokens, ...) with a recipient list scoped to that host alone --
  # widening it so other fleet members could decrypt just the pubkeys would
  # over-grant access to everything else in it. luks.sops.yaml is already
  # narrowly scoped to LUKS-unlock material and already lists exactly the
  # hosts that need it (fnuc, lrz, rofl-10 -- the only importers of this
  # module), so the pubkeys are copied there instead (same bytes, correctly
  # scoped file) and referenced from there, rendered via sops.templates so a
  # target's key rotation flows through automatically (with a matching
  # service restart) instead of relying on a hand-bootstrapped file under
  # /srv.
  luksSecretsFile =
    target: inputs.nixos-config-private.outPath + "/hosts/${target.name}/luks.sops.yaml";

  pubkeySecret = target: keySet: algo: {
    name = "ssh/${target.name}/${keySet}/${algo}/pubkey";
    value = {
      sopsFile = luksSecretsFile target;
      key = "ssh/${keySet}/${algo}/pubkey";
    };
  };

  secretsForTarget =
    target:
    [
      {
        name = "luks/${target.name}/passphrase";
        value = {
          sopsFile = luksSecretsFile target;
          key = "luks/root";
        };
      }
      (pubkeySecret target "host_keys" "ed25519")
      (pubkeySecret target "host_keys" "rsa")
    ]
    ++ lib.optionals target.hasInitrdCheck [
      (pubkeySecret target "initrd_host_keys" "ed25519")
      (pubkeySecret target "initrd_host_keys" "rsa")
    ];

  # A known_hosts line just needs "<hostname> <keytype> <base64key>"; the
  # backed-up pubkey secrets are already full "<keytype> <base64key> ..."
  # lines, so prefixing the target's connection hostname is enough.
  knownHostsTemplate =
    target: keySet:
    lib.concatMapStringsSep "\n"
      (
        algo: "${target.hostname} " + config.sops.placeholder."ssh/${target.name}/${keySet}/${algo}/pubkey"
      )
      [
        "ed25519"
        "rsa"
      ]
    + "\n";

  templatesForTarget =
    target:
    [
      {
        name = "luks-ssh-unlock/${target.name}/known_hosts";
        value = {
          content = knownHostsTemplate target "host_keys";
          restartUnits = [ "luks-ssh-unlock-${target.name}.service" ];
        };
      }
    ]
    ++ lib.optionals target.hasInitrdCheck [
      {
        name = "luks-ssh-unlock/${target.name}/known_hosts_initrd";
        value = {
          content = knownHostsTemplate target "initrd_host_keys";
          restartUnits = [ "luks-ssh-unlock-${target.name}.service" ];
        };
      }
    ];

  createInstance = target: {
    type = "systemd";
    inherit (target) hostname;
    key = selfSshKey;
    passphraseFile = config.sops.secrets."luks/${target.name}/passphrase".path;
    sshKnownHostsFile = config.sops.templates."luks-ssh-unlock/${target.name}/known_hosts".path;
    initrdKnownHostsFile =
      if target.hasInitrdCheck then
        config.sops.templates."luks-ssh-unlock/${target.name}/known_hosts_initrd".path
      else
        null;
    jumpHost =
      if fleetConfig.jumpHost == null then
        null
      else
        {
          inherit (fleetConfig.jumpHost) hostname username port;
          enable = true;
          key = if fleetConfig.jumpHost.key == null then selfSshKey else fleetConfig.jumpHost.key;
        };

    forceIpv4 = true;
    sleepInterval = 30;

    dhcpListener = target.dhcpListener or { };

    initrdCheck = {
      enable = target.hasInitrdCheck;
      # `dir` is where a fresh signed baseline gets scp'd to on every
      # successful healthcheck (fetch_initrd_checksum); the module derives
      # the read-back path (`file`) from dir+hostname automatically.
      dir = "/srv/luks-ssh-unlock/data/initrd-checksum";
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

  config = {
    assertions = [
      {
        assertion =
          fleetConfig.targetNames == null
          || lib.all (name: lib.elem name (map (target: target.name) targets)) fleetConfig.targetNames;
        message = "services.luks-ssh-unlock-fleet.targetNames contains an unknown fleet target.";
      }
    ];

    # Fleet-internal trust: rofl-10's dedicated unlock identity (see the
    # services.luks-ssh-unlock-fleet.selfKeyPath override in hosts/rofl-10) is
    # authorized as root on every fleet member.
    users.users.root.openssh.authorizedKeys.keys = lib.mkAfter [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcHlgZc+nNUPw2rg90jjov7mvNL8CMbeHgvMygtDJAq rofl-10-luks-ssh-unlock"
    ];

    # SOPS secrets: LUKS passphrase and SSH host pubkeys from each target
    # host's own private files.
    sops.secrets = lib.listToAttrs (lib.concatMap secretsForTarget otherTargets);

    # Rendered known_hosts files, one pair (regular + initrd) per target.
    sops.templates = lib.listToAttrs (lib.concatMap templatesForTarget otherTargets);

    services.luks-ssh-unlock = {
      enable = true;
      instances = lib.listToAttrs (
        map (target: {
          inherit (target) name;
          value = createInstance target;
        }) otherTargets
      );
    };
  };
}
