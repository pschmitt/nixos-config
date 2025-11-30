{
  config,
  inputs,
  pkgs,
  ...
}:

{
  imports = [
    inputs.vpn-confinement.nixosModules.default
  ];

  # Define the secret for the VPN config
  sops.secrets."mullvad/config" = {
    inherit (config.custom) sopsFile;
  };

  # Define the VPN namespace
  vpnNamespaces.mullvad = {
    enable = true;
    wireguardConfigFile = config.sops.secrets."mullvad/config".path;

    # Allow access from local network
    accessibleFrom = [
      # NOTE This routes Mullvad DNS (10.64.0.1) to the local network instead of the VPN
      # "10.0.0.0/8"

      # Tailscale/Netbird CGNAT range
      "100.64.0.0/10"
    ];

    portMappings = [
      # {
      #   from = 8989;
      #   to = 8989;
      # } # Sonarr
    ];
  };

  systemd.services.vpn-test = {
    description = "VPN Test Service";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
    };
    vpnConfinement = {
      enable = true;
      vpnNamespace = "mullvad";
    };
  };
}
