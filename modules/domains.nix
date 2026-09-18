{ lib, config, ... }:

{
  options.domains = {
    main = lib.mkOption {
      type = lib.types.str;
      default = "brkn.lol";
      description = "Main domain";
    };

    netbird = lib.mkOption {
      type = lib.types.str;
      default = "nb.${config.domains.main}";
      description = "Domain used for Netbird hosts";
    };

    tailscale = lib.mkOption {
      type = lib.types.str;
      default = "ts.${config.domains.main}";
      description = "Domain used for Tailscale hosts";
    };

    vpn = lib.mkOption {
      type = lib.types.str;
      default = "vpn.${config.domains.main}";
      description = "Domain used for VPN hosts";
    };

    roflnet = lib.mkOption {
      type = lib.types.str;
      default = "roflnet.internal";
      description = "Domain used for hosts on the OpenStack rofl network";
    };

    mesh = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        config.domains.tailscale
        config.domains.netbird
        config.domains.vpn
      ];
      description = ''
        Domains whose names resolve to a host's own mesh addresses. Reaching a
        service through one of these actually routes over the mesh, unlike the
        main domain, whose records point at the WAN address and hairpin.
      '';
    };
  };

  options.custom.meshHosts = lib.mkOption {
    type = lib.types.functionTo (lib.types.listOf lib.types.str);
    description = ''
      Given a service name, the <name>.<host>.<mesh domain> hostname on each
      mesh network, for use as an nginx virtual host plus serverAliases.
      Authelia bypasses these for requests that actually come from the mesh
      (see services/authelia.nix), so a service exposed under them needs no
      login there while staying authenticated everywhere else.
    '';
  };

  config.custom.meshHosts =
    name: map (meshDomain: "${name}.${config.networking.hostName}.${meshDomain}") config.domains.mesh;
}
