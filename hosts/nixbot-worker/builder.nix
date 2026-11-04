# The remote builder role: nixbot's host logs in as nix-remote-builder over
# NetBird and builds through this host's nix daemon.
{ config, pkgs, ... }:
{
  boot.kernelParams = [
    "console=tty0"
    # The autoscaler reads the host key from the serial console log.
    "console=ttyS0,115200"
  ];

  networking = {
    # The autoscaler names each worker; the hostname comes from DHCP.
    hostName = "";
    useNetworkd = true;
  };

  users = {
    mutableUsers = false;
    # No passwords anywhere; logins by SSH key only. nix-remote-builder
    # serves nixbot; agent is for ad-hoc workers (rworker) and only
    # usable when the user-data hands it an SSH key (netbird.nix); the main
    # user (with sudo) is there for debugging.
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
        # Same key as profiles/base/users/nix-remote-builder.nix.
        openssh.authorizedKeys.keys = [
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
    authorizedKeysFiles = [ "/run/nixbot-worker/authorized_keys/%u" ];
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

  # Homes (ad-hoc work trees, caches) live on the encrypted partition too.
  fileSystems."/home" = {
    device = "/nix/.rw-store/home";
    fsType = "none";
    options = [ "bind" ];
    depends = [ "/nix/.rw-store" ];
  };
  systemd.tmpfiles.rules = [ "d /nix/.rw-store/home 0755 root root -" ];

  # The main user's sudo; there are no passwords to ask for.
  security.sudo.wheelNeedsPassword = false;

  documentation.enable = false;
  environment.defaultPackages = [ ];
}
