{ lib, ... }:
{
  options.services.harmonia.extraVirtualHosts = lib.mkOption {
    type = lib.types.listOf (
      lib.types.submodule {
        options = {
          domain = lib.mkOption {
            type = lib.types.str;
            description = "Virtual host domain name.";
          };
          basicAuth = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to enable HTTP basic auth for this virtual host.";
          };
        };
      }
    );
    default = [ ];
    description = "Additional Harmonia virtual hosts to define on this machine.";
  };
}
