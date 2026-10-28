{ config, ... }:
let
  sshOptions = [
    "IdentityFile=${config.mainUser.homeDirectory}/.ssh/id_ed25519"
    "IdentitiesOnly=yes"
    "StrictHostKeyChecking=no"
    "UserKnownHostsFile=/dev/null"
    "ServerAliveInterval=10"
  ];

  vpnDomain = config.domains.vpn;
in
{
  services.sshfs.mounts = {
    fnuc = {
      mountPoint = "/mnt/fnuc";
      host = "fnuc.${vpnDomain}";
      extraOptions = sshOptions;
    };

    ha-dieppe = {
      mountPoint = "/mnt/ha-dieppe";
      host = "homeassistant-dieppe.${vpnDomain}";
      path = "/homeassistant";
      extraOptions = sshOptions;
    };

    oci-01 = {
      mountPoint = "/mnt/oci-01";
      host = "oci-01.${vpnDomain}";
      extraOptions = sshOptions;
    };

    turris = {
      mountPoint = "/mnt/turris";
      host = "turris.${vpnDomain}";
      extraOptions = sshOptions;
    };

    # wrt1900ac = {
    #   mountPoint = "/mnt/wrt1900ac";
    #   host = "wrt1900ac.${vpnDomain}";
    #   extraOptions = sshOptions;
    # };

    rofl-10 = {
      mountPoint = "/mnt/rofl-10";
      host = "rofl-10.${vpnDomain}";
      user = "pschmitt";
      path = "/mnt/data";
      extraOptions = sshOptions;
    };

    rofl-11 = {
      mountPoint = "/mnt/rofl-11";
      host = "rofl-11.${vpnDomain}";
      user = "pschmitt";
      path = "/mnt/data";
      extraOptions = sshOptions;
    };
  };
}
