{ config, lib, ... }:

{
  config =
    let
      cfg = config.services.syncthing.declarative;
      syncthingUser = if cfg.server then "syncthing" else config.mainUser.username;
    in
    lib.mkIf cfg.enable {
      sops.secrets."syncthing/cert" = config.sops.mkHostSecret {
        owner = syncthingUser;
        group = syncthingUser;
        mode = "0400";
      };
      sops.secrets."syncthing/key" = config.sops.mkHostSecret {
        owner = syncthingUser;
        group = syncthingUser;
        mode = "0400";
      };

      services.syncthing = {
        key = config.sops.secrets."syncthing/key".path;
        cert = config.sops.secrets."syncthing/cert".path;
      };
    };
}
