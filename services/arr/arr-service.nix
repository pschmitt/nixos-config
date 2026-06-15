# Shared scaffold for "arr" services that live inside the Mullvad VPN namespace.
#
# Each service declares `arr.services.<name>` with its port and public host; this
# module generates the bits that were copy-pasted across every arr service file:
#   - vpnNamespaces.mullvad.portMappings entry
#   - fakeHosts.<name> local proxy entry
#   - nginx virtualHost (Authelia-protected) when `host` is set
#   - monit health check (group piracy, restart-then-alert)
#   - systemd unit wiring into arr.target plus Mullvad confinement
#
# App-specific config (the service/container definition, sops API keys, recyclarr,
# tmpfiles, restic, ...) stays in the per-service file and merges with what this
# module adds to the same systemd unit.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    mkIf
    types
    ;

  cfg = config.arr.services;
  enabled = lib.filterAttrs (_: s: s.enable) cfg;

  internalIP = config.vpnNamespaces.mullvad.namespaceAddress;
  autheliaConfig = import ../authelia-nginx-config.nix { inherit config; };

  # Systemd unit that actually runs the service: the container's generated unit
  # for OCI services, otherwise the service name itself.
  unitOf =
    name: s:
    if s.container != null then
      config.virtualisation.oci-containers.containers.${s.container}.serviceName
    else
      name;

  nginxVhost = _name: s: {
    name = s.host;
    value = {
      serverAliases = s.aliases;
      enableACME = true;
      # FIXME https://github.com/NixOS/nixpkgs/issues/210807
      acmeRoot = null;
      forceSSL = true;
      extraConfig = autheliaConfig.server;
      locations."/" = {
        proxyPass = "http://${internalIP}:${toString s.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
        extraConfig = autheliaConfig.location;
      };
    };
  };

  monitCheck =
    name: s:
    let
      requestLine = lib.optionalString (s.monit.request != null) "\n    request \"${s.monit.request}\"";
    in
    ''
      check host "${s.monit.name}" with address ${internalIP}
        group piracy
        depends on mullvad-netns
        restart program = "${pkgs.systemd}/bin/systemctl restart ${unitOf name s}"
        if failed port ${toString s.port}
          protocol http${requestLine}
          with timeout 15 seconds
          for 3 cycles
        then restart
        if 3 restarts within 5 cycles then alert
    '';

  systemdUnit =
    name: s:
    if s.container != null then
      {
        ${unitOf name s} = {
          wantedBy = [ "arr.target" ];
          partOf = [ "arr.target" ];
          after = [ "mullvad.service" ];
          requires = [ "mullvad.service" ];
        };
      }
    else
      {
        ${name} = {
          wantedBy = [ "arr.target" ];
          partOf = [ "arr.target" ];
          vpnConfinement = {
            enable = true;
            vpnNamespace = "mullvad";
          };
          # Fix for systemd-resolved atomic updates breaking bind mounts
          serviceConfig.TemporaryFileSystem = "/run/systemd/resolve";
        };
      };
in
{
  options.arr.dirs = {
    audiobooks = mkOption {
      type = types.str;
      default = "/mnt/data/audiobooks";
      description = "Path to the audiobooks library directory.";
    };
    books = mkOption {
      type = types.str;
      default = "/mnt/data/books";
      description = "Path to the ebooks library directory.";
    };
    downloads = mkOption {
      type = types.str;
      description = "Transmission download directory shared by arr services.";
    };
    videos = mkOption {
      type = types.str;
      default = "/mnt/data/videos";
      description = "Root directory for video content.";
    };
    movies = mkOption {
      type = types.str;
      description = "Path to the movies library directory.";
    };
    tvShows = mkOption {
      type = types.str;
      description = "Path to the TV shows library directory.";
    };
  };

  options.arr.services = mkOption {
    default = { };
    description = "Arr services sharing the Mullvad namespace scaffold.";
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Whether to wire up the shared arr scaffold for this service.";
            };

            port = mkOption {
              type = types.port;
              description = "Upstream port the service listens on inside the namespace.";
            };

            host = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Public nginx virtualHost. When null, no public vhost is created.";
            };

            aliases = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Additional nginx server aliases for `host`.";
            };

            container = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                Name of the `virtualisation.oci-containers.containers` entry backing
                this service. When set, the container's unit is wired into arr.target
                and ordered after mullvad.service instead of using vpnConfinement.
              '';
            };

            monit = {
              name = mkOption {
                type = types.str;
                default = name;
                description = "Name used in the monit check.";
              };
              request = mkOption {
                type = types.nullOr types.str;
                default = "/ping";
                description = "HTTP path probed by monit; null omits the request line.";
              };
            };
          };
        }
      )
    );
  };

  config = lib.mkMerge [
    {
      arr.dirs = {
        downloads = lib.mkDefault (
          config.services.transmission.settings."download-dir"
            or "${config.services.transmission.home}/Downloads"
        );
        movies = lib.mkDefault "${config.arr.dirs.videos}/movies";
        tvShows = lib.mkDefault "${config.arr.dirs.videos}/tv_shows";
      };
    }
    (mkIf (enabled != { }) {
      vpnNamespaces.mullvad.portMappings = lib.mapAttrsToList (_: s: {
        from = s.port;
        to = s.port;
      }) enabled;

      fakeHosts = lib.mapAttrs (_: s: { inherit (s) port; }) enabled;

      services.nginx.virtualHosts = lib.listToAttrs (
        lib.mapAttrsToList nginxVhost (lib.filterAttrs (_: s: s.host != null) enabled)
      );

      services.monit.config = lib.concatStringsSep "\n" (lib.mapAttrsToList monitCheck enabled);

      systemd.services = lib.mkMerge (lib.mapAttrsToList systemdUnit enabled);
    })
  ];
}
