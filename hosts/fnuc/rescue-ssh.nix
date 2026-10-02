# Rescue SSH: a second, root-only sshd on port 2222 that still lets you in
# when user.slice is throttled, capped or being killed by systemd-oomd.
# Without PAM, pam_systemd never moves the login into user.slice: the shell
# stays in this service's cgroup, with reserved memory and top CPU/IO weight.
{ config, lib, ... }:
let
  port = 2222;
  configFile =
    lib.pipe
      {
        Port = port;
        HostKey = [
          "/etc/ssh/ssh_host_ed25519_key"
          "/etc/ssh/ssh_host_rsa_key"
        ];
        PidFile = "/run/sshd-rescue.pid";
        UsePAM = "no";
        AllowUsers = "root";
        PermitRootLogin = "prohibit-password";
        AuthorizedKeysFile = "/etc/ssh/authorized_keys.d/%u";
        PasswordAuthentication = "no";
        KbdInteractiveAuthentication = "no";
        UseDNS = "no";
        X11Forwarding = "no";
        AllowTcpForwarding = "no";
        PrintMotd = "no";
      }
      [
        (lib.generators.toKeyValue {
          mkKeyValue = lib.generators.mkKeyValueDefault { } " ";
          listsAsDuplicateKeys = true;
        })
        (builtins.toFile "sshd-rescue.conf")
      ];
in
{
  # Without PAM, sshd refuses "locked" accounts ("!"). "*" is just as
  # password-less (no hash can match it) but not considered locked.
  users.users.root.hashedPassword = lib.mkForce "*";

  systemd.services.sshd-rescue = {
    description = "Rescue SSH daemon (root only, outside user.slice)";
    wantedBy = [ "multi-user.target" ];
    # sshd.service generates the host keys.
    after = [
      "network.target"
      "sshd.service"
    ];
    serviceConfig = {
      ExecStart = "${config.services.openssh.package}/bin/sshd -D -e -f ${configFile}";
      Restart = "always";
      RestartSec = 1;
      MemoryMin = "128M";
      CPUWeight = 1000;
      IOWeight = 1000;
      OOMScoreAdjust = -1000;
    };
  };

  networking.firewall.allowedTCPPorts = [ port ];
}
