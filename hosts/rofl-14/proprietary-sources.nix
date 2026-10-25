# nixbot builds the proprietary packages here; their `requireFile` sources
# come from the password-protected blobs host (dedicated `nixbot` user).
{ config, pkgs, ... }:
{
  imports = [ ../../services/nix-proprietary-sources.nix ];

  sops = {
    secrets."blobs/nixbot-password" = config.sops.mkHostSecret { };
    templates.blobs-netrc.content = ''
      machine blobs.${config.domains.main}
      login nixbot
      password ${config.sops.placeholder."blobs/nixbot-password"}
    '';
  };

  services.nix-proprietary-sources = {
    enable = true;
    packages = with pkgs; [
      ComicCode
      ComicCodeNF
      MonoLisa
      MonoLisa-Custom
      MonoLisa-CustomNF
      MonoLisaNF
      falcon-sensor-wiit
    ];
    netrcFile = config.sops.templates.blobs-netrc.path;
  };
}
