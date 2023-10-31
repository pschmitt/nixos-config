{ inputs, lib, config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    openconnect
  ];

  systemd.user.services.gec-vpn = {
    description = "GEC VPN";
    path = [
      "${config.custom.homeDirectory}"
      "/run/current-system/sw"
      "/etc/profiles/per-user/${config.custom.username}"
    ];

    serviceConfig = {
      ExecStart = "${config.custom.homeDirectory}/bin/zhj gec::openconnect";
    };

    wantedBy = [ "default.target" ];
  };
}
