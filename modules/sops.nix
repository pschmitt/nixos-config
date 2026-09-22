{
  config,
  inputs,
  lib,
  ...
}:

{
  options.sops = {
    hostSopsFile = lib.mkOption {
      type = lib.types.path;
      default =
        inputs.nixos-config-private.outPath + "/hosts/${config.networking.hostName}/secrets.sops.yaml";
      description = "Host-specific SOPS file (overrides the shared default).";
    };

    mkHostSecret = lib.mkOption {
      type = lib.types.raw;
      internal = true;
      readOnly = true;
      description = ''
        Helper for declaring a secret stored in the host-specific sops file
        (`sops.hostSopsFile`), rather than the shared default set in
        `profiles/base/sops.nix`.

        Usage:
          sops.secrets."foo/bar" = config.sops.mkHostSecret { };
          sops.secrets."foo/baz" = config.sops.mkHostSecret { owner = "svc"; };
      '';
    };
  };

  config.sops.mkHostSecret = attrs: { sopsFile = config.sops.hostSopsFile; } // attrs;
}
