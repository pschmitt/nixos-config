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
  };
}
