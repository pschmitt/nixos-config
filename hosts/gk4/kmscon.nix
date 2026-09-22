{ lib, pkgs, ... }:
{
  services.kmscon.config = {
    rotate = "right";
    "xkb-keymap" = "${pkgs.custom-keymaps}/share/keymaps/custom/gpdpocket4-de.xkb";
  };

  console.keyMap = lib.mkForce "custom/gpdpocket4-de";
}
