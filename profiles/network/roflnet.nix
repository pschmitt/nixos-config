{
  config,
  pkgs,
  ...
}:
{
  # Configure the Neutron DHCP resolver as a link-local DNS scope.  Public DNS
  # remains the global resolver for all other names.
  systemd.services.roflnet-dns = {
    description = "Configure roflnet split DNS";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "systemd-resolved.service"
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      interface="$(${pkgs.iproute2}/bin/ip -o route show default | ${pkgs.gawk}/bin/awk '$1 == "default" { print $5; exit }')"

      if [[ -z "$interface" ]]
      then
        echo "Could not determine the default-route interface" >&2
        exit 1
      fi

      ${pkgs.systemd}/bin/resolvectl dns "$interface" 10.69.46.1
      ${pkgs.systemd}/bin/resolvectl domain "$interface" "~${config.domains.roflnet}"
    '';
  };
}
