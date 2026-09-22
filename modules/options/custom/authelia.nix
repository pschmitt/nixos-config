{ config, lib, ... }:
{
  options.custom.authelia = {
    extraAccessControlRules = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = ''
        Extra access_control rules appended after the built-in rules above (i.e.
        after the mesh-wide bypass), for services defined in other modules on
        this same host (e.g. http-static.nix's blobs.${config.domains.main}
        rules). Modules on other hosts can't use this: each host builds as an
        independent NixOS system, so an option set there never reaches this
        Authelia instance's settings here -- but a same-host module (including
        one contributed by a private flake input also imported on this host)
        can.
      '';
    };

    extraAuthenticatedDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Domains that must be authenticated (policy = "one_factor") even on the
        bypass networks below, for apps with no login of their own that trust
        the reverse proxy for auth (e.g. AUTHENTICATIONMETHOD=External or
        X-Auth-User-style proxy auth). Without this, the mesh-wide bypass rule
        would leave them reachable unauthenticated from anywhere on the mesh.
        Populated by same-host modules (e.g. a private flake input's per-host
        file), same caveat as extraAccessControlRules above.
      '';
    };

    extraTwoFactorDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Domains that must require two-factor authentication even on the mesh,
        for sensitive control-plane applications. These rules are placed before
        the mesh-wide bypass.
      '';
    };
  };
}
