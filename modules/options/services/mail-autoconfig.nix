{ config, lib, ... }:
{
  options.services.mail-autoconfig.domain = lib.mkOption {
    type = lib.types.str;
    default = config.domains.main;
    description = "Domain served by the mail client autoconfiguration endpoint.";
  };
}
