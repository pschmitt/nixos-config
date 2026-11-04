# The remote builder role: nixbot's host logs in as nix-remote-builder over
# NetBird and builds through this host's nix daemon.
{ pkgs, ... }:
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
    # Nobody logs in interactively: no root or wheel access at all, only
    # nix-remote-builder.
    allowNoPasswordLogin = true;
    groups.nix-remote-builder = { };
    users.nix-remote-builder = {
      isSystemUser = true;
      group = "nix-remote-builder";
      shell = pkgs.bash;
      # Same key as profiles/base/users/nix-remote-builder.nix.
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIICyWHQNmz85w1IPJIzmK6DFg2T0XOOazVjeymiaCb98 nix-remote-builder@nixos-config"
      ];
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
      AllowUsers = [ "nix-remote-builder" ];
    };
  };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [ "nix-remote-builder" ];
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

  documentation.enable = false;
  environment.defaultPackages = [ ];
}
