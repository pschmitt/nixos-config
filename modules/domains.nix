{ lib, config, ... }:

{
  options.domains = {
    main = lib.mkOption {
      type = lib.types.str;
      default = "brkn.lol";
      description = "Main domain";
    };

    netbirdDomain = lib.mkOption {
      type = lib.types.str;
      default = "nb.${config.domains.main}";
      description = "Domain used for Netbird hosts";
    };

    tailscaleDomain = lib.mkOption {
      type = lib.types.str;
      default = "ts.${config.domains.main}";
      description = "Domain used for Tailscale hosts";
    };
  };
}
