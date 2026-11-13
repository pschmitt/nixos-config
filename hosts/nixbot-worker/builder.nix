# The remote builder role: nixbot's host logs in as nix-remote-builder over
# NetBird and builds through this host's nix daemon.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  boot.kernelParams = [
    "console=tty0"
    # The autoscaler reads the host key from the serial console log.
    "console=ttyS0,115200"
  ];

  networking = {
    # Each worker is named by its creator; netbird.nix sets that OpenStack
    # name as the (transient) hostname at boot.
    hostName = "";
    useNetworkd = true;
  };

  users = {
    mutableUsers = false;
    # No passwords anywhere; logins by SSH key only, and the main user's keys
    # work for every account. nix-remote-builder serves nixbot; agent is for
    # ad-hoc workers (rworker) and also takes the creator's key from the
    # user-data (netbird.nix); the main user (with sudo) is for debugging.
    allowNoPasswordLogin = true;
    groups.nix-remote-builder = { };
    users = {
      ${config.mainUser.username} = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        shell = pkgs.bash;
        openssh.authorizedKeys.keys = config.mainUser.authorizedKeys;
      };
      agent = {
        isNormalUser = true;
        home = "/home/agent";
        shell = pkgs.bash;
        # Plus the creator's keys from the user-data (netbird.nix).
        openssh.authorizedKeys.keys = config.mainUser.authorizedKeys;
        packages = [
          pkgs.git
          pkgs.jq
          pkgs.rsync
          pkgs.tmux
        ];
      };
      nix-remote-builder = {
        isSystemUser = true;
        group = "nix-remote-builder";
        shell = pkgs.bash;
        # Same keys as profiles/base/users/nix-remote-builder.nix.
        openssh.authorizedKeys.keys = config.mainUser.authorizedKeys ++ [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICyWHQNmz85w1IPJIzmK6DFg2T0XOOazVjeymiaCb98 nix-remote-builder@nixos-config"
        ];
      };
    };
  };

  services.openssh = {
    enable = true;
    # Reachable over NetBird only (netbird.nix).
    openFirewall = false;
    hostKeys = [
      {
        type = "ed25519";
        path = "/etc/ssh/ssh_host_ed25519_key";
      }
    ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [
        "nix-remote-builder"
        "agent"
        config.mainUser.username
      ];
    };
    # Keys handed over in the user-data, written at boot (netbird.nix).
    # sshd reads them as the target user, so every path component must be
    # traversable by it (not /run/nixbot-worker, which holds the LUKS key).
    authorizedKeysFiles = [ "/run/ssh-authorized-keys/%u" ];
  };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    # agent: ad-hoc workers belong to one user and are thrown away, so it
    # may use the worker as a remote builder (rworker builder).
    trusted-users = [
      "nix-remote-builder"
      "agent"
    ];
    system-features = [
      "nixos-test"
      "benchmark"
      "big-parallel"
      "kvm"
    ];
    connect-timeout = 5;
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      # nixbot's own store (harmonia on the nixbot host), signing what it
      # hands to the workers.
      "rofl-14:XkEHSleW71wOnEnAcTZnYi/badnlAJAUxt6SIzbYsG8="
    ];
  };

  # Opt-in S3 cache for ad-hoc workers (`rworker up --nix-cache`, `rworker
  # nix-cache NAME`). The client pushes its s3:// substituters, their public
  # keys and the read-only AWS profile into /run/rworker-nix over SSH. The
  # include below is ignored while the file is missing, so a worker without
  # the flag is unchanged and never holds the credentials.
  nix.extraOptions = "!include /run/rworker-nix/nix.conf";
  systemd = {
    services = {
      # The daemon does the substituting, so it needs the credentials.
      nix-daemon.environment.AWS_SHARED_CREDENTIALS_FILE = "/run/rworker-nix/aws-credentials";
      # nix-daemon reads its configuration only at start. agent has no sudo,
      # so a path unit (root) restarts the daemon when the client replaces
      # nix.conf. The client pushes the credentials first, nix.conf last.
      rworker-nix-config = {
        description = "Restart nix-daemon for the cache settings pushed by rworker";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${config.systemd.package}/bin/systemctl restart nix-daemon.service";
        };
      };
    };
    paths.rworker-nix-config = {
      description = "Cache settings pushed by rworker";
      wantedBy = [ "multi-user.target" ];
      pathConfig.PathChanged = "/run/rworker-nix/nix.conf";
    };
  };

  # Print the SSH host key to the serial console. The autoscaler fetches it
  # through the OpenStack API (console log), so it never has to trust a key
  # on first use.
  systemd.services.nixbot-worker-announce-host-key = {
    description = "Print the SSH host key to the serial console";
    wantedBy = [ "multi-user.target" ];
    after = [ "sshd.service" ];
    wants = [ "sshd.service" ];
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "tty";
      TTYPath = "/dev/ttyS0";
    };
    script = ''
      key=/etc/ssh/ssh_host_ed25519_key.pub
      for _ in $(seq 1 60)
      do
        [[ -s $key ]] && break
        sleep 1
      done
      printf 'NIXBOT-WORKER-HOSTKEY %s\n' "$(cut -d' ' -f1,2 "$key")"
    '';
  };

  # Homes (ad-hoc work trees, caches) and temporary files live on the
  # encrypted partition too: the root is a 16 GiB tmpfs in RAM, which big
  # compiles (rustc and linker temp files in /tmp) filled up.
  fileSystems =
    lib.mapAttrs
      (_path: dir: {
        device = "/nix/.rw-store/${dir}";
        fsType = "none";
        options = [ "bind" ];
        depends = [ "/nix/.rw-store" ];
        # Mounted in the initrd, so activation creates the homes on it rather
        # than on the tmpfs root underneath.
        neededForBoot = true;
      })
      {
        "/home" = "home";
        "/tmp" = "tmp";
        "/var/tmp" = "var-tmp";
      };
  systemd.tmpfiles.rules = [
    "d /nix/.rw-store/home 0755 root root -"
    "d /nix/.rw-store/tmp 1777 root root -"
    "d /nix/.rw-store/var-tmp 1777 root root -"
    "d /run/rworker-nix 0700 agent users -"
    # rworker's control host writes the worker's own niks3 push token here
    # (as nix-remote-builder); agent reads it.
    "d /run/rworker-niks3 2750 nix-remote-builder users -"
  ];

  # The main user's sudo; there are no passwords to ask for.
  security.sudo.wheelNeedsPassword = false;

  documentation.enable = false;
  environment = {
    defaultPackages = [ ];
    # Small tools every login wants (/run/rworker/metadata.json is JSON),
    # and rworker-metadata, which shows what this worker is.
    systemPackages = [
      pkgs.curl
      pkgs.jq
      (pkgs.writeShellApplication {
        name = "niks3";
        runtimeInputs = [ pkgs.niks3 ];
        text = builtins.readFile ./scripts/niks3.sh;
      })
      (pkgs.writeShellApplication {
        name = "rworker-metadata";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
          pkgs.gawk
          pkgs.iproute2
          pkgs.jq
        ];
        text = builtins.readFile ./scripts/rworker-metadata.sh;
      })
    ];
  };
}
