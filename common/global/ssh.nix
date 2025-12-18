{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Helper to build hostnames across all known suffixes
  mkHostnames = host: [
    host
    "${host}.lan"
    "${host}.${config.domains.main}"
    "${host}.vpn.${config.domains.main}"
    "${host}.${config.domains.netbird}"
    "${host}.${config.domains.tailscale}"
    "${host}.snake-eagle.ts.net"
    "${host}.netbird.cloud"
  ];

  # NOTE ssh-hosts.generated.json is generated using ./secrets/ssh-gen-known-hosts.sh
  generatedHostKeys =
    let
      p = ./ssh-hosts.generated.json;
    in
    if builtins.pathExists p then builtins.fromJSON (builtins.readFile p) else { };

  # Default map of hosts to their pubkeys
  defaultHostKeys = {
    fnuc = {
      ed25519 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMUasZ5NmpBE1LDa/sdD4F9dhlB4DpCUY0g2kQpSCmfo";
      rsa = "fnuc ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCxPqTGClmwptv+dPHd0NBFmpp4WjVP8/D1r3rFu6d/JDQ6/hk5PWqu+dGrNLh5FLamNXRK5LWG2LDftCGC2lAcTWzFqIt9PDT019vj/idpBpZd/PQOwnQ03YED1IsPH+KVHjp9PG/VkNL1m2FdHciCvz9bh/U5DFvAiCzhCGgNB2JdGvEL3gi9TXTQx95vMNCc0bvEF1KNZV+VGhxIwdTT2Y/CKtcjkZUc+ERa/jhZ3mmdMSvubvMyKfrpQ3GO9PNEb1To0OybjcgmbpuJpXbAAtnyJIxurSm+Mwx1KAxVtoi/40Fp2MDuLjN2R96iqRpLjihwxaBZN/J3Slc4BIkWYB6EhI6vPTHS5ZaanrnmFQw/HzQnNKegZMr8oilj1iw+IpTC78mIvGQXQdHfxPWAbTebTgeYTDOFLZWA0LUfqLHX6Z72o4thm1UBSYa3Hs+IOsBSVNuwMBpvdxcGzJoTN7WFj4XLtxqIIc3Epe4yuyZCwgwLHAqvBJZkYmVPYb8=";
    };
  };

  # Merge generated keys (if any) over defaults
  hostKeys = generatedHostKeys // defaultHostKeys;

  # Turn a host + keys into knownHosts entries for available key types
  mkKnownHostEntries =
    host: keys:
    let
      hostNames = mkHostnames host;
      types = builtins.filter (t: builtins.hasAttr t keys) [
        "ed25519"
        "rsa"
      ];
      mk = typ: {
        name = "${host}-${typ}";
        value = {
          inherit hostNames;
          publicKey = keys.${typ};
        };
      };
    in
    builtins.map mk types;

  # Flatten all host entries to a single list and build attrset
  generatedHosts = builtins.listToAttrs (
    builtins.concatLists (
      builtins.map (h: mkKnownHostEntries h hostKeys.${h}) (builtins.attrNames hostKeys)
    )
  );
in
{
  # OpenSSH server
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = true;
      PermitRootLogin = "prohibit-password";
      # Let clients pick the bind address (e.g. 0.0.0.0)
      GatewayPorts = "clientspecified";
    };
    sftpServerExecutable = "internal-sftp";
    extraConfig = ''
      AcceptEnv TERM_SSH_CLIENT
    '';
  };

  # https://github.com/nix-community/srvos/blob/main/nixos/common/well-known-hosts.nix
  # Avoid TOFU MITM with known forges.
  programs.ssh.knownHosts = {
    "github.com".hostNames = [ "github.com" ];
    "github.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";

    "gitlab.com".hostNames = [ "gitlab.com" ];
    "gitlab.com".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf";

    "git.sr.ht".hostNames = [ "git.sr.ht" ];
    "git.sr.ht".publicKey =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMZvRd4EtM7R+IHVMWmDkVU3VLQTSwQDSAvW0t2Tkj60";
  }
  // generatedHosts;

  networking.firewall = {
    allowedTCPPorts = lib.mkBefore [ 22 ];
    allowedUDPPortRanges = [
      {
        # mosh
        from = 60000;
        to = 61000;
      }
    ];
  };

  environment.systemPackages = with pkgs; [
    autossh
    mosh
    sshfs
    sshpass
  ];

  users.users.root.openssh.authorizedKeys.keys = config.mainUser.authorizedKeys;

  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    # pinentryPackage = pkgs.pinentry-gnome3;
    enableSSHSupport = true;
  };
}
