{
  config,
  lib,
  ...
}:
let
  cfg = config.fakeHosts;
  active = lib.filterAttrs (_: v: v.port != null) cfg;
  localBind = "127.67.42.1";

  vhostList = lib.mapAttrsToList (
    _: value:
    let
      inherit (value) address;
      portStr = toString value.port;
    in
    {
      name = value.host;
      value = {
        enableACME = false;
        forceSSL = false;
        serverName = value.host;
        listenAddresses = [ localBind ];
        locations."/" = {
          proxyPass = "http://${address}:${portStr}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
    }
  ) active;

  vhosts = builtins.listToAttrs vhostList;

  hostEntries = lib.mapAttrsToList (_: value: value.host) active;
in
{
  options.fakeHosts = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            host = lib.mkOption {
              type = lib.types.str;
              default = "${name}.internal";
              description = "Hostname for the local proxy.";
            };
            address = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = config.vpnNamespaces.mullvad.namespaceAddress;
              description = "Upstream address (defaults to Mullvad namespace IP).";
            };
            port = lib.mkOption {
              type = lib.types.port;
              description = "Upstream port.";
            };
          };
        }
      )
    );
    default = { };
    description = "Local-only fake host proxies for Arr services.";
  };

  config = lib.mkIf (hostEntries != [ ]) {
    # Local-only hostnames to reach Arr services inside the Mullvad namespace.
    networking.extraHosts = lib.mkAfter (
      "# Provided by services/arr/fake-hosts.nix\n"
      + lib.concatStringsSep "\n" (map (h: "${localBind} " + h) hostEntries)
      + "\n"
    );

    services.nginx.virtualHosts = vhosts;
  };
}
