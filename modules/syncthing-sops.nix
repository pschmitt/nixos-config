{ config, lib, ... }:

{
  config =
    let
      cfg = config.custom.syncthing;
      syncthingUser = if cfg.server then "syncthing" else config.mainUser.username;
    in
    lib.mkIf cfg.enable {
      sops.secrets."syncthing/cert" = {
        inherit (config.custom) sopsFile;
        owner = syncthingUser;
        group = syncthingUser;
        mode = "0400";
      };
      sops.secrets."syncthing/key" = {
        inherit (config.custom) sopsFile;
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
