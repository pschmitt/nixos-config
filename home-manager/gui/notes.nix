{ pkgs, ... }:
let
  obsidian = pkgs.obsidian.overrideAttrs (oldAttrs: {
    nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
    postFixup = (oldAttrs.postFixup or "") + ''
      wrapProgram $out/bin/obsidian \
        --add-flags "--password-store=gnome-libsecret"
    '';
  });
in
{
  home.packages = [ obsidian ];
}
