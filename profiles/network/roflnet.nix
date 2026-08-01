{
  config,
  pkgs,
  ...
}:
{
  # Configure the provider's recursive resolver as a link-specific DNS scope.
  # The Neutron gateway at 10.69.46.1 does not listen for DNS; the provider
  # resolver also serves the private records registered by Neutron.
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

      ${pkgs.systemd}/bin/resolvectl dns "$interface" 1.1.1.1
      ${pkgs.systemd}/bin/resolvectl domain "$interface" "~${config.domains.roflnet}"
    '';
  };
}
