{ lib, config, ... }:

{
  options.custom = {
    sopsFile = lib.mkOption {
      type = lib.types.path;
      default = ../hosts/${config.networking.hostName}/secrets.sops.yaml;
      description = "Host-specific SOPS file (overrides the shared default).";
    };

    mkSecret = lib.mkOption {
      type = lib.types.raw;
      internal = true;
      readOnly = true;
      description = ''
        Helper for declaring a secret stored in the host-specific sops file
        (`custom.sopsFile`), rather than the shared default set in
        `common/global/sops.nix`.

        Usage:
          sops.secrets."foo/bar" = config.custom.mkSecret { };
          sops.secrets."foo/baz" = config.custom.mkSecret { owner = "svc"; };
      '';
    };
  };

  config.custom.mkSecret = attrs: { inherit (config.custom) sopsFile; } // attrs;
}
